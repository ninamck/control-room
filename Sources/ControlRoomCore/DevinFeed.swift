import Foundation

/// Devin's v3 API (https://docs.devin.ai/api-reference), with a personal access token that acts as Nina.
public struct DevinAPI: Sendable {
    public let token: String
    static let base = "https://api.devin.ai/v3"

    public init(token: String) { self.token = token }

    public struct Me: Sendable {
        public let userID: String
        public let userName: String
        public let orgID: String
    }

    public struct Session: Sendable, Equatable {
        public let id: String
        public let url: String
        public let title: String?
        public let status: String
        public let detail: String?
        public let userID: String?
        public let updatedAt: Date?
        public let pullRequest: String?
    }

    public struct Message: Sendable, Equatable {
        public let fromDevin: Bool
        public let text: String
    }

    public struct Problem: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Who the token belongs to and which organisation their sessions run in.
    public func me() async throws -> Me {
        let json = try await call("GET", "/self")
        guard let user = json["user_id"] as? String,
              let org = (json["devin_sessions_org_id"] ?? json["org_id"]) as? String else {
            throw Problem(message: "Devin didn't say which account this token belongs to. Make a Personal access token, not a service user key.")
        }
        return Me(userID: user, userName: json["user_name"] as? String ?? "you", orgID: org)
    }

    /// Nina's recent sessions. Filtered to her user id here too, in case the token can see the whole team's.
    public func sessions(org: String, user: String) async throws -> [Session] {
        let json = try await call("GET", "/organizations/\(org)/sessions?first=100&is_archived=false&user_ids=\(user)")
        return (json["items"] as? [[String: Any]] ?? []).compactMap(Self.session).filter { $0.userID == nil || $0.userID == user }
    }

    /// The last thing Devin said, and the last thing Nina said, in a session.
    public func lastMessages(org: String, session: String) async throws -> (devin: String?, nina: String?) {
        var after: String?
        var items: [Message] = []
        // Messages come oldest first; walk to the last page.
        for _ in 0..<20 {
            let path = "/organizations/\(org)/sessions/\(session)/messages?first=200" + (after.map { "&after=\($0)" } ?? "")
            let json = try await call("GET", path)
            let page = (json["items"] as? [[String: Any]] ?? []).compactMap { item -> Message? in
                guard let text = item["message"] as? String else { return nil }
                return Message(fromDevin: (item["source"] as? String) == "devin", text: text)
            }
            if !page.isEmpty { items = page }
            guard json["has_next_page"] as? Bool == true, let cursor = json["end_cursor"] as? String else { break }
            after = cursor
        }
        return (items.last { $0.fromDevin }?.text, items.last { !$0.fromDevin }?.text)
    }

    public func send(_ message: String, org: String, session: String) async throws {
        _ = try await call("POST", "/organizations/\(org)/sessions/\(session)/messages", body: ["message": message])
    }

    public func create(prompt: String, org: String) async throws -> Session {
        let json = try await call("POST", "/organizations/\(org)/sessions", body: ["prompt": prompt])
        guard let session = Self.session(json) else { throw Problem(message: "Devin started a session but didn't say which.") }
        return session
    }

    static func session(_ json: [String: Any]) -> Session? {
        guard let id = json["session_id"] as? String else { return nil }
        let updated = (json["updated_at"] as? NSNumber).map { n -> Date in
            // The unit isn't documented: treat big numbers as milliseconds.
            let value = n.doubleValue
            return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
        }
        let pr = (json["pull_requests"] as? [[String: Any]])?.last?["pr_url"] as? String
        return Session(id: id, url: json["url"] as? String ?? "https://app.devin.ai/sessions/\(id)",
                       title: (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                       status: json["status"] as? String ?? "", detail: json["status_detail"] as? String,
                       userID: json["user_id"] as? String, updatedAt: updated, pullRequest: pr)
    }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem(message: "Couldn't reach Devin. Check the internet connection.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let detail = (json["detail"] ?? json["message"] ?? json["error"]).map { "\($0)" } ?? "error \(status)"
            switch status {
            case 401: throw Problem(message: "Devin didn't accept the token. Run `cr set-devin-token` again with a fresh one.")
            case 403: throw Problem(message: "Devin says this token isn't allowed to do that (\(detail)).")
            case 429: throw Problem(message: "Devin asked Control Room to slow down. It'll try again shortly.")
            default: throw Problem(message: "Devin said: \(detail)")
            }
        }
        return json
    }
}

/// Turns Devin's sessions into tickets. A ticket only moves when Devin's status changes,
/// so Nina's Done sticks until Devin does something new.
public enum DevinFeed {
    /// Sessions untouched for longer than this are left alone unless they already have a ticket.
    static let recent: TimeInterval = 24 * 3600

