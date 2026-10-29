import AppKit
import ControlRoomCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var companion: Companion?
    private var board: BoardWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerBundledFonts()
        // Light mode only (SPEC section 7), even when the Mac is in dark mode.
        NSApp.appearance = NSAppearance(named: .aqua)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        do {
            let config = try Config.loadOrCreate()
            let model = AppModel(store: try TicketStore())
            model.startServer(config: config)
            let companion = Companion(model: model)
            let board = BoardWindow(model: model)
            model.openBoard = { [weak companion, weak board] in
                companion?.collapse()
                board?.show()
            }
            companion.start()
            self.model = model
            self.companion = companion
            self.board = board
        } catch {
            let alert = NSAlert()
            alert.messageText = "Control Room couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    // Opening Control Room again from Finder or Spotlight while it's running brings up the board.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.openBoard()
        return false
    }

    // Closing the board leaves the companion running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // No Dock icon: the companion is the whole interface.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
