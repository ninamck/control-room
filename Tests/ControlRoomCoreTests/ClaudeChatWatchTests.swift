import Foundation
import Testing
@testable import ControlRoomCore

private func store() throws -> TicketStore {
    try TicketStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
}

@Test func claudeChatNamesComeFromThePageTitle() {
    #expect(ClaudeChatView.chatName(fromPageTitle: "Kitchen at closing time story - Claude") == "Kitchen at closing time story")
    #expect(ClaudeChatView.chatName(fromPageTitle: "Control room folder plan - Claude Code") == nil)
    #expect(ClaudeChatView.chatName(fromPageTitle: "Claude Artifact") == nil)
    #expect(ClaudeChatView.chatName(fromPageTitle: "New chat - Claude") == nil)
    #expect(ClaudeChatView.strip("Claude responded: The extractor fan goes quiet", prefix: "Claude responded:") == "The extractor fan goes quiet")
}

@Test func aReplyFinishedWhileNinaIsElsewhereWaitsOnHer() throws {
    let store = try store()
    var watch = ClaudeChatWatch()
    try watch.observe([], store: store)
    #expect(try store.all().isEmpty)

    try watch.observe([ClaudeChatView(name: "Kitchen story", replying: true, lastAsked: "Write me a story")], store: store)
    var ticket = try store.all()[0]
    #expect(ticket.state == .working)
    #expect(ticket.title == "Write me a story")
    #expect(ticket.chatName == "Kitchen story")
    #expect(ticket.tool == .claudeAI)

    try watch.observe([ClaudeChatView(name: "Kitchen story", replying: false, lastReply: "The extractor fan goes quiet.")], store: store)
    ticket = try store.all()[0]
    #expect(ticket.state == .needsYou)
    #expect(ticket.lastMessage == "The extractor fan goes quiet.")

    // She opens Claude and looks at it: read.
    try watch.observe([ClaudeChatView(name: "Kitchen story", replying: false, lastReply: "The extractor fan goes quiet.", looking: true)], store: store)
    #expect(try store.all()[0].state == .done)
}

@Test func aReplyWatchedToTheEndIsAlreadyRead() throws {
    let store = try store()
    var watch = ClaudeChatWatch()
    try watch.observe([ClaudeChatView(name: "Story", replying: true, looking: true)], store: store)
    try watch.observe([ClaudeChatView(name: "Story", replying: false, lastReply: "Done.", looking: true)], store: store)
    #expect(try store.all()[0].state == .done)
}

@Test func movingToAnotherChatMidReplySaysSo() throws {
    let store = try store()
    var watch = ClaudeChatWatch()
    try watch.observe([ClaudeChatView(name: "Story", replying: true)], store: store)
    // The window couldn't be read: nothing changes.
    try watch.observe(nil, store: store)
    #expect(try store.all()[0].state == .working)
    try watch.observe([ClaudeChatView(name: "Pricing", replying: false, looking: true)], store: store)
    let ticket = try store.all()[0]
    #expect(ticket.state == .needsYou)
    #expect(ticket.lastMessage == ClaudeChatWatch.movedAway)
    // Going back shows the reply and counts as reading it.
    try watch.observe([ClaudeChatView(name: "Story", replying: false, lastReply: "Here it is.", looking: true)], store: store)
    #expect(try store.all()[0].state == .done)
    #expect(try store.all()[0].lastMessage == "Here it is.")
    // Opening an old chat never makes a ticket.
    #expect(try store.all().count == 1)
}

@Test func taskSessionsInTheWindowDontGetASecondTicket() throws {
    let store = try store()
    try store.update { tickets, now in
        var ticket = Ticket(tool: .claudeAI, source: .automatic, title: "Pret calls", state: .working, stateSince: now)
        ticket.externalId = "claude-app:local_x"
        ticket.chatName = "Pret calls"
        tickets.append(ticket)
    }
    var watch = ClaudeChatWatch()
    try watch.observe([ClaudeChatView(name: "Pret calls", replying: true)], store: store)
    #expect(try store.all().count == 1)
}

@Test func aChatRenamedMidReplyKeepsItsTicket() throws {
    let store = try store()
    var watch = ClaudeChatWatch()
    try watch.observe([ClaudeChatView(name: "Poem about walk-in fridge", replying: true, lastAsked: "Write a poem")], store: store)
    try watch.observe([ClaudeChatView(name: "Poem about a walk-in fridge", replying: false, lastReply: "Cold light.", lastAsked: "Write a poem")], store: store)
    let tickets = try store.all()
    #expect(tickets.count == 1)
    #expect(tickets[0].state == .needsYou)
    #expect(tickets[0].chatName == "Poem about a walk-in fridge")
    #expect(tickets[0].lastMessage == "Cold light.")
}
