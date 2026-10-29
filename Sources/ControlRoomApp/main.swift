import AppKit
import ControlRoomCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var companion: Companion?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerBundledFonts()
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
            companion.start()
            self.model = model
            self.companion = companion
        } catch {
            let alert = NSAlert()
            alert.messageText = "Control Room couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // No Dock icon: the companion is the whole interface.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
