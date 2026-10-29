import AppKit
import SwiftUI

/// The board as an ordinary window. While it's open Control Room shows in the Dock and Cmd-Tab;
/// closed, it goes back to being just the companion.
@MainActor
final class BoardWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Control Room"
            window.contentView = NSHostingView(rootView: BoardView(model: model))
            window.contentMinSize = NSSize(width: 960, height: 640)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("ControlRoomBoard")
            if !window.setFrameUsingName("ControlRoomBoard") { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.boardOpen = true
    }

    func windowWillClose(_ notification: Notification) {
        model.boardOpen = false
        WindowPolicy.update(closing: window)
    }

    func windowDidMiniaturize(_ notification: Notification) { model.boardOpen = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.boardOpen = true }
}
