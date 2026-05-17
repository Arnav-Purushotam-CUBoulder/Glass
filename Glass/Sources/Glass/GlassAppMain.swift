import AppKit
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
    private var activeSpaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installObservers()
        viewModel.refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        scheduleInitialWindowBootstrap()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringWindowsToFront()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
                self?.rebuildOverlayWindows()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bringWindowsToFront()
            }
        }
    }

    private func scheduleInitialWindowBootstrap() {
        DispatchQueue.main.async { [weak self] in
            self?.rebuildOverlayWindows()
            self?.bringWindowsToFront()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if self.overlayWindows.isEmpty {
                self.rebuildOverlayWindows()
                self.bringWindowsToFront()
            }
        }
    }

    private func rebuildOverlayWindows() {
        let currentScreens = NSScreen.screens
        guard !currentScreens.isEmpty else { return }
        let currentIDs = Set(currentScreens.map(screenID(for:)))

        for screen in currentScreens {
            let id = screenID(for: screen)
            if let existingWindow = overlayWindows[id] {
                position(existingWindow, on: screen)
                existingWindow.orderFrontRegardless()
            } else {
                let window = makeOverlayWindow(for: screen)
                overlayWindows[id] = window
                if overlayWindows.count == 1 {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    window.orderFrontRegardless()
                }
            }
        }

        let staleIDs = Set(overlayWindows.keys).subtracting(currentIDs)
        for id in staleIDs {
            if let window = overlayWindows[id] {
                window.delegate = nil
                window.orderOut(nil)
                window.close()
            }
            overlayWindows.removeValue(forKey: id)
        }
    }

    private func bringWindowsToFront() {
        for (id, window) in overlayWindows {
            if let screen = NSScreen.screens.first(where: { screenID(for: $0) == id }) {
                position(window, on: screen)
            }
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let content = GlassRootView(model: viewModel)
        let hostingView = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: frame(for: screen),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
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
        window.level = .statusBar
        window.sharingType = .none
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
        window.contentView = hostingView
        window.delegate = self
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeGlassWindow(_:))
        position(window, on: screen)
        return window
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
}
