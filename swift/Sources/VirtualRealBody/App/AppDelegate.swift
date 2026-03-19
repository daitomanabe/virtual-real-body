import AppKit
import Satin

final class EscapeWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NSApplication.shared.terminate(nil)
            return
        }
        super.keyDown(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: EscapeWindow?
    private var controller: MetalViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let renderer = MainRenderer()
        let controller = MetalViewController(renderer: renderer)
        self.controller = controller

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 2560, height: 720)
        let window = EscapeWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces, .stationary]
        window.level = .mainMenu
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller)
        window.setFrame(screenFrame, display: true)
        window.toggleFullScreen(nil)

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
