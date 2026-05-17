import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct GlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var overlayWindows: [String: NSWindow] = [:]
    private let viewModel = GlassViewModel()
    private var screenObserver: NSObjectProtocol?
    private var hotKeyHandler: EventHandlerRef?
    private var openHotKeyRef: EventHotKeyRef?
    private var closeHotKeyRef: EventHotKeyRef?
    private var localKeyMonitor: Any?

    private let hotKeySignature = fourCharCode("GLAS")
    private let openHotKeyIdentifier: UInt32 = 1
    private let closeHotKeyIdentifier: UInt32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installObservers()
        installHotKeys()
        viewModel.refreshPermissions()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if overlayWindows.isEmpty {
            openOverlayOnCurrentScreen(triggerAnalysis: false, activateApp: true)
        } else {
            bringWindowsToFront(activateApp: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeGlassWindow(sender)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel.stopImmediatelyForQuit()
        return .terminateNow
    }

    @objc private func closeGlassWindow(_ sender: Any?) {
        viewModel.stopImmediatelyForQuit()
        NSApp.terminate(nil)
    }

    private func installObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeStaleWindowsForDisconnectedDisplays()
            }
        }

    }

    private func installHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event,
                      let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                delegate.handleHotKeyPress(hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandler
        )

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            switch characters {
            case "u":
                self.openOverlayOnCurrentScreen(triggerAnalysis: true, activateApp: false)
                return nil
            case "i":
                self.closeOverlayOnCurrentScreen()
                return nil
            default:
                return event
            }
        }

        openHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_U),
            modifiers: UInt32(cmdKey),
            identifier: openHotKeyIdentifier
        )
        closeHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_I),
            modifiers: UInt32(cmdKey),
            identifier: closeHotKeyIdentifier
        )
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, identifier: UInt32) -> EventHotKeyRef? {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr else { return nil }
        return ref
    }

    private func handleHotKeyPress(_ identifier: UInt32) {
        switch identifier {
        case openHotKeyIdentifier:
            openOverlayOnCurrentScreen(triggerAnalysis: true, activateApp: false)
        case closeHotKeyIdentifier:
            closeOverlayOnCurrentScreen()
        default:
            break
        }
    }

    private func openOverlayOnCurrentScreen(triggerAnalysis: Bool, activateApp: Bool) {
        guard let screen = currentScreen() else { return }
        let id = screenID(for: screen)

        for (otherID, window) in overlayWindows where otherID != id {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
            overlayWindows.removeValue(forKey: otherID)
        }

        let window: NSWindow
        if let existingWindow = overlayWindows[id] {
            window = existingWindow
            position(window, on: screen)
        } else {
            let newWindow = makeOverlayWindow(for: screen)
            overlayWindows[id] = newWindow
            window = newWindow
        }

        applyStealthMode(to: window)
        viewModel.setFocusedDisplayID(displayID(for: screen))
        present(window, activateApp: activateApp)

        guard triggerAnalysis else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.analyzeCurrentScreen()
        }
    }

    private func closeOverlayOnCurrentScreen() {
        guard let screen = currentScreen() else {
            destroyOverlayWindows()
            return
        }

        let id = screenID(for: screen)
        if let window = overlayWindows[id] {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
            overlayWindows.removeValue(forKey: id)
        } else {
            destroyOverlayWindows()
        }
    }

    private func closeStaleWindowsForDisconnectedDisplays() {
        let validIDs = Set(NSScreen.screens.map(screenID(for:)))
        for id in Set(overlayWindows.keys).subtracting(validIDs) {
            if let window = overlayWindows[id] {
                window.delegate = nil
                window.orderOut(nil)
                window.close()
            }
            overlayWindows.removeValue(forKey: id)
        }
    }

    private func destroyOverlayWindows() {
        for window in overlayWindows.values {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }

    private func bringWindowsToFront(activateApp: Bool) {
        for (id, window) in overlayWindows {
            if let screen = NSScreen.screens.first(where: { screenID(for: $0) == id }) {
                position(window, on: screen)
            }
            applyStealthMode(to: window)
            present(window, activateApp: activateApp)
        }
    }

    private func applyStealthMode(to window: NSWindow) {
        guard NSApp.windows.contains(window) else { return }
        window.sharingType = .none
    }

    private func present(_ window: NSWindow, activateApp: Bool) {
        applyStealthMode(to: window)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let content = GlassRootView(model: viewModel)
        let hostingView = NSHostingView(rootView: content)

        let window = GlassOverlayPanel(
            contentRect: frame(for: screen),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Glass"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = .statusBar
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient, .ignoresCycle]
        window.contentView = hostingView
        window.delegate = self
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeGlassWindow(_:))
        position(window, on: screen)
        return window
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func position(_ window: NSWindow, on screen: NSScreen) {
        window.setFrame(frame(for: screen), display: true)
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let horizontalInset: CGFloat = 24
        let verticalInset: CGFloat = 26
        let targetWidth = min(1480, visible.width - horizontalInset * 2)
        let width = min(visible.width - 12, max(700, targetWidth))
        let targetHeight = min(860, visible.height - 56)
        let height = min(visible.height - 12, max(560, targetHeight))
        let x = visible.midX - (width / 2)
        let y = visible.maxY - height - verticalInset
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "\(screen.localizedName)-\(screen.frame.debugDescription)"
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}

final class GlassOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private func fourCharCode(_ string: StaticString) -> OSType {
    string.withUTF8Buffer { buffer in
        buffer.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
