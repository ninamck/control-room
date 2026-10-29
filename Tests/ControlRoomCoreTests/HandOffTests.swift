import Foundation
import Testing
@testable import ControlRoomCore

@Test func claudeHandOffTicketWaitsForItsSession() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
    let brief = "Draft the corrective actions table for the Checklists PRD.\nUse the audits section."
    let handed = try store.add(HandOff.ticket(tool: .claudeCode, brief: brief, folder: "/Users/nina/code/edify-web",
                                               sessionID: "11111111-2222-3333-4444-555555555555", notionPage: "page-1", now: noon))
    #expect(handed.state == .working)
    #expect(handed.title == "Draft the corrective actions table for the Checklists PRD.")
    #expect(handed.thread == "edify-web")
    #expect(handed.notionPage == "page-1")

    // The new session's first event lands on the same ticket.
    let t = try ClaudeCodeFeed.handle(["hook_event_name": "UserPromptSubmit", "session_id": "11111111-2222-3333-4444-555555555555",
                                       "cwd": "/Users/nina/code/edify-web", "prompt": brief], store: store)
    #expect(t?.id == handed.id)
    #expect(try store.all().count == 1)
}

@Test func cursorChatTakesOverItsHandOff() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
    let brief = "Rewrite the transfer request empty states"
    let handed = try store.add(HandOff.ticket(tool: .cursor, brief: brief, folder: "/Users/nina/code/edify-web", now: noon))
    #expect(handed.source == .manual)

    let t = try CursorFeed.handle(["hook_event_name": "beforeSubmitPrompt", "conversation_id": "conv-x",
                                   "workspace_roots": ["/Users/nina/code/edify-web"], "prompt": brief + "\n"], store: store)
    #expect(t?.id == handed.id)
    #expect(t?.source == .automatic)
    #expect(t?.externalId == "cursor:conv-x")
    #expect(try store.all().count == 1)

    // A different chat doesn't steal it.
    let other = try CursorFeed.handle(["hook_event_name": "beforeSubmitPrompt", "conversation_id": "conv-y", "prompt": "Something else"], store: store)
    #expect(other?.id != handed.id)
}

@Test func placesListMostRecentFirst() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = dir.appendingPathComponent("alpha"), b = dir.appendingPathComponent("beta"), c = dir.appendingPathComponent("gamma")
    for folder in [a, b, c] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    let book = PlaceBook(fileURL: dir.appendingPathComponent("places.json"))
    book.record(a.path, tool: .cursor, at: noon)
    book.record(b.path, tool: .claudeCode, at: noon + 60)
    let seen = [Ticket(tool: .cursor, title: "x", deepLink: c.path, stateSince: noon)]
    #expect(book.list(seenIn: seen) == [b.path, a.path, c.path])
    #expect(book.lastTool(for: a.path) == .cursor)
}

@Test func notionItemsReadAsInTheMockup() {
    let page: [String: Any] = [
        "id": "p1", "url": "https://www.notion.so/p1",
        "properties": [
            "Task": ["title": [["plain_text": "Summarise last three Pret calls"]]],
            "Notes": ["rich_text": [["plain_text": "For Alistair."]]],
            "Due Date": ["date": ["start": "2026-10-30"]],
            "Project": ["select": ["name": "🥨 Pret"]],
        ],
    ]
    let item = NotionReady.item(page)!
    #expect(item.brief == "Summarise last three Pret calls\n\nFor Alistair.")
    #expect(NotionReady.meta(item, now: noon, calendar: utc) == "Tomorrow · Pret")
    var undated = item
    undated.due = nil
    undated.project = nil
    #expect(NotionReady.meta(undated, now: noon, calendar: utc) == "No date")
}
