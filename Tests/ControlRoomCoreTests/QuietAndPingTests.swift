import Foundation
import Testing
@testable import ControlRoomCore

private func chat(heard minutesAgo: Double, tool: Tool = .cursor, source: Source = .automatic) -> Ticket {
    var ticket = Ticket(tool: tool, source: source, title: "Chat", state: .working, stateSince: noon.addingTimeInterval(-36 * 3600))
    ticket.activityAt = noon.addingTimeInterval(-minutesAgo * 60)
    return ticket
}

@Test func chatsWithNoNewsGoQuietThenClearAfterADay() {
    #expect(!chat(heard: 5).goneQuiet(at: noon))
    #expect(chat(heard: 45).goneQuiet(at: noon))
    // Devin is asked directly, and Nina's own tickets are hers to move.
    #expect(!chat(heard: 45, tool: .devin).goneQuiet(at: noon))
    #expect(!chat(heard: 45, source: .manual).goneQuiet(at: noon))

    let kept = Rules.tick([chat(heard: 45), chat(heard: 25 * 60), chat(heard: 25 * 60, tool: .devin)], now: noon)
    #expect(kept.count == 2)
}

@Test func aPingLastsForOneWait() throws {
    var ticket = chat(heard: 1)
    ticket.pingMe = true
    try ticket.apply(.needsYou, now: noon)
    #expect(ticket.pingMe == true)
    // She answers in the tool and it starts again: the ping has done its job.
    try ticket.apply(.stillRunning, now: noon)
    #expect(ticket.pingMe == nil)

    ticket.pingMe = true
    try ticket.apply(.done, now: noon)
    #expect(ticket.pingMe == nil)
}
