import AppKit
import Combine
import ControlRoomCore

/// Everything the companion and panel show, kept current from the ticket store.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var now = Date()
    @Published var panelOpen = false {
        didSet { if panelOpen != oldValue { updateSecondHand() } }
    }
    /// Whether the board window is on screen.
    @Published var boardOpen = false {
        didSet { if boardOpen != oldValue { updateSecondHand() } }
    }
    /// Opens the board window. Set by the app at launch.
    var openBoard: () -> Void = {}
    /// Opens Hand off, optionally with a brief already written (from End of day). Set by the app at launch.
    var openHandOffWith: (_ brief: String?, _ replacing: String?) -> Void = { _, _ in }

    /// Opens Hand off. From End of day it carries the put-off ticket's title, and that ticket is
    /// removed once the hand-off starts, so the work isn't listed twice.
    func openHandOff(_ brief: String?, replacing: String? = nil) {
        openHandOffWith(brief, replacing)
    }

    /// The Ready to delegate list from Notion, and why it's empty if something's wrong.
    @Published private(set) var ready: [NotionReady.Item] = []
    @Published private(set) var readyProblem: String?
    @Published private(set) var readyLoading = false
    let places = PlaceBook()
    /// Set when Devin can't be reached or refuses the token, shown at the top of the panel.
    @Published private(set) var devinProblem: String?
    private var devinTimer: Timer?
    private var devinPolling = false

    /// While the panel or board is showing running agents, keep "3s ago" counting.
    /// Otherwise nothing ticks faster than every 20s.
    private func updateSecondHand() {
        secondHand?.invalidate()
        secondHand = nil
        guard panelOpen || boardOpen else { return }
        now = Date()
        secondHand = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.workingCount > 0, self.boardOpen || self.showWorking else { return }
                self.now = Date()
            }
        }
    }
    private var secondHand: Timer?
    /// Whether the panel lists what's working under the Working count. Remembered between opens.
    @Published var showWorking = false
    /// Set when the local server couldn't start, shown at the top of the panel.
    @Published private(set) var serverProblem: String?

    let store: TicketStore
    private var server: HTTPServer?
    private var clock: Timer?

    /// Remembered settings (quiet, End of day shown). Snapshots pass their own so they never touch Nina's.
    let defaults: UserDefaults

    init(store: TicketStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        quietUntil = defaults.object(forKey: "quietUntil") as? Date
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
        startCalendar()
        // Catch up on anything Cursor sent while the app was closed.
        EventQueue.drain(into: store)
        reload()
        // Minutes tick over, Later tickets come back, done expires at midnight, and any stray queued events land.
        // Devin has no hooks, so ask it every 30 seconds: quick enough to notice, gentle on its API.
        pollDevin()
        devinTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollDevin() }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                EventQueue.drain(into: self.store)
                self.reload()
                self.calendar.refresh()
            }
        }
    }

    func reload() {
        now = Date()
        // Scheduled runs whose time has come land as cards first.
        try? watchList.land(into: store, now: now)
        tickets = (try? store.all()) ?? tickets
        watched = watchList.tasks
        openEndOfDayIfDue()
    }

    // MARK: What to show

    /// Waiting on Nina: needs_you and blocked, oldest first. Blocked never clears on its own.
    var waiting: [Ticket] {
        tickets.filter { $0.state == .needsYou || $0.state == .blocked }
            .sorted { $0.stateSince < $1.stateSince }
    }

    /// Running agents, longest running first.
    var working: [Ticket] {
        tickets.filter { $0.state == .working }.sorted { $0.stateSince < $1.stateSince }
    }

    var workingCount: Int { working.count }

    /// Finished today, most recent first.
    var done: [Ticket] {
        tickets.filter { $0.state == .done }.sorted { $0.stateSince > $1.stateSince }
    }

    var doneCount: Int { done.count }

    var face: Face {
        if panelOpen { return .expanded }
        return restingFace
    }

    /// The face as it would be with the panel closed: what's waiting, not whether it's being looked at.
    var restingFace: Face {
        // Quiet: asleep whatever is waiting. No colour change, no animation (SPEC section 4).
        if isQuiet { return .asleep }
        // Scheduled output never wakes the companion.
        let wakers = waiting.filter { $0.kind == .interactive }
        if wakers.contains(where: { $0.signal(at: now) == .coral }) { return .overdue }
        if !wakers.isEmpty { return .needsYou }
        return .asleep
    }

    // MARK: Calendar

    /// The next busy event today (SPEC section 5), and why it's missing if the calendar can't be read.
    @Published private(set) var hardStop: HardStop?
    @Published private(set) var calendarProblem: String?
    private let calendar = CalendarWatch()

    private func startCalendar() {
        calendar.onChange = { [weak self] stop, problem in
            self?.hardStop = stop
            self?.calendarProblem = problem
        }
        calendar.start()
    }

    // MARK: Scheduled

    let watchList = WatchList()
    /// The watch list as last read, for the views.
    @Published private(set) var watched: [WatchedTask] = []
    /// Opens the reader pane for a scheduled result. Set by the app at launch.
    var openReader: (Ticket) -> Void = { _ in }

    /// Landed scheduled results waiting to be read, oldest first.
    var landed: [Ticket] { waiting.filter { $0.kind == .scheduled } }
    /// Waiting on Nina, without scheduled results (which get their own block on the board).
    var decisions: [Ticket] { waiting.filter { $0.kind == .interactive } }

    /// The next scheduled run, for the morning board.
    var nextScheduled: (task: WatchedTask, at: Date)? {
        watched.compactMap { task in task.nextRun(after: now).map { (task, $0) } }.min { $0.1 < $1.1 }
    }

    func watch(_ task: WatchedTask) {
        watchList.add(task)
        reload()
    }

    func stopWatching(_ id: String) {
        watchList.remove(id)
        reload()
    }

    /// Read it: the result is Done and the watch list notes the run was fine.
    func markRead(_ ticket: Ticket) {
        try? watchList.markRead(ticket, store: store)
        reload()
    }

    func markMissed(_ ticket: Ticket) {
        try? watchList.markMissed(ticket, store: store)
        reload()
    }

    /// Read: the full text in the reader pane when there is some, otherwise wherever the results live.
    func read(_ ticket: Ticket) {
        if ticket.lastMessage.isEmpty { open(ticket) } else { openReader(ticket) }
    }

    // MARK: Quiet

    /// Until when the companion stays asleep. Kept across restarts.
    @Published private(set) var quietUntil: Date?

    var isQuiet: Bool { (quietUntil ?? .distantPast) > now }

    func quiet(minutes: Int) {
        setQuiet(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// +25 or +50 on the time already set.
    func extendQuiet(minutes: Int) {
        setQuiet(until: max(quietUntil ?? Date(), Date()).addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func wake() { setQuiet(until: nil) }

    func setQuiet(until date: Date?) {
        quietUntil = date
        defaults.set(date, forKey: "quietUntil")
        now = Date()
    }

    // MARK: End of day

    /// Opens End of day. Set by the app at launch.
    var openEndOfDay: () -> Void = {}

    var endOfDay: EndOfDay { EndOfDay(tickets: tickets, now: now) }

    /// When End of day opens by itself today (18:30 unless changed in config.local.json).
    private var endOfDayTime: Date? {
        let setting = (try? Config.loadOrCreate())?.endOfDay ?? "18:30"
        let parts = setting.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)
    }

    /// Opens End of day once, at its time, on days there's something to look back on.
    private func openEndOfDayIfDue() {
        guard let due = endOfDayTime, now >= due else { return }
        let today = Calendar.current.startOfDay(for: now)
        if let last = defaults.object(forKey: "endOfDayShown") as? Date, last >= today { return }
        defaults.set(now, forKey: "endOfDayShown")
        let summary = endOfDay
        guard !summary.done.isEmpty || !summary.waiting.isEmpty || !summary.putOff.isEmpty else { return }
        openEndOfDay()
    }

    /// Close the day: anything still waiting goes quiet until 9, Done clears, and the companion sleeps until 9.
    func closeTheDay() {
        let nine = Rules.nextNineAM(after: Date())
        _ = try? store.update { tickets, now in
            for i in tickets.indices where tickets[i].state == .needsYou && !EndOfDay.isPutOff(tickets[i], now: now) {
                try tickets[i].apply(.tomorrow, now: now)
            }
            tickets.removeAll { $0.state == .done }
        }
        setQuiet(until: nine)
        reload()
    }

    /// Drop deletes the ticket, and unticks Agent in Notion if it came from Task Tracker (DECISIONS.md).
    func drop(_ ticket: Ticket) {
        _ = try? store.drop(ticket.id)
        reload()
        guard let page = ticket.notionPage, let token = (try? Config.loadOrCreate())?.notionToken else { return }
        Task {
            do { try await NotionReady.untickAgent(page: page, token: token) }
            catch { readyProblem = error.localizedDescription }
        }
    }

    /// Removes a ticket without touching Notion (a put-off ticket that's now been handed off).
    func removeTicket(_ id: String) {
        _ = try? store.drop(id)
        reload()
    }

    // MARK: Hand off

    /// Folders to offer in Where, most recently used first.
    var handOffPlaces: [String] { places.list(seenIn: tickets) }

    func loadReady() {
        guard let config = try? Config.loadOrCreate(), let token = config.notionToken, !token.isEmpty else {
            ready = []
            readyProblem = "Not connected to Notion yet. Run `cr set-notion-token` in Terminal to connect it."
            return
        }
        readyLoading = true
        Task {
            do {
                let items = try await NotionReady.fetch(token: token, dataSource: config.notionDataSource ?? NotionReady.taskTracker)
                ready = items
                readyProblem = nil
            } catch {
                readyProblem = error.localizedDescription
            }
            readyLoading = false
        }
    }

    /// Go. Returns a message for Nina if it couldn't start, or nil once a Working ticket exists.
    func handOff(brief: String, tool: Tool, folder: String?, notionPage: String?) -> String? {
        let brief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return "Write a brief first." }
        switch tool {
        case .claudeCode:
            guard let folder else { return "Pick a project folder for Claude to work in." }
            guard let claude = Launcher.claudeCode() else {
                return "Claude Code isn't installed on this Mac yet. Run Anthropic's installer once in Terminal: curl -fsSL https://claude.ai/install.sh | bash"
            }
            let session = UUID().uuidString.lowercased()
            do {
                try Launcher.startClaudeCode(claude, brief: brief, folder: folder, sessionID: session)
            } catch {
                return "Couldn't open Terminal: \(error.localizedDescription)"
            }
            _ = try? store.add(HandOff.ticket(tool: .claudeCode, brief: brief, folder: folder, sessionID: session, notionPage: notionPage))
        case .cursor:
            guard let folder else { return "Pick the project to open in Cursor." }
            Launcher.copy(brief)
            openInCursor(folder: URL(fileURLWithPath: folder))
            _ = try? store.add(HandOff.ticket(tool: .cursor, brief: brief, folder: folder, notionPage: notionPage))
        case .grok:
            Launcher.copy(brief)
            NSWorkspace.shared.open(URL(string: "https://grok.com")!)
            _ = try? store.add(HandOff.ticket(tool: .grok, brief: brief, folder: nil, notionPage: notionPage))
        case .devin:
            guard let devin = devinAccount else { return "Not connected to Devin yet. Run `cr set-devin-token` in Terminal to connect it." }
            let store = self.store
            Task {
                do {
                    let session = try await DevinAPI(token: devin.token).create(prompt: brief, org: devin.org)
                    var ticket = HandOff.ticket(tool: .devin, brief: brief, folder: nil, notionPage: notionPage)
                    ticket.source = .automatic
                    ticket.externalId = "devin:\(session.id)"
                    ticket.deepLink = session.url
                    ticket.activity = "Starting up"
                    ticket.activityAt = Date()
                    _ = try? store.add(ticket)
                } catch {
                    devinProblem = "Devin didn't start the hand-off: \(error.localizedDescription)"
                }
                reload()
            }
            return nil
        case .claudeAI:
            return "Pick Claude, Cursor or Grok."
        }
        if let folder { places.record(folder, tool: tool) }
        reload()
        return nil
    }

    // MARK: Devin

    private var devinAccount: (token: String, org: String, user: String)? {
        guard let config = try? Config.loadOrCreate(), let token = config.devinToken,
              let org = config.devinOrg, let user = config.devinUser else { return nil }
        return (token, org, user)
    }

    func pollDevin() {
        guard let devin = devinAccount, !devinPolling else { return }
        devinPolling = true
        let store = self.store
        let current = tickets
        Task {
            do {
                let api = DevinAPI(token: devin.token)
                let sessions = try await api.sessions(org: devin.org, user: devin.user)
                var messages: [String: (devin: String?, nina: String?)] = [:]
                for session in DevinFeed.needsMessages(sessions, in: current, now: Date()).prefix(10) {
                    messages[session.id] = try? await api.lastMessages(org: devin.org, session: session.id)
                }
                try DevinFeed.apply(sessions, messages: messages, store: store)
                devinProblem = nil
            } catch {
                devinProblem = error.localizedDescription
            }
            devinPolling = false
        }
    }

    // MARK: Quick replies

    struct Reply {
        let label: String
        let answer: String
        let affirmative: Bool
    }

    /// The answer buttons for a ticket, or nil if it should only offer Open (SPEC section 6, Quick replies):
    /// the tool takes messages, the agent is waiting at an ordinary reply, and it asked yes/no or pick one.
    /// Claude Code only when it was started by Hand off, so the answer can be typed into its own Terminal window.
    func quickReplies(for ticket: Ticket) -> [Reply]? {
        guard ticket.state == .needsYou, ticket.quickReplyReady == true else { return nil }
        switch ticket.tool {
        case .devin: guard devinAccount != nil else { return nil }
        case .claudeCode: guard let session = ticket.claudeSessionID, Launcher.handOffTerminal(for: session) != nil else { return nil }
        default: return nil
        }
        switch ticket.questionType {
        case .yesNo:
            return [Reply(label: "YES", answer: "Yes", affirmative: true), Reply(label: "NOT YET", answer: "No, not yet", affirmative: false)]
        case .choice(let options) where (2...4).contains(options.count):
            return options.enumerated().map { n, option in
                Reply(label: "\(n + 1) · \(option.uppercased())", answer: option, affirmative: false)
            }
        default:
            return nil
        }
    }

    /// Sends a quick reply. If it can't be sent the ticket turns blocked with the reason, no toast (SPEC section 6).
    func quickReply(_ ticket: Ticket, _ answer: String) {
        switch ticket.tool {
        case .devin:
            guard let devin = devinAccount, let session = ticket.externalId?.replacingOccurrences(of: "devin:", with: "") else { return }
            replied(ticket, answer)
            Task {
                do { try await DevinAPI(token: devin.token).send(answer, org: devin.org, session: session) }
                catch { failed(ticket, error) }
            }
        case .claudeCode:
            guard let session = ticket.claudeSessionID else { return }
            do {
                try Launcher.type(answer, intoClaudeSession: session)
                replied(ticket, answer)
            } catch {
                failed(ticket, error)
            }
        default:
            return
        }
    }

    private func replied(_ ticket: Ticket, _ answer: String) {
        _ = try? store.update { tickets, now in
            guard let i = tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
            tickets[i].quickReplyReady = false
            tickets[i].questionType = .none
            tickets[i].activity = "Reading your reply: \(answer)"
            tickets[i].activityAt = now
            try tickets[i].apply(.stillRunning, now: now)
        }
        reload()
    }

    private func failed(_ ticket: Ticket, _ error: Error) {
        _ = try? store.update { tickets, now in
            guard let i = tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
            tickets[i].lastMessage = "Your quick reply didn't send: \(error.localizedDescription)"
            tickets[i].quickReplyReady = false
            tickets[i].activity = nil
            try tickets[i].apply(.blocked, now: now)
        }
        reload()
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
        let thread = parsed.link.flatMap(QuickAdd.threadName(forLink:)) ?? ""
        _ = try? store.add(Ticket(tool: tool, source: .manual, title: parsed.title, thread: thread, deepLink: parsed.link ?? ""))
        reload()
        return true
    }

    func open(_ ticket: Ticket) {
        // Cursor always opens the app on this Mac, never cursor.com, and goes to the project's window when it knows the folder.
        if ticket.tool == .cursor {
            openInCursor(folder: QuickAdd.localFolder(ticket.deepLink))
            return
        }
        // Claude Code goes back to wherever the session runs: Cursor's terminal (that project's window),
        // the Claude desktop app, or the terminal app it was started from.
        if ticket.tool == .claudeCode, ticket.source == .automatic {
            switch ticket.hostApp {
            case Self.cursorID: openInCursor(folder: QuickAdd.localFolder(ticket.deepLink))
            case let app?: openApp(app, fallback: "https://claude.ai")
            case nil: openApp("com.anthropic.claudefordesktop", fallback: "https://claude.ai")
            }
            return
        }
        if let url = URL(string: ticket.deepLink), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return
        }
        // No link: open the tool itself.
        switch ticket.tool {
        case .cursor: openInCursor(folder: nil)
        case .claudeAI, .claudeCode: openApp("com.anthropic.claudefordesktop", fallback: "https://claude.ai")
        case .grok: NSWorkspace.shared.open(URL(string: "https://grok.com")!)
        case .devin: NSWorkspace.shared.open(URL(string: "https://app.devin.ai")!)
        }
    }

    static let cursorID = "com.todesktop.230313mzl4w4u92"

    /// Opening a folder that's already open in Cursor brings that window to the front.
    func openInCursor(folder: URL?) {
        guard let cursor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.cursorID) else { return }
        if let folder, FileManager.default.fileExists(atPath: folder.path) {
            // Cursor's own `cursor` command opens the folder in the editor window (or brings that window
            // forward). Asking macOS to open the folder with Cursor lands in its Agents window instead.
            let command = cursor.appendingPathComponent("Contents/Resources/app/bin/cursor")
            if FileManager.default.isExecutableFile(atPath: command.path) {
                let run = Process()
                run.executableURL = command
                run.arguments = [folder.path]
                if (try? run.run()) != nil { return }
            }
            NSWorkspace.shared.open([folder], withApplicationAt: cursor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.openApplication(at: cursor, configuration: .init())
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
