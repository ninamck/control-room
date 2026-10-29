import Foundation
import Testing
@testable import ControlRoomCore

let noon = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z")!
var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

func minutes(_ m: Double) -> TimeInterval { m * 60 }

@Test func waitingTurnsCoralAtFifteenMinutes() {
    let t = Ticket(tool: .cursor, title: "Pick one", stateSince: noon)
    #expect(t.signal(at: noon + minutes(14.9)) == .pink)
    #expect(t.signal(at: noon + minutes(15)) == .coral)
}

@Test func coloursFollowState() {
    var t = Ticket(tool: .devin, title: "x", stateSince: noon)
    t.state = .blocked; #expect(t.signal(at: noon) == .coral)
    t.state = .working; #expect(t.signal(at: noon) == .sky)
    t.state = .done; #expect(t.signal(at: noon) == .mint)
    t.state = .parked; #expect(t.signal(at: noon) == .paper)
}

@Test func laterHidesForThirtyMinutesThenComesBackWithOriginalClock() throws {
    var t = Ticket(tool: .claudeCode, title: "Review", stateSince: noon)
    try t.apply(.later, now: noon + minutes(10))
    #expect(t.state == .later)
    #expect(t.laterCount == 1)

    let stillHidden = Rules.tick([t], now: noon + minutes(39), calendar: utc)
    #expect(stillHidden[0].state == .later)

    let back = Rules.tick([t], now: noon + minutes(40), calendar: utc)[0]
    #expect(back.state == .needsYou)
    #expect(back.stateSince == noon)  // clock didn't reset
    #expect(back.signal(at: noon + minutes(40)) == .coral)
}

@Test func laterCountKeepsClimbing() throws {
    var t = Ticket(tool: .grok, title: "x", stateSince: noon)
    var now = noon
    for _ in 1...3 {
        try t.apply(.later, now: now)
        now += minutes(30)
        t = Rules.tick([t], now: now, calendar: utc)[0]
    }
    #expect(t.laterCount == 3)
    #expect(t.state == .needsYou)
}

@Test func laterOnlyFromWaiting() {
    var t = Ticket(tool: .cursor, title: "x", state: .working, stateSince: noon)
    #expect(throws: RuleError.self) { try t.apply(.later, now: noon) }
}

@Test func doneExpiresAtMidnight() throws {
    var t = Ticket(tool: .cursor, title: "x", stateSince: noon)
    try t.apply(.done, now: noon)
    let lateTonight = noon + minutes(11 * 60 + 59)
    #expect(Rules.tick([t], now: lateTonight, calendar: utc).count == 1)
    let afterMidnight = noon + minutes(12 * 60 + 1)
    #expect(Rules.tick([t], now: afterMidnight, calendar: utc).isEmpty)
}

@Test func blockedAndParkedNeverClearOnTheirOwn() throws {
    var blocked = Ticket(tool: .devin, title: "x", stateSince: noon)
    try blocked.apply(.blocked, now: noon)
    var parked = Ticket(tool: .cursor, title: "y", stateSince: noon)
    try parked.apply(.park, now: noon)
    let weekLater = Rules.tick([blocked, parked], now: noon + minutes(7 * 24 * 60), calendar: utc)
    #expect(weekLater.map(\.state) == [.blocked, .parked])
}

@Test func storeSavesAndReloads() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = dir.appendingPathComponent("tickets.json")
    let store = try TicketStore(fileURL: file, now: { noon })
    let t = try store.add(Ticket(tool: .cursor, title: "Saved", questionType: .choice(["Menu", "Integrations"]), stateSince: noon))
    try store.apply(.later, to: t.shortID)

    let reloaded = try TicketStore(fileURL: file, now: { noon })
    let back = try reloaded.all()
    #expect(back.count == 1)
    #expect(back[0].state == .later)
    #expect(back[0].questionType == .choice(["Menu", "Integrations"]))
}

@Test func apiNeedsTheToken() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let api = API(store: try TicketStore(fileURL: dir.appendingPathComponent("t.json")), token: "secret")
    let noToken = api.handle(HTTPRequest(method: "GET", path: "/tickets", headers: [:], body: Data()))
    #expect(noToken.status == 401)
    let ok = api.handle(HTTPRequest(method: "GET", path: "/tickets", headers: ["authorization": "Bearer secret"], body: Data()))
    #expect(ok.status == 200)
}
