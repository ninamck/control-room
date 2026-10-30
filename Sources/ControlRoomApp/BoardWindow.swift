import AppKit
import SwiftUI

/// The board as an ordinary window. While it's open Control Room shows in the Dock and Cmd-Tab;
/// closed, it goes back to being just the companion.
@MainActor
final class BoardWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let form = HandOffForm()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    /// Hand off and End of day open in the board window, in place of the board, never a window of their own.
    func show(_ page: BoardPage = .board) {
        model.boardPage = page
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Control Room"
            window.contentView = NSHostingView(rootView: BoardRoot(model: model, form: form))
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

    /// From the panel, the board or End of day. A put-off ticket's title comes along as the brief,
    /// and that ticket goes once the hand-off starts, so the work isn't listed twice.
    func showHandOff(brief: String?, replacing: String?) {
        if let brief { form.brief = brief }
        form.replaces = replacing
        show(.handOff)
    }

    func windowWillClose(_ notification: Notification) {
        model.boardOpen = false
        WindowPolicy.update(closing: window)
    }

    func windowDidMiniaturize(_ notification: Notification) { model.boardOpen = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.boardOpen = true }
}

enum BoardPage { case board, handOff, endOfDay }

/// What the board window shows: the board, or Hand off or End of day in its place.
struct BoardRoot: View {
    @ObservedObject var model: AppModel
    let form: HandOffForm

    var body: some View {
        switch model.boardPage {
        case .board: BoardView(model: model)
        case .handOff: HandOffView(model: model, form: form) { model.boardPage = .board }
        case .endOfDay: EndOfDayView(model: model) { model.boardPage = .board }
        }
    }
}
