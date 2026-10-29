import Foundation
import Testing
@testable import ControlRoomCore

@Test func tomorrowNineQuietsATicketOvernightWithoutCountingAsLater() throws {
    let evening = noon + 6.5 * 3600  // 18:30 UTC
    var t = Ticket(tool: .cursor, title: "Pairing screen", stateSince: noon)
    try t.apply(.tomorrow, now: evening)
    #expect(t.state == .later)
    #expect(t.laterCount == 0)
    let nine = Rules.nextNineAM(after: evening, calendar: utc)
    #expect(nine == ISO8601DateFormatter().date(from: "2026-10-30T09:00:00Z"))
    #expect(Rules.nextNineAM(after: ISO8601DateFormatter().date(from: "2026-10-30T07:00:00Z")!, calendar: utc) == nine)
}

@Test func endOfDaySortsIntoThreeBlocks() throws {
    let now = noon + 6.5 * 3600
    var later3 = Ticket(tool: .cursor, title: "Transfer request empty states", stateSince: noon)
    later3.laterCount = 3
    var parked = Ticket(tool: .grok, title: "Talkshop eval cases", state: .parked, stateSince: noon - 2 * 24 * 3600)
    let waiting = Ticket(tool: .claudeCode, title: "PRD v0.2 ready", stateSince: noon)
    let done = Ticket(tool: .devin, title: "PR #412 merged", state: .done, stateSince: noon)
    let working = Ticket(tool: .cursor, title: "still going", state: .working, stateSince: noon)
    let summary = EndOfDay(tickets: [later3, parked, waiting, done, working], now: now)
    #expect(summary.done.map(\.title) == ["PR #412 merged"])
    #expect(summary.waiting.map(\.title) == ["PRD v0.2 ready"])
    #expect(Set(summary.putOff.map(\.title)) == ["Transfer request empty states", "Talkshop eval cases"])
    #expect(summary.headline == "One finished. One still wants you.")

    // Keep gives one more day.
    try parked.apply(.keep, now: now)
    #expect(EndOfDay(tickets: [parked], now: now).putOff.isEmpty)
    #expect(EndOfDay(tickets: [parked], now: now + 25 * 3600).putOff.count == 1)
}

@Test func headlineReadsInWords() {
    let done = (0..<9).map { _ in Ticket(tool: .cursor, title: "d", state: .done) }
    let waiting = (0..<2).map { _ in Ticket(tool: .cursor, title: "w") }
    #expect(EndOfDay(tickets: done + waiting, now: Date()).headline == "Nine finished. Two still want you.")
    #expect(EndOfDay(tickets: [], now: Date()).headline == "Nothing finished. Nothing still wants you.")
}