    /// What a session's status means for its ticket.
    enum Meaning: Equatable {
        case working(String)
        case waiting(String?)
        case finished
        case blocked(String)
        case leaveAlone
    }

    static func meaning(status: String, detail: String?) -> Meaning {
        switch (status, detail) {
        case ("new", _), ("claimed", _), ("resuming", _): return .working("Starting up")
        case ("running", "waiting_for_user"): return .waiting(nil)
        case ("running", "waiting_for_approval"): return .waiting("Waiting for your approval")
        case ("running", "finished"), ("exit", _): return .finished
        case ("running", _): return .working("Working")
        case ("error", _): return .blocked("Devin hit an error.")
        // Suspended because it was idle or Nina paused it: nothing new to say.
        case ("suspended", "inactivity"), ("suspended", "user_request"), ("suspended", nil): return .leaveAlone
        case ("suspended", let reason?): return .blocked("Devin stopped: \(reason.replacingOccurrences(of: "_", with: " ")).")
        default: return .leaveAlone
        }
    }

    /// Which sessions need their messages read this round: new waits and finishes.
    public static func needsMessages(_ sessions: [DevinAPI.Session], in tickets: [Ticket], now: Date) -> [DevinAPI.Session] {
        sessions.filter { session in
            let key = "\(session.status)/\(session.detail ?? "")"
            let ticket = tickets.first { $0.externalId == "devin:\(session.id)" }
            guard ticket?.feedStatus != key else { return false }
            if ticket == nil, let updated = session.updatedAt, now.timeIntervalSince(updated) > recent { return false }
            switch meaning(status: session.status, detail: session.detail) {
            case .waiting, .finished: return true
            case .leaveAlone: return false
            default: return ticket == nil  // a new ticket's title comes from Nina's message
            }
        }
    }

    /// Applies one poll. `messages` holds the last messages for sessions listed by `needsMessages`.
    @discardableResult
    public static func apply(_ sessions: [DevinAPI.Session], messages: [String: (devin: String?, nina: String?)],
                             store: TicketStore) throws -> [Ticket] {
        try store.update { tickets, now in
            var touched: [Ticket] = []
            for session in sessions {
                let key = "devin:\(session.id)"
                let status = "\(session.status)/\(session.detail ?? "")"
                let meaning = meaning(status: session.status, detail: session.detail)
                var index = tickets.firstIndex { $0.externalId == key }
                if index == nil {
                    // Only recent sessions that are doing something get a ticket.
                    if let updated = session.updatedAt, now.timeIntervalSince(updated) > recent { continue }
                    if meaning == .leaveAlone { continue }
                    let asked = messages[session.id]?.nina.flatMap(FeedText.title(from:)) ?? session.title ?? "Devin session"
                    var ticket = Ticket(tool: .devin, source: .automatic, title: asked, deepLink: session.url,
                                        state: .working, stateSince: now)
                    ticket.externalId = key
                    tickets.append(ticket)
                    index = tickets.count - 1
                }
                let i = index!
                if let title = session.title { tickets[i].chatName = title }
                if let asked = messages[session.id]?.nina.flatMap(FeedText.title(from:)) { tickets[i].title = asked }
                guard tickets[i].feedStatus != status else { continue }
                tickets[i].feedStatus = status

                switch meaning {
                case .working(let what):
                    tickets[i].activity = what
                    tickets[i].activityAt = now
                    tickets[i].questionType = .none
                    tickets[i].quickReplyReady = false
                    try tickets[i].apply(.stillRunning, now: now)
                case .waiting(let note):
                    let said = messages[session.id]?.devin
                    tickets[i].lastMessage = note ?? said ?? tickets[i].lastMessage
                    tickets[i].questionType = note == nil ? QuestionDetector.detect(tickets[i].lastMessage) : .yesNo
                    tickets[i].quickReplyReady = true
                    tickets[i].activity = nil
                    try tickets[i].apply(.needsYou, now: now)
                case .finished:
                    // A finished task is Nina's turn too (DECISIONS.md): it waits until she marks it Done.
                    let said = messages[session.id]?.devin
                    tickets[i].lastMessage = said ?? session.pullRequest.map { "Finished. Pull request: \($0)" } ?? "Finished."
                    tickets[i].questionType = QuestionDetector.detect(tickets[i].lastMessage)
                    tickets[i].quickReplyReady = true
                    tickets[i].activity = nil
                    try tickets[i].apply(.needsYou, now: now)
                case .blocked(let why):
                    tickets[i].lastMessage = why
                    tickets[i].quickReplyReady = false
                    tickets[i].activity = nil
                    try tickets[i].apply(.blocked, now: now)
                case .leaveAlone:
                    break
                }
                touched.append(tickets[i])
            }
            return touched
        }
    }
}
