import Foundation
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

@Test func finishingWithoutAQuestionIsDone() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "Refactor"]), store: store)
    try CursorFeed.handle(event("afterAgentResponse", ["text": "Done. All tests pass."]), store: store)
    let t = try CursorFeed.handle(event("stop", ["status": "completed"]), store: store)
    #expect(t?.state == .done)
    #expect(t?.lastMessage == "Done. All tests pass.")
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

@Test func otherToolsDontChangeAnything() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    #expect(try CursorFeed.handle(event("preToolUse", ["tool_name": "Task"]), store: store) == nil)
    #expect(try CursorFeed.handle(event("preToolUse", ["tool_name": "Shell"]), store: store) == nil)
    #expect(try store.all()[0].state == .working)
}

@Test func errorsBlockAndFollowUpsResume() throws {
    let store = try makeStore()
    try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "x"]), store: store)
    #expect(try CursorFeed.handle(event("stop", ["status": "error"]), store: store)?.state == .blocked)
    let again = try CursorFeed.handle(event("beforeSubmitPrompt", ["prompt": "try again"]), store: store)
    #expect(again?.state == .working)
    #expect(again?.title == "x")  // keeps its first title
    #expect(try store.all().count == 1)
}

@Test func eventsForUnknownConversationsAreIgnored() throws {
    let store = try makeStore()
    #expect(try CursorFeed.handle(event("stop", ["status": "completed"]), store: store) == nil)
    #expect(try store.all().isEmpty)
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
