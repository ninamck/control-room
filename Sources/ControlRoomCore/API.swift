import Foundation

/// The local server's routes. Every feed and the app talk to the store through these.
///
///   GET  /health                   no token needed
///   GET  /tickets                  all tickets
///   POST /tickets                  add a ticket
///   POST /tickets/{id}/{action}    later, park, done, still-running, needs-you, blocked
///   POST /tickets/{id}/drop        delete it
///   POST /feeds/cursor             a Cursor hook event
///   POST /feeds/claude-code        a Claude Code hook event
public struct API: Sendable {
    let store: TicketStore
    let token: String

    public init(store: TicketStore, token: String) {
        self.store = store
        self.token = token
    }

    /// Body of POST /tickets. Only tool and title are required.
    public struct NewTicket: Codable, Sendable {
        public var tool: Tool
        public var title: String
        public var thread: String?
        public var lastMessage: String?
        public var questionType: QuestionType?
        public var deepLink: String?
        public var state: TicketState?
        public var source: Source?
        public var kind: Kind?

        public init(tool: Tool, title: String, thread: String? = nil, lastMessage: String? = nil,
                    questionType: QuestionType? = nil, deepLink: String? = nil, state: TicketState? = nil,
                    source: Source? = nil, kind: Kind? = nil) {
            self.tool = tool
            self.title = title
            self.thread = thread
            self.lastMessage = lastMessage
            self.questionType = questionType
            self.deepLink = deepLink
            self.state = state
            self.source = source
            self.kind = kind
        }
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let parts = request.path.split(separator: "?")[0].split(separator: "/").map(String.init)
        if request.method == "GET" && parts == ["health"] {
            return json(200, ["ok": true])
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return error(401, "Missing or wrong token.")
        }
        do {
            switch (request.method, parts.count) {
            case ("GET", 1) where parts[0] == "tickets":
                return json(200, try store.all())
            case ("POST", 1) where parts[0] == "tickets":
                let new = try JSONDecoder.controlRoom.decode(NewTicket.self, from: request.body)
                guard !new.title.trimmingCharacters(in: .whitespaces).isEmpty else { return error(400, "A ticket needs a title.") }
                let thread = new.thread ?? new.deepLink.flatMap(QuickAdd.threadName(forLink:)) ?? ""
                let ticket = Ticket(tool: new.tool, source: new.source ?? .manual, kind: new.kind ?? .interactive,
                                    title: new.title, thread: thread, lastMessage: new.lastMessage ?? "",
                                    questionType: new.questionType ?? .none, deepLink: new.deepLink ?? "",
                                    state: new.state ?? .needsYou)
                return json(201, try store.add(ticket))
            case ("POST", 2) where parts == ["feeds", "cursor"]:
                guard let payload = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                    return error(400, "Expected a Cursor hook event.")
                }
                EventLog.record(payload)
                return json(200, try CursorFeed.handle(payload, store: store))
            case ("POST", 2) where parts == ["feeds", "claude-code"]:
                guard let payload = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                    return error(400, "Expected a Claude Code hook event.")
                }
                EventLog.record(payload)
                return json(200, try ClaudeCodeFeed.handle(payload, store: store))
            case ("POST", 3) where parts[0] == "tickets":
                if parts[2] == "drop" { return json(200, try store.drop(parts[1])) }
                guard let action = TicketAction(rawValue: parts[2]) else { return error(404, "Unknown action \(parts[2]).") }
                return json(200, try store.apply(action, to: parts[1]))
            default:
                return error(404, "Nothing at \(request.method) \(request.path).")
            }
        } catch let e as RuleError {
            return error(400, e.message)
        } catch is DecodingError {
            return error(400, "Couldn't read that ticket. Check the tool name and fields.")
        } catch {
            return self.error(500, error.localizedDescription)
        }
    }

    private func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        HTTPResponse(status: status, body: (try? JSONEncoder.controlRoom.encode(value)) ?? Data())
    }

    private func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(status, ["error": message])
    }
}
