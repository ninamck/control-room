import Foundation

/// One plain chat open in a Claude app window, as read through macOS Accessibility.
/// Plain chats live only on Anthropic's servers, so the window is the only place to see them.
public struct ClaudeChatView: Equatable, Sendable {
    /// The chat's name, from the window ("Kitchen at closing time story - Claude").
    public var name: String
    /// The window shows "Stop response": Claude is writing.
    public var replying: Bool
    /// The start of Claude's latest reply, from its "Claude responded: …" heading.
    public var lastReply: String?
    /// The start of Nina's latest message, from its "You said: …" heading.
    public var lastAsked: String?
    /// Claude is the frontmost app and this is its front window: Nina is looking at it.
    public var looking: Bool

    public init(name: String, replying: Bool, lastReply: String? = nil, lastAsked: String? = nil, looking: Bool = false) {
        self.name = name
        self.replying = replying
        self.lastReply = lastReply
        self.lastAsked = lastAsked
        self.looking = looking
    }

    /// "Kitchen at closing time story - Claude" → "Kitchen at closing time story". Other pages (the Code tab,
    /// artifacts) and chats still waiting for a name give nil.
    public static func chatName(fromPageTitle title: String) -> String? {
        let suffix = " - Claude"
        guard title.hasSuffix(suffix) else { return nil }
        let name = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        return ["", "Claude", "New chat", "Untitled"].contains(name) ? nil : name
    }

    /// "Claude responded: The extractor fan goes quiet" → "The extractor fan goes quiet".
    public static func strip(_ heading: String, prefix: String) -> String? {
        guard heading.hasPrefix(prefix) else { return nil }
        let text = heading.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Turns what the Claude window shows, scan after scan, into tickets.
/// Only a reply seen being written makes a ticket; opening an old chat never does.
public struct ClaudeChatWatch {
    /// Chats seen writing at the last scan.
    var writing: Set<String> = []

    public static let movedAway = "You moved away before the reply finished. Go back to the chat to see it."
    static let hostApp = "com.anthropic.claudefordesktop"

    public init() {}

    static func key(_ name: String) -> String { "claude-chat:\(name)" }

    /// `views` nil means the window couldn't be read this time: nothing changes.
    public mutating func observe(_ views: [ClaudeChatView]?, store: TicketStore) throws {
        guard let views else { return }
        let writingNow = Set(views.filter(\.replying).map(\.name))
        let before = writing
        var renamed: [String: String] = [:]
        try store.update { tickets, now in
            // Task sessions are already followed from their files; don't add a second ticket for them.
            func taskSession(_ name: String) -> Bool {
                tickets.contains { $0.chatName == name && ($0.externalId?.hasPrefix("claude-app:") ?? false) }
            }
            func ticketIndex(_ name: String) -> Int? { tickets.firstIndex { $0.externalId == Self.key(name) } }

            // Claude renames a new chat a few seconds in. Same window, same question, new name: same chat.
            for view in views where ticketIndex(view.name) == nil {
                guard let asked = view.lastAsked.flatMap(FeedText.title(from:)),
                      let old = before.first(where: { name in
                          !views.contains { $0.name == name } &&
                          ticketIndex(name).map { tickets[$0].title == asked } == true
                      }),
                      let i = ticketIndex(old) else { continue }
                tickets[i].externalId = Self.key(view.name)
                tickets[i].chatName = view.name
                renamed[old] = view.name
            }

            for view in views where view.replying && !taskSession(view.name) {
                let i: Int
                if let found = ticketIndex(view.name) {
                    i = found
                } else {
                    var ticket = Ticket(tool: .claudeAI, source: .automatic, title: view.name, state: .working, stateSince: now)
                    ticket.externalId = Self.key(view.name)
                    ticket.hostApp = Self.hostApp
                    tickets.append(ticket)
                    i = tickets.count - 1
                }
                tickets[i].chatName = view.name
                if let asked = view.lastAsked.flatMap(FeedText.title(from:)) { tickets[i].title = asked }
                tickets[i].questionType = .none
                if tickets[i].state != .working || tickets[i].activity == nil { tickets[i].activityAt = now }
                tickets[i].activity = "Writing a reply"
                try tickets[i].apply(.stillRunning, now: now)
            }

            for name in Set(before.map { renamed[$0] ?? $0 }).subtracting(writingNow) {
                guard let i = ticketIndex(name), tickets[i].state == .working else { continue }
                tickets[i].activity = nil
                if let view = views.first(where: { $0.name == name }) {
                    // Finished while on screen.
                    tickets[i].lastMessage = view.lastReply ?? ""
                    tickets[i].questionType = QuestionDetector.detect(tickets[i].lastMessage)
                    try tickets[i].apply(view.looking ? .done : .needsYou, now: now)
                } else {
                    // The window went to another chat: Claude carries on, but out of sight.
                    tickets[i].lastMessage = Self.movedAway
                    tickets[i].questionType = .none
                    try tickets[i].apply(.needsYou, now: now)
                }
            }

            // Opening a chat that's waiting on Nina, once its reply is there, counts as reading it.
            for view in views where view.looking && !view.replying {
                guard let i = ticketIndex(view.name), tickets[i].state == .needsYou else { continue }
                if tickets[i].lastMessage == Self.movedAway, let reply = view.lastReply { tickets[i].lastMessage = reply }
                try tickets[i].apply(.done, now: now)
            }
        }
        writing = writingNow
    }
}
