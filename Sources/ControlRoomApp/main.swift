import AppKit
import ControlRoomCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var companion: Companion?
    private var board: BoardWindow?
    private var handOff: HandOffWindow?
    private var endOfDay: EndOfDayWindow?
    private var reader: ReaderWindow?

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
            let companion = Companion(model: model)
            let board = BoardWindow(model: model)
            let handOff = HandOffWindow(model: model)
            model.openBoard = { [weak companion, weak board] in
                companion?.collapse()
                board?.show()
            }
            let endOfDay = EndOfDayWindow(model: model)
            let reader = ReaderWindow(model: model)
            model.openReader = { [weak reader] ticket in reader?.show(ticket) }
            model.openHandOffWith = { [weak companion, weak handOff] brief, replacing in
                companion?.collapse()
                handOff?.show(brief: brief, replacing: replacing)
            }
            model.openEndOfDay = { [weak companion, weak endOfDay] in
                companion?.collapse()
                endOfDay?.show()
            }
            // Started once everything above is connected, so End of day can open even if the app starts after 18:30.
            model.startServer(config: config)
            companion.start()
            startAtLogin()
            self.model = model
            self.companion = companion
            self.board = board
            self.handOff = handOff
            self.endOfDay = endOfDay
            self.reader = reader
        } catch {
            let alert = NSAlert()
            alert.messageText = "Control Room couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Starts Control Room when Nina logs in, once it's installed in Applications (not test builds).
    /// She can switch it off in System Settings → General → Login Items.
    private func startAtLogin() {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix("\(home)/Applications/") || path.hasPrefix("/Applications/") else { return }
        let login = SMAppService.mainApp
        // Only the first time: if she turns it off in System Settings, it stays off.
        guard login.status == .notRegistered, !UserDefaults.standard.bool(forKey: "askedToStartAtLogin") else { return }
        UserDefaults.standard.set(true, forKey: "askedToStartAtLogin")
        try? login.register()
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
