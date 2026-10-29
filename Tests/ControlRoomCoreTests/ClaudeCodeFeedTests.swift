import Foundation
import Testing
@testable import ControlRoomCore

private func makeStore() throws -> TicketStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { noon })
}

private func event(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["hook_event_name": name, "session_id": "sess-1", "cwd": "/Users/nina/Claude-code/control-room",
     "_env": ["app": "com.anthropic.claudefordesktop", "term": "", "entrypoint": "claude-desktop"]]
        .merging(extra) { $1 }
}

@Test func aPromptStartsAWorkingSessionTicket() throws {
    let store = try makeStore()
    let t = try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "Start step 3"]), store: store)
    #expect(t?.tool == .claudeCode)
    #expect(t?.state == .working)
    #expect(t?.title == "Start step 3")
    #expect(t?.thread == "control-room")
    #expect(t?.hostApp == "com.anthropic.claudefordesktop")
    #expect(t?.activity == "Reading your message")
}

@Test func theSessionTitleNamesIt() throws {
    let store = try makeStore()
    let first = try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "Look at the control room folder"]), store: store)
    #expect(first?.chatName == "Look at the control room folder")  // until it has a title
    let titled = try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "Start step 3", "session_title": "Control room folder plan"]), store: store)
    #expect(titled?.chatName == "Control room folder plan")
    #expect(titled?.title == "Start step 3")
}

@Test func titleComesFromTheTranscriptWhenTheEventHasNone() throws {
    let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    try [#"{"type":"user","message":{"content":"hi"}}"#,
         #"{"type":"custom-title","customTitle":"Control room folder plan","sessionId":"sess-1"}"#]
        .joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)
    let store = try makeStore()
    let t = try ClaudeCodeFeed.handle(event("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "swift test"],
                                                           "transcript_path": transcript.path]), store: store)
    #expect(t?.chatName == "Control room folder plan")
    #expect(t?.activity == "Running swift test")
}

@Test func aFinishedReplyWaitsOnNina() throws {
    let store = try makeStore()
    try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "x"]), store: store)
    let t = try ClaudeCodeFeed.handle(event("Stop", ["last_assistant_message": "Step 3 is built. Should I install the hooks?"]), store: store)
    #expect(t?.state == .needsYou)
    #expect(t?.lastMessage == "Step 3 is built. Should I install the hooks?")
    #expect(t?.questionType == .yesNo)
    #expect(t?.activity == nil)
}

@Test func questionsAndPermissionsWaitOnNina() throws {
    let store = try makeStore()
    try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "x"]), store: store)
    let asked = try ClaudeCodeFeed.handle(event("PreToolUse", ["tool_name": "AskUserQuestion", "tool_input": [
        "questions": [["question": "Which font?", "header": "Font", "options": [["label": "Archivo"], ["label": "System"]], "multiSelect": false]]]]), store: store)
    #expect(asked?.state == .needsYou)
    #expect(asked?.questionType == .choice(["Archivo", "System"]))
    #expect(try ClaudeCodeFeed.handle(event("PostToolUse", ["tool_name": "AskUserQuestion"]), store: store)?.state == .working)

    let permission = try ClaudeCodeFeed.handle(event("Notification", ["notification_type": "permission_prompt",
                                                                      "message": "Claude needs your permission to use Bash"]), store: store)
    #expect(permission?.state == .needsYou)
    #expect(permission?.lastMessage == "Claude needs your permission to use Bash")

    let plan = try ClaudeCodeFeed.handle(event("PreToolUse", ["tool_name": "ExitPlanMode", "tool_input": ["plan": "1. Do it"]]), store: store)
    #expect(plan?.state == .needsYou)
    #expect(plan?.lastMessage == "Plan ready for your approval")
}

@Test func idleAfterAFinishedReplyKeepsItsClock() throws {
    var clock = noon
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try TicketStore(fileURL: dir.appendingPathComponent("t.json"), now: { clock })
    try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "x"]), store: store)
    try ClaudeCodeFeed.handle(event("Stop", ["last_assistant_message": "Done."]), store: store)
    clock = noon + 120
    let t = try ClaudeCodeFeed.handle(event("Notification", ["notification_type": "idle_prompt", "message": "Claude is waiting for your input"]), store: store)
    #expect(t?.stateSince == noon)
    #expect(t?.lastMessage == "Done.")
}

@Test func closingTheSessionIsDoneAndStrangersAreIgnored() throws {
    let store = try makeStore()
    #expect(try ClaudeCodeFeed.handle(event("SessionEnd", ["reason": "prompt_input_exit"]), store: store) == nil)
    #expect(try ClaudeCodeFeed.handle(event("Notification", ["notification_type": "auth_success"]), store: store) == nil)
    #expect(try store.all().isEmpty)

    try ClaudeCodeFeed.handle(event("UserPromptSubmit", ["prompt": "x"]), store: store)
    #expect(try ClaudeCodeFeed.handle(event("SessionEnd", ["reason": "other"]), store: store)?.state == .done)
}

@Test func claudeInstallerKeepsOtherSettingsAndRemovesCleanly() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    setenv("CONTROL_ROOM_CLAUDE_DIR", dir.path, 1)
    defer { unsetenv("CONTROL_ROOM_CLAUDE_DIR") }
    let existing = #"{"model": "opus", "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "afplay ding.aiff"}]}]}}"#
    try existing.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

    try ClaudeCodeHooks.install()
    try ClaudeCodeHooks.install()
    let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("settings.json"))) as! [String: Any]
    #expect(installed["model"] as? String == "opus")
    let hooks = installed["hooks"] as! [String: [[String: Any]]]
    #expect(hooks["Stop"]?.count == 2)
    #expect(hooks["UserPromptSubmit"]?.count == 1)

    try ClaudeCodeHooks.remove()
    let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("settings.json"))) as! [String: Any]
    let left = removed["hooks"] as! [String: [[String: Any]]]
    #expect(left.keys.sorted() == ["Stop"])
    #expect(removed["model"] as? String == "opus")
}
