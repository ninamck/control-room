import Foundation
import SQLite3
import Testing
@testable import ControlRoomCore

private func makeStore() throws -> TicketStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
}

private func event(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["hook_event_name": name, "conversation_id": "conv-1", "workspace_roots": ["/Users/nina/code/edify-web"]]
        .merging(extra) { $1 }
}

@Test func promptStartsAWorkingTicketInItsProject() throws {
    let store = try makeStore()
    let t = try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "We have lost pack type and pack cost\nmore detail"]), store: store)
    #expect(t?.state == .working)
    #expect(t?.title == "We have lost pack type and pack cost")
    #expect(t?.thread == "edify-web")
    #expect(t?.deepLink == "/Users/nina/code/edify-web")
    #expect(t?.source == .automatic)
    #expect(try store.all().count == 1)
}

@Test func aFinishedReplyWaitsOnNinaUntilSheMarksItDone() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Refactor"]), store: store)
    try CursorFeed.handle(event("afterAgentResponse", ["text": "Done. All tests pass."]), store: store)
    let t = try CursorFeed.handle(event("stop", ["status": "completed"]), store: store)
    #expect(t?.state == .needsYou)
    #expect(t?.questionType == QuestionType.none)
    #expect(t?.lastMessage == "Done. All tests pass.")

    let marked = try store.apply(.done, to: t!.id)
    #expect(marked.state == .done)
    // Prompting the same chat again brings it back.
    #expect(try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "One more thing"]), store: store)?.state == .working)
}

@Test func stoppingItYourselfIsDone() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    #expect(try CursorFeed.handle(event("stop", ["status": "aborted"]), store: store)?.state == .done)
}

@Test func finishingOnAQuestionNeedsNina() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Fix nav"]), store: store)
    try CursorFeed.handle(event("afterAgentResponse", ["text": "Two options:\n1. Menu\n2. Integrations\nWhich do you want?"]), store: store)
    let t = try CursorFeed.handle(event("stop", ["status": "completed"]), store: store)
    #expect(t?.state == .needsYou)
    #expect(t?.questionType == .choice(["Menu", "Integrations"]))
}

@Test func questionsPromptNeedsNinaThenGoesBackToWorking() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Basket lines"]), store: store)
    let asked = try CursorFeed.handle(event("preToolUse", [
        "tool_name": "AskQuestion",
        "tool_input": ["questions": [["question": "Where should the pack and price go?",
                                       "options": [["label": "One grey line"], ["label": "Split across columns"]]]]],
    ]), store: store)
    #expect(asked?.state == .needsYou)
    #expect(asked?.lastMessage == "Where should the pack and price go?")
    #expect(asked?.questionType == .choice(["One grey line", "Split across columns"]))

    let answered = try CursorFeed.handle(event("postToolUse", ["tool_name": "AskQuestion"]), store: store)
    #expect(answered?.state == .working)
}

@Test func otherToolsShowWhatItsDoingButStayWorking() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    #expect(try store.all()[0].activity == "Reading your message")

    let helper = try CursorFeed.handle(event("preToolUse", ["tool_name": "Task"]), store: store)
    #expect(helper?.state == .working)
    #expect(helper?.activity == "Handing part of it to a helper")

    let shell = try CursorFeed.handle(event("preToolUse", ["tool_name": "Shell", "tool_input": [
        "command": "cd \"/Users/nina/Documents/New AI direction\" && npm run test:e2e -- basket"]]), store: store)
    #expect(shell?.activity == "Running npm run test:e2e -- basket")
    #expect(shell?.activityAt == noon)

    let edit = try CursorFeed.handle(event("preToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/x/web/src/basket.tsx"]]), store: store)
    #expect(edit?.activity == "Editing basket.tsx")

    #expect(try CursorFeed.handle(event("postToolUse", ["tool_name": "Write"]), store: store)?.activity == "Thinking")
    let done = try CursorFeed.handle(event("stop", ["status": "completed"]), store: store)
    #expect(done?.activity == nil)
}

@Test func errorsBlockAndFollowUpsResume() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    #expect(try CursorFeed.handle(event("stop", ["status": "error"]), store: store)?.state == .blocked)
    let again = try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "try again"]), store: store)
    #expect(again?.state == .working)
    #expect(again?.title == "try again")  // follows what Nina last asked
    #expect(try store.all().count == 1)
}

