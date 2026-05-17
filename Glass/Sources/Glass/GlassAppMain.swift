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
    private var overlayOffsets: [String: CGSize] = [:]
    private let viewModel = GlassViewModel()
    private var screenObserver: NSObjectProtocol?
    private var hotKeyHandler: EventHandlerRef?
    private var openHotKeyRef: EventHotKeyRef?
    private var closeHotKeyRef: EventHotKeyRef?
    private var responseHotKeyRef: EventHotKeyRef?
    private var cppResponseHotKeyRef: EventHotKeyRef?
    private var meetingHotKeyRef: EventHotKeyRef?
    private var moveUpHotKeyRef: EventHotKeyRef?
    private var moveLeftHotKeyRef: EventHotKeyRef?
    private var moveDownHotKeyRef: EventHotKeyRef?
    private var moveRightHotKeyRef: EventHotKeyRef?
    private var scrollUpHotKeyRef: EventHotKeyRef?
    private var scrollDownHotKeyRef: EventHotKeyRef?
    private var localKeyMonitor: Any?
    private var movementRepeatTimer: Timer?
    private var movementRepeatStartWorkItem: DispatchWorkItem?
    private var activeMovementIdentifier: UInt32?

    private let hotKeySignature = fourCharCode("GLAS")
    private let openHotKeyIdentifier: UInt32 = 1
    private let closeHotKeyIdentifier: UInt32 = 2
    private let responseHotKeyIdentifier: UInt32 = 3
    private let cppResponseHotKeyIdentifier: UInt32 = 4
    private let meetingHotKeyIdentifier: UInt32 = 5
    private let moveUpHotKeyIdentifier: UInt32 = 6
    private let moveLeftHotKeyIdentifier: UInt32 = 7
    private let moveDownHotKeyIdentifier: UInt32 = 8
    private let moveRightHotKeyIdentifier: UInt32 = 9
    private let scrollUpHotKeyIdentifier: UInt32 = 10
    private let scrollDownHotKeyIdentifier: UInt32 = 11
    private let requiredHotKeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    private let carbonHotKeyModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    private let overlayNudgeStep: CGFloat = 48
    private let movementRepeatDelay: TimeInterval = 0.18
    private let movementRepeatInterval: TimeInterval = 0.045

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
        stopContinuousMovement()
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
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        _ = eventTypes.withUnsafeMutableBufferPointer { buffer in
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
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        delegate.handleHotKeyRelease(hotKeyID.id)
                    } else {
                        delegate.handleHotKeyPress(hotKeyID.id)
                    }
                    return noErr
                },
                buffer.count,
                buffer.baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &hotKeyHandler
            )
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == self.requiredHotKeyModifiers else {
                return event
            }

            switch Int(event.keyCode) {
            case kVK_ANSI_E:
                return nil
            case kVK_ANSI_Q:
                return nil
            case kVK_ANSI_R:
                return nil
            case kVK_ANSI_C:
                return nil
            case kVK_ANSI_F:
                return nil
            case kVK_ANSI_W:
                return nil
            case kVK_ANSI_A:
                return nil
            case kVK_ANSI_S:
                return nil
            case kVK_ANSI_D:
                return nil
            case kVK_UpArrow:
                return nil
            case kVK_DownArrow:
                return nil
            default:
                return event
            }
        }

        openHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: carbonHotKeyModifiers,
            identifier: openHotKeyIdentifier
        )
        closeHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: carbonHotKeyModifiers,
            identifier: closeHotKeyIdentifier
        )
        responseHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: carbonHotKeyModifiers,
            identifier: responseHotKeyIdentifier
        )
        cppResponseHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: carbonHotKeyModifiers,
            identifier: cppResponseHotKeyIdentifier
        )
        meetingHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: carbonHotKeyModifiers,
            identifier: meetingHotKeyIdentifier
        )
        moveUpHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: carbonHotKeyModifiers,
            identifier: moveUpHotKeyIdentifier
        )
        moveLeftHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: carbonHotKeyModifiers,
            identifier: moveLeftHotKeyIdentifier
        )
        moveDownHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: carbonHotKeyModifiers,
            identifier: moveDownHotKeyIdentifier
        )
        moveRightHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: carbonHotKeyModifiers,
            identifier: moveRightHotKeyIdentifier
        )
        scrollUpHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: carbonHotKeyModifiers,
            identifier: scrollUpHotKeyIdentifier
        )
        scrollDownHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: carbonHotKeyModifiers,
            identifier: scrollDownHotKeyIdentifier
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
        case responseHotKeyIdentifier:
            requestAIResponseForCurrentMeeting(preferredCodeLanguage: .python)
        case cppResponseHotKeyIdentifier:
            requestAIResponseForCurrentMeeting(preferredCodeLanguage: .cpp)
        case meetingHotKeyIdentifier:
            toggleMeetingForCurrentScreen()
        case moveUpHotKeyIdentifier, moveLeftHotKeyIdentifier, moveDownHotKeyIdentifier, moveRightHotKeyIdentifier:
            startContinuousMovement(for: identifier)
        case scrollUpHotKeyIdentifier:
            scrollCopilotHistory(.up)
        case scrollDownHotKeyIdentifier:
            scrollCopilotHistory(.down)
        default:
            break
        }
    }

    private func handleHotKeyRelease(_ identifier: UInt32) {
        switch identifier {
        case moveUpHotKeyIdentifier, moveLeftHotKeyIdentifier, moveDownHotKeyIdentifier, moveRightHotKeyIdentifier:
            stopContinuousMovement(for: identifier)
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

        applyCaptureVisibilityMode(to: window)
        viewModel.setFocusedDisplayID(displayID(for: screen))
        present(window, activateApp: activateApp)

        guard triggerAnalysis else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.analyzeCurrentScreen()
        }
    }

    private func requestAIResponseForCurrentMeeting(preferredCodeLanguage: CopilotCodeLanguage) {
        if let screen = currentScreen() {
            viewModel.setFocusedDisplayID(displayID(for: screen))
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.refreshCopilotNow(preferredCodeLanguage: preferredCodeLanguage)
        }
    }

    private func toggleMeetingForCurrentScreen() {
        if overlayWindows.isEmpty {
            openOverlayOnCurrentScreen(triggerAnalysis: false, activateApp: false)
        } else if let screen = currentScreen(),
                  overlayWindows[screenID(for: screen)] == nil {
            openOverlayOnCurrentScreen(triggerAnalysis: false, activateApp: false)
        }

        if let screen = currentScreen() {
            viewModel.setFocusedDisplayID(displayID(for: screen))
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.toggleMeeting()
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

    private func scrollCopilotHistory(_ direction: CopilotScrollDirection) {
        guard !overlayWindows.isEmpty else { return }
        viewModel.requestCopilotScroll(direction)
    }

    private func startContinuousMovement(for identifier: UInt32) {
        performMovement(for: identifier)

        if activeMovementIdentifier == identifier {
            return
        }

        stopContinuousMovement()
        activeMovementIdentifier = identifier

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeMovementIdentifier == identifier else { return }

            let timer = Timer.scheduledTimer(withTimeInterval: self.movementRepeatInterval, repeats: true) { [weak self] timer in
                Task { @MainActor [weak self] in
                    guard let self, self.activeMovementIdentifier == identifier else {
                        self?.stopContinuousMovement(for: identifier)
                        return
                    }
                    self.performMovement(for: identifier)
                }
            }

            RunLoop.main.add(timer, forMode: .common)
            self.movementRepeatTimer = timer
        }

        movementRepeatStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + movementRepeatDelay, execute: workItem)
    }

    private func stopContinuousMovement(for identifier: UInt32? = nil) {
        if let identifier, activeMovementIdentifier != identifier {
            return
        }

        movementRepeatStartWorkItem?.cancel()
        movementRepeatStartWorkItem = nil
        movementRepeatTimer?.invalidate()
        movementRepeatTimer = nil
        activeMovementIdentifier = nil
    }

    private func performMovement(for identifier: UInt32) {
        switch identifier {
        case moveUpHotKeyIdentifier:
            moveOverlayOnCurrentScreen(deltaX: 0, deltaY: overlayNudgeStep)
        case moveLeftHotKeyIdentifier:
            moveOverlayOnCurrentScreen(deltaX: -overlayNudgeStep, deltaY: 0)
        case moveDownHotKeyIdentifier:
            moveOverlayOnCurrentScreen(deltaX: 0, deltaY: -overlayNudgeStep)
        case moveRightHotKeyIdentifier:
            moveOverlayOnCurrentScreen(deltaX: overlayNudgeStep, deltaY: 0)
        default:
            break
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
            overlayOffsets.removeValue(forKey: id)
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
            applyCaptureVisibilityMode(to: window)
            present(window, activateApp: activateApp)
        }
    }

    private func applyCaptureVisibilityMode(to window: NSWindow) {
        guard NSApp.windows.contains(window) else { return }
        window.sharingType = .none
    }

    private func moveOverlayOnCurrentScreen(deltaX: CGFloat, deltaY: CGFloat) {
        guard let screen = currentScreen() else { return }
        let id = screenID(for: screen)
        guard let window = overlayWindows[id] else { return }

        let baseFrame = defaultFrame(for: screen)
        var frame = frame(for: screen)
        frame.origin.x += deltaX
        frame.origin.y += deltaY

        let visibleFrame = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        overlayOffsets[id] = CGSize(
            width: frame.origin.x - baseFrame.origin.x,
            height: frame.origin.y - baseFrame.origin.y
        )
        window.setFrame(frame, display: true)
        present(window, activateApp: false)
    }

    private func present(_ window: NSWindow, activateApp: Bool) {
        applyCaptureVisibilityMode(to: window)
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
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Glass"
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = .statusBar
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient, .ignoresCycle]
        window.contentView = hostingView
        window.delegate = self
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
        let id = screenID(for: screen)
        let base = defaultFrame(for: screen)
        let offset = overlayOffsets[id] ?? .zero
        var frame = base.offsetBy(dx: offset.width, dy: offset.height)
        let visibleFrame = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return frame
    }

    private func defaultFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let horizontalInset: CGFloat = 18
        let verticalInset: CGFloat = 20
        let targetWidth = min(660, visible.width - horizontalInset * 2)
        let width = min(visible.width - 8, max(470, targetWidth))
        let targetHeight = min(980, visible.height - 24)
        let height = min(visible.height - 8, max(820, targetHeight))
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
