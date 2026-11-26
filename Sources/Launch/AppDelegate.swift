import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var windowController: LauncherWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.reloadApps()
        model.onDismiss = {
            NSApp.terminate(nil)
        }
        let controller = LauncherWindowController(model: model)
        windowController = controller
        controller.showWindow(nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if windowController?.window?.isVisible == true {
            sender.terminate(nil)
            return false
        }
        return true
    }
}

final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private var allowsResignTermination = false
    private var isUpdatingDock = false
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 885, height: 681),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Launch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.isOpaque = true
        window.hasShadow = true
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 680, height: 480)
        window.contentView = NSHostingView(rootView: LauncherView(model: model))
        super.init(window: window)
        window.delegate = self
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.terminateAfterResign()
        }
        model.onDockUpdateBegan = { [weak self] in
            self?.isUpdatingDock = true
            self?.allowsResignTermination = false
        }
        model.onDockUpdateEnded = { [weak self] in
            self?.finishDockUpdate()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        positionOnActiveScreen()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.enableResignTermination()
        }
    }

    private func positionOnActiveScreen() {
        guard let window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let frame = screen?.frame else { return }

        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func terminateAfterResign() {
        guard allowsResignTermination, !isUpdatingDock else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.allowsResignTermination, !self.isUpdatingDock else { return }
            if NSApp.modalWindow != nil { return }
            NSApp.terminate(nil)
        }
    }

    private func finishDockUpdate() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.isUpdatingDock = false
            self.enableResignTermination()
        }
    }

    private func enableResignTermination() {
        allowsResignTermination = true
        if !NSApp.isActive {
            terminateAfterResign()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