@Test func ticketsStillMatchAfterTheAppRestarts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    let first = try TicketStore(fileURL: file, now: { noon })
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Checkout scroll"]), store: first)

    let reopened = try TicketStore(fileURL: file, now: { noon })
    try CursorFeed.handle(event("afterAgentResponse", ["text": "Fixed."]), store: reopened)
    let t = try CursorFeed.handle(event("stop", ["status": "completed"]), store: reopened)
    #expect(t?.state == .needsYou)
    #expect(t?.lastMessage == "Fixed.")
    #expect(try reopened.all().count == 1)
}

@Test func chatsAlreadyRunningAppearOnTheirFirstEvent() throws {
    let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    let lines = [
        #"{"role":"user","message":{"content":[{"type":"text","text":"<external_links>stuff</external_links><user_query>https://linear.app/edify/project/predictive-ordering-ai-rules-and-ui-sweep-8c6</user_query>"}]}}"#,
        #"{"role":"assistant","message":{"content":[{"type":"text","text":"Plan ready."}]}}"#,
        #"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>x</timestamp><user_query>\nWhen I click check out it scrolls me to the bottom\n</user_query>"}]}}"#,
        #"{"role":"assistant","message":{"content":[{"type":"text","text":"Checkout now opens at the top."}]}}"#,
    ]
    try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

    let store = try makeStore()
    let working = try CursorFeed.handle(event("preToolUse", ["tool_name": "Shell", "transcript_path": transcript.path]), store: store)
    #expect(working?.state == .working)
    #expect(working?.title == "When I click check out it scrolls me to the bottom")

    let finished = try CursorFeed.handle(event("stop", ["status": "completed", "transcript_path": transcript.path]), store: store)
    #expect(finished?.state == .needsYou)
    #expect(finished?.lastMessage == "Checkout now opens at the top.")
    #expect(try store.all().count == 1)
}

@Test func pastedPageElementsKeepTheTitle() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "When I click check out it scrolls"]), store: store)
    let pasted = "DOM Path: div#root > div.flex\nPosition: top=296px, left=147px\nHTML Element: <div class=\"x\">"
    let t = try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": pasted]), store: store)
    #expect(t?.title == "When I click check out it scrolls")
    #expect(CursorFeed.title(from: pasted + "\nmake this box smaller") == "make this box smaller")

    // Cursor puts her words straight after the element, on the same line.
    let inline = "DOM Path: div#root\nPosition: top=124px\nHTML Element: <div class=\"x\" data-cursor-element-id=\"cursor-el-45\">Predictive orders Empty basket</div> will this default to open the predictive orders always?"
    #expect(CursorFeed.title(from: inline) == "will this default to open the predictive orders always?")
}

@Test func cursorsOwnFollowUpsArentTitles() throws {
    #expect(CursorFeed.title(from: "Briefly inform the user about the task result and perform any follow-up actions (if needed).") == nil)
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Does this go across to the variances?"]), store: store)
    let t = try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Briefly inform the user about the task result and perform any follow-up actions (if needed)."]), store: store)
    #expect(t?.title == "Does this go across to the variances?")
}

@Test func finishingRefreshesTheTitleFromTheTranscript() throws {
    let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    try #"{"role":"user","message":{"content":[{"type":"text","text":"<user_query>Newest question</user_query>"}]}}"#
        .write(to: transcript, atomically: true, encoding: .utf8)
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Old question"]), store: store)
    let t = try CursorFeed.handle(event("stop", ["status": "completed", "transcript_path": transcript.path]), store: store)
    #expect(t?.title == "Newest question")
}

@Test func toolUseAfterFinishingMeansWorkingAgain() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    try CursorFeed.handle(event("stop", ["status": "completed"]), store: store)
    let t = try CursorFeed.handle(event("preToolUse", ["tool_name": "Shell"]), store: store)
    #expect(t?.state == .working)
}

