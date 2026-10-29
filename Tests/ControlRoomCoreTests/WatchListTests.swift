import Foundation
import Testing
@testable import ControlRoomCore

private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

private func makeList() -> (WatchList, TicketStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try! TicketStore(fileURL: dir.appendingPathComponent("t.json"))
    return (WatchList(fileURL: dir.appendingPathComponent("watch.json")), store, dir)
}

@Test func cadencesKnowTheirRuns() {
    // Thursday 29 Oct 2026, noon UTC.
    let weekdays = WatchedTask(name: "Morning brief", tool: .claudeAI, time: "09:00", cadence: .init(kind: .weekdays), created: at("2026-10-01T00:00:00Z"))
    #expect(weekdays.previousRun(atOrBefore: noon, calendar: utc) == at("2026-10-29T09:00:00Z"))
    // Friday then the weekend is skipped.
    #expect(weekdays.nextRun(after: at("2026-10-30T10:00:00Z"), calendar: utc) == at("2026-11-02T09:00:00Z"))

    let mondays = WatchedTask(name: "All-hands numbers", tool: .claudeAI, time: "08:00", cadence: .init(kind: .weekly, weekday: 2), created: at("2026-10-01T00:00:00Z"))
    #expect(mondays.previousRun(atOrBefore: noon, calendar: utc) == at("2026-10-26T08:00:00Z"))
    #expect(mondays.cadence.label == "Mondays")

    let fortnightly = WatchedTask(name: "Numbers", tool: .claudeAI, time: "08:00",
                                  cadence: .init(kind: .fortnightly, weekday: 2, anchor: at("2026-10-26T00:00:00Z")), created: at("2026-10-01T00:00:00Z"))
    #expect(fortnightly.nextRun(after: noon, calendar: utc) == at("2026-11-09T08:00:00Z"))
}

@Test func runsLandAsQuietCardsAndTheNextReplacesAnUnreadOne() throws {
    let (list, store, _) = makeList()
    list.add(WatchedTask(name: "QSR news scan", tool: .grok, time: "07:30", cadence: .init(kind: .daily),
                         link: "https://grok.com/tasks", created: at("2026-10-28T00:00:00Z")))

    try list.land(into: store, now: at("2026-10-29T07:29:00Z"), calendar: utc)
    let first = try store.all()
    #expect(first.count == 1)  // yesterday's 07:30 landed
    #expect(first[0].kind == .scheduled)
    #expect(first[0].state == .needsYou)
    #expect(first[0].stateSince == at("2026-10-28T07:30:00Z"))
    #expect(WatchList.status(list.tasks[0], tickets: first, now: at("2026-10-29T07:29:00Z"), calendar: utc) == .unread)

    // Today's run lands; yesterday's unread card goes, and the watch list remembers it went unread.
    try list.land(into: store, now: at("2026-10-29T07:31:00Z"), calendar: utc)
    let second = try store.all()
    #expect(second.count == 1)
    #expect(second[0].stateSince == at("2026-10-29T07:30:00Z"))
    #expect(WatchList.lastResult(list.tasks[0]) == "unread · Wed")

    // Read it.
    try list.markRead(second[0], store: store)
    #expect(try store.all()[0].state == .done)
    #expect(WatchList.lastResult(list.tasks[0]) == "last ok · Thu")
    #expect(WatchList.status(list.tasks[0], tickets: try store.all(), now: at("2026-10-29T07:40:00Z"), calendar: utc) == .later("TOMORROW"))
    #expect(WatchList.status(list.tasks[0], tickets: try store.all(), now: at("2026-10-30T07:00:00Z"), calendar: utc) == .soon(minutes: 30))
}

@Test func didntRunShowsMissed() throws {
    let (list, store, _) = makeList()
    list.add(WatchedTask(name: "All-hands numbers", tool: .claudeAI, time: "08:00", cadence: .init(kind: .weekly, weekday: 2),
                         created: at("2026-10-20T00:00:00Z")))
    try list.land(into: store, now: noon, calendar: utc)
    let card = try store.all()[0]
    try list.markMissed(card, store: store)
    #expect(try store.all().isEmpty)
    #expect(WatchList.status(list.tasks[0], tickets: [], now: noon, calendar: utc) == .missed)
    #expect(WatchList.lastResult(list.tasks[0]) == "no run Mon 26")
}

@Test func addingAScheduleDoesntLandRunsFromBeforeItWasAdded() throws {
    let (list, store, _) = makeList()
    list.add(WatchedTask(name: "Morning brief", tool: .claudeAI, time: "09:00", cadence: .init(kind: .daily), created: noon))
    try list.land(into: store, now: noon + 60, calendar: utc)
    #expect(try store.all().isEmpty)
}
