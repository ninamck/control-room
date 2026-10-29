import Foundation
import Testing
@testable import ControlRoomCore

private func session(_ status: String, _ detail: String?, id: String = "devin-abc", title: String? = "Transfer requests: PR #412",
                     updated: Date = noon) -> DevinAPI.Session {
    DevinAPI.Session(id: id, url: "https://app.devin.ai/sessions/\(id)", title: title, status: status, detail: detail,
                     userID: "u1", updatedAt: updated, pullRequest: nil)
}

@Test func devinSessionsMoveThroughWorkingWaitingAndDone() throws {
    var clock = noon
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { clock })

    let working = try DevinFeed.apply([session("running", "working")], messages: [:], store: store)
    #expect(working.first?.state == .working)
    #expect(working.first?.chatName == "Transfer requests: PR #412")
    #expect(working.first?.deepLink == "https://app.devin.ai/sessions/devin-abc")

    clock = noon + 300
    let asking = try DevinFeed.apply([session("running", "waiting_for_user")],
                                     messages: ["devin-abc": ("Checks are green. Should I merge PR #412?", "Fix the transfer request flow")], store: store)
    #expect(asking.first?.state == .needsYou)
    #expect(asking.first?.questionType == .yesNo)
    #expect(asking.first?.quickReplyReady == true)
    #expect(asking.first?.title == "Fix the transfer request flow")

    // Nina marks it done; the same status on the next poll leaves it done.
    let id = try store.all()[0].id
    try store.apply(.done, to: id)
    try DevinFeed.apply([session("running", "waiting_for_user")], messages: [:], store: store)
    #expect(try store.all()[0].state == .done)

    // Something new from Devin brings it back.
    try DevinFeed.apply([session("running", "working")], messages: [:], store: store)
    #expect(try store.all()[0].state == .working)
}

@Test func devinFinishedIsNinasTurnAndErrorsBlock() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
    let finished = try DevinFeed.apply([session("exit", nil)], messages: ["devin-abc": ("Opened PR #412.", nil)], store: store)
    #expect(finished.first?.state == .needsYou)
    #expect(finished.first?.lastMessage == "Opened PR #412.")

    let broke = try DevinFeed.apply([session("suspended", "out_of_credits", id: "devin-two")], messages: [:], store: store)
    #expect(broke.first?.state == .blocked)
    #expect(broke.first?.lastMessage == "Devin stopped: out of credits.")
}

@Test func oldOrIdleDevinSessionsDontAppear() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
    try DevinFeed.apply([session("exit", nil, id: "devin-old", updated: noon - 3 * 24 * 3600),
                         session("suspended", "inactivity", id: "devin-idle")], messages: [:], store: store)
    #expect(try store.all().isEmpty)
}

@Test func devinOnlyReadsMessagesWhenSomethingNewIsWaiting() throws {
    let tickets: [Ticket] = []
    let picked = DevinFeed.needsMessages([session("running", "waiting_for_user"), session("running", "working", id: "devin-2")],
                                         in: tickets, now: noon)
    #expect(picked.map(\.id) == ["devin-abc", "devin-2"])  // both new: read titles from messages
    var known = Ticket(tool: .devin, title: "x")
    known.externalId = "devin:devin-abc"
    known.feedStatus = "running/waiting_for_user"
    #expect(DevinFeed.needsMessages([session("running", "waiting_for_user")], in: [known], now: noon).isEmpty)
}

@Test func devinSessionJSONReads() {
    let s = DevinAPI.session(["session_id": "devin-x", "url": "https://app.devin.ai/sessions/devin-x", "title": "",
                              "status": "running", "status_detail": "working", "user_id": "u1",
                              "updated_at": 1_793_200_000_000, "pull_requests": [["pr_url": "https://github.com/x/pull/1"]]])
    #expect(s?.title == nil)
    #expect(s?.updatedAt == Date(timeIntervalSince1970: 1_793_200_000))
    #expect(s?.pullRequest == "https://github.com/x/pull/1")
}