@Test func ticketsCarryCursorsChatName() throws {
    // A stand-in for Cursor's state database with one named chat.
    let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".vscdb").path
    var db: OpaquePointer?
    #expect(sqlite3_open(dbPath, &db) == SQLITE_OK)
    sqlite3_exec(db, "CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);", nil, nil, nil)
    sqlite3_exec(db, #"INSERT INTO cursorDiskKV VALUES ('composerData:named-chat', '{"name":"Predictive ordering UI sweep"}');"#, nil, nil, nil)
    sqlite3_close(db)
    setenv("CONTROL_ROOM_CURSOR_STATE_DB", dbPath, 1)
    defer { unsetenv("CONTROL_ROOM_CURSOR_STATE_DB") }

    #expect(CursorChatNames.name(for: "named-chat") == "Predictive ordering UI sweep")
    #expect(CursorChatNames.name(for: "no-such-chat") == nil)

    let store = try makeStore()
    let named = try CursorFeed.handle(["hook_event_name": "beforeSubmitPrompt", "conversation_id": "named-chat",
                                       "prompt": "can you make this look nice?"], store: store)
    #expect(named?.chatName == "Predictive ordering UI sweep")
    #expect(named?.contextName == "Predictive ordering UI sweep")
    #expect(named?.title == "can you make this look nice?")

    // No Cursor name: the first message names it, and the project is the fallback after that.
    let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    try [#"{"role":"user","message":{"content":[{"type":"text","text":"<user_query>Can you create a UI pass ticket</user_query>"}]}}"#,
         #"{"role":"user","message":{"content":[{"type":"text","text":"<user_query>Latest thing</user_query>"}]}}"#]
        .joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)
    let unnamed = try CursorFeed.handle(["hook_event_name": "preToolUse", "conversation_id": "unnamed-chat", "tool_name": "Read",
                                         "transcript_path": transcript.path], store: store)
    #expect(unnamed?.chatName == "Can you create a UI pass ticket")
    #expect(unnamed?.title == "Latest thing")

    setenv("CONTROL_ROOM_CURSOR_STATE_DB", "/nonexistent/state.vscdb", 1)
    #expect(CursorChatNames.name(for: "named-chat") == nil)
}

@Test func closedChatsWeNeverSawAreIgnored() throws {
    let store = try makeStore()
    #expect(try CursorFeed.handle(event("sessionEnd", ["reason": "user_close"]), store: store) == nil)
    #expect(try store.all().isEmpty)
}

@Test func linksBecomeReadableTitles() {
    #expect(CursorFeed.title(from: "https://linear.app/edify-systems/project/predictive-ordering-ai-rules-and-ui-sweep-8c6")
            == "Predictive ordering ai rules and ui sweep")
    #expect(CursorFeed.title(from: "Fix the nav https://x.com/a") == "Fix the nav https://x.com/a")
}

@Test func detectsQuestions() {
    #expect(QuestionDetector.detect("All done, tests pass.") == .none)
    #expect(QuestionDetector.detect("Should I merge it?") == .yesNo)
    #expect(QuestionDetector.detect("What colour do you want the header?") == .free)
    #expect(QuestionDetector.detect("Pick one:\n1. Menu\n2) Integrations") == .choice(["Menu", "Integrations"]))
}

@Test func installerKeepsOtherHooksAndRemovesCleanly() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    setenv("CONTROL_ROOM_CURSOR_DIR", dir.path, 1)
    defer { unsetenv("CONTROL_ROOM_CURSOR_DIR") }
    let existing = #"{"version": 1, "hooks": {"stop": [{"command": "./audit.sh"}]}}"#
    try existing.write(to: dir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

    try CursorHooks.install()
    try CursorHooks.install()  // twice must not add twice
    let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("hooks.json"))) as! [String: Any]
    let hooks = installed["hooks"] as! [String: [[String: Any]]]
    #expect(hooks["stop"]?.count == 2)
    #expect(hooks["beforeSubmitPrompt"]?.count == 1)
    #expect(FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("hooks/control-room.sh").path))
    #expect(CursorHooks.isInstalled)

    try CursorHooks.remove()
    let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("hooks.json"))) as! [String: Any]
    let left = removed["hooks"] as! [String: [[String: Any]]]
    #expect(left.keys.sorted() == ["stop"])
    #expect(left["stop"]?.first?["command"] as? String == "./audit.sh")
}
