import AppKit
import Combine
import ControlRoomCore

/// Everything the companion and panel show, kept current from the ticket store.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var now = Date()
    @Published var panelOpen = false
    /// Set when the local server couldn't start, shown at the top of the panel.
    @Published private(set) var serverProblem: String?

    let store: TicketStore
    private var server: HTTPServer?
    private var clock: Timer?

    init(store: TicketStore) {
        self.store = store
        store.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    /// Starts the local server so `cr` and the feeds can reach the store.
    func startServer(config: Config) {
        let api = API(store: store, token: config.token)
        do {
            let server = try HTTPServer(port: config.port) { api.handle($0) }
            server.start { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.serverProblem = "The local server couldn't start (\(error.localizedDescription)). If cr serve is running in Terminal, stop it with Ctrl+C and reopen Control Room."
                }
            }
            self.server = server
        } catch {
            serverProblem = "The local server couldn't start: \(error.localizedDescription)"
        }
        reload()
        // Minutes tick over, Later tickets come back, done expires at midnight.
        clock = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        now = Date()
        tickets = (try? store.all()) ?? tickets
    }

    // MARK: What to show

    /// Waiting on Nina: needs_you and blocked, oldest first. Blocked never clears on its own.
    var waiting: [Ticket] {
        tickets.filter { $0.state == .needsYou || $0.state == .blocked }
            .sorted { $0.stateSince < $1.stateSince }
    }

    var workingCount: Int { tickets.filter { $0.state == .working }.count }
    var doneCount: Int { tickets.filter { $0.state == .done }.count }

    var face: Face {
        if panelOpen { return .expanded }
        // Scheduled output never wakes the companion.
        let wakers = waiting.filter { $0.kind == .interactive }
        if wakers.contains(where: { $0.signal(at: now) == .coral }) { return .overdue }
        if !wakers.isEmpty { return .needsYou }
        return .asleep
    }

    // MARK: Actions

    func apply(_ action: TicketAction, to ticket: Ticket) {
        _ = try? store.apply(action, to: ticket.id)
        reload()
    }

    /// Adds a ticket from the quick-add field. Returns false if the tool or title is missing.
    @discardableResult
    func quickAdd(_ text: String, tool chosen: Tool?) -> Bool {
        let parsed = QuickAdd.parse(text)
        guard let tool = chosen ?? parsed.tool, !parsed.title.isEmpty else { return false }
        _ = try? store.add(Ticket(tool: tool, source: .manual, title: parsed.title, deepLink: parsed.link ?? ""))
        reload()
        return true
    }

    func open(_ ticket: Ticket) {
        if let url = URL(string: ticket.deepLink), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return
        }
        // No link: open the tool itself.
        switch ticket.tool {
        case .cursor: openApp("com.todesktop.230313mzl4w4u92", fallback: "https://cursor.com")
        case .claudeAI, .claudeCode: openApp("com.anthropic.claudefordesktop", fallback: "https://claude.ai")
        case .grok: NSWorkspace.shared.open(URL(string: "https://grok.com")!)
        case .devin: NSWorkspace.shared.open(URL(string: "https://app.devin.ai")!)
        }
    }

    private func openApp(_ bundleID: String, fallback: String) {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else {
            NSWorkspace.shared.open(URL(string: fallback)!)
        }
    }
}
