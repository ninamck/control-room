import Foundation

/// Who is doing the work. Identity only, never colour (SPEC section 3).
public enum Tool: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case claudeAI = "claude-ai"
    case cursor
    case grok
    case devin

    /// The letter in the tool's black square.
    public var initial: String {
        switch self {
        case .claudeCode, .claudeAI: "A"
        case .cursor: "C"
        case .devin: "D"
        case .grok: "G"
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeAI: "Claude"
        case .cursor: "Cursor"
        case .devin: "Devin"
        case .grok: "Grok"
        }
    }

    /// Tools that can take a quick reply (SPEC section 6, Quick replies).
    public var acceptsMessages: Bool { self == .claudeCode || self == .devin }
}

public enum Source: String, Codable, Sendable {
    case automatic, manual
}

public enum Kind: String, Codable, Sendable {
    case interactive, scheduled
}

public enum TicketState: String, Codable, CaseIterable, Sendable {
    case working
    case needsYou = "needs_you"
    case blocked
    case done
    case later
    case parked
}

/// What the agent's last message asks for.
public enum QuestionType: Codable, Equatable, Sendable {
    case none
    case yesNo
    case choice([String])
    case free

    private enum CodingKeys: String, CodingKey { case type, options }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "yes_no": self = .yesNo
        case "choice": self = .choice(try c.decodeIfPresent([String].self, forKey: .options) ?? [])
        case "free": self = .free
        default: self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode("none", forKey: .type)
        case .yesNo: try c.encode("yes_no", forKey: .type)
        case .choice(let options):
            try c.encode("choice", forKey: .type)
            try c.encode(options, forKey: .options)
        case .free: try c.encode("free", forKey: .type)
        }
    }
}

public struct Schedule: Codable, Equatable, Sendable {
    public var cadence: String
    public var expected: Date

    public init(cadence: String, expected: Date) {
        self.cadence = cadence
        self.expected = expected
    }
}

/// What a ticket's colour means right now (SPEC section 4).
public enum Signal: String, Sendable {
    case pink, coral, sky, mint, paper
}

public struct Ticket: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tool: Tool
    public var source: Source
    public var kind: Kind
    public var title: String
    public var thread: String
    public var lastMessage: String
    public var questionType: QuestionType
    public var deepLink: String
    public var state: TicketState
    public var stateSince: Date
    public var laterCount: Int
    public var schedule: Schedule?
    /// For automatic tickets: the feed's own id, like "cursor:<conversation id>", so later events find the same ticket.
    /// Spelled "Id", not "ID": tickets.json uses snake_case, and "external_id" only reads back into "externalId".
    public var externalId: String?

    /// While in later: when it comes back.
    public var laterUntil: Date?
    /// While in later: the needs_you clock to restore, so waiting time keeps counting.
    public var waitingSince: Date?

    public init(
        id: String = UUID().uuidString.lowercased(),
        tool: Tool,
        source: Source = .manual,
        kind: Kind = .interactive,
        title: String,
        thread: String = "",
        lastMessage: String = "",
        questionType: QuestionType = .none,
        deepLink: String = "",
        state: TicketState = .needsYou,
        stateSince: Date = Date(),
        laterCount: Int = 0,
        schedule: Schedule? = nil
    ) {
        self.id = id
        self.tool = tool
        self.source = source
        self.kind = kind
        self.title = title
        self.thread = thread
        self.lastMessage = lastMessage
        self.questionType = questionType
        self.deepLink = deepLink
        self.state = state
        self.stateSince = stateSince
        self.laterCount = laterCount
        self.schedule = schedule
    }

    /// Short id for typing at the command line.
    public var shortID: String { String(id.prefix(6)) }

    public func signal(at now: Date) -> Signal {
        switch state {
        case .needsYou: now.timeIntervalSince(stateSince) >= Rules.coralAfter ? .coral : .pink
        case .blocked: .coral
        case .working: .sky
        case .done: .mint
        case .later, .parked: .paper
        }
    }
}
