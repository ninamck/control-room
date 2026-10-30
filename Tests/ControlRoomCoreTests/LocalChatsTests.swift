import Foundation
import Testing
@testable import ControlRoomCore

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeLines(_ lines: [String], to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

/// A Claude app session folder: local_<id>.json and local_<id>/audit.jsonl.
private func claudeSession(_ root: URL, id: String, title: String, task: String? = nil, audit: [String]) {
    let space = root.appendingPathComponent("acct/space")
    var session: [String: Any] = ["sessionId": "local_\(id)", "title": title, "isArchived": false, "initialMessage": "Start"]
    if let task { session["scheduledTaskId"] = task }
    try! FileManager.default.createDirectory(at: space, withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: session).write(to: space.appendingPathComponent("local_\(id).json"))
    writeLines(audit, to: space.appendingPathComponent("local_\(id)/audit.jsonl"))
}

private let userLine = #"{"type":"user","message":{"content":[{"type":"text","text":"Summarise the Pret calls"}]}}"#
private let toolLine = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/notes.md"}}]}}"#
private let progressLine = #"{"type":"tool_progress"}"#
private let replyLine = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Here's the summary. Want me to send it to Alistair?"}]}}"#
private let resultLine = #"{"type":"result","subtype":"success","usage":{"thinking_tokens":120}}"#

@Test func claudeAppSessionsReadAsWorkingRepliedOrWaiting() {
    let root = tempDir()
    claudeSession(root, id: "a", title: "Pret calls", audit: [userLine, toolLine, progressLine])
    claudeSession(root, id: "b", title: "Pret summary", audit: [userLine, toolLine, replyLine, resultLine])
    claudeSession(root, id: "c", title: "Needs a yes", audit: [userLine, #"{"type":"system","subtype":"permission_request"}"#])
    let chats = Dictionary(uniqueKeysWithValues: ClaudeAppChats.scan(root: root).map { ($0.chatName!, $0) })

    #expect(chats["Pret calls"]?.status == .working("Reading notes.md"))
    #expect(chats["Pret calls"]?.asked == "Summarise the Pret calls")
    #expect(chats["Pret summary"]?.status == .replied("Here's the summary. Want me to send it to Alistair?"))
    #expect(chats["Needs a yes"]?.status == .waiting("Wants your permission to carry on"))
}

@Test func newerClaudeSessionsLogInAShortFolder() {
    let root = tempDir()
    let space = root.appendingPathComponent("acct/space")
    try! FileManager.default.createDirectory(at: space, withIntermediateDirectories: true)
    let session: [String: Any] = ["sessionId": "local_14a06876-2b81", "title": "PM News", "isArchived": false]
    try! JSONSerialization.data(withJSONObject: session).write(to: space.appendingPathComponent("local_14a06876-2b81.json"))
    writeLines([userLine, replyLine, resultLine], to: space.appendingPathComponent("14a06876/audit.jsonl"))
    #expect(ClaudeAppChats.scan(root: root).first?.status == .replied("Here's the summary. Want me to send it to Alistair?"))
}

@Test func claudeScheduledRunsLandQuietlyAndReplaceUnreadOnes() throws {
    let root = tempDir()
    let space = root.appendingPathComponent("acct/space")
    try FileManager.default.createDirectory(at: space, withIntermediateDirectories: true)
    try #"{"scheduledTasks":[{"id":"morning-briefing","cronExpression":"0 9 * * 1-5"}]}"#
        .write(to: space.appendingPathComponent("scheduled-tasks.json"), atomically: true, encoding: .utf8)
    claudeSession(root, id: "run1", title: "Morning briefing", task: "morning-briefing", audit: [userLine, replyLine, resultLine])

    let store = try TicketStore(fileURL: tempDir().appendingPathComponent("t.json"), now: { noon })
    try LocalChatFeed.apply(ClaudeAppChats.scan(root: root), store: store, seen: [:])
    let landed = try store.all()
    #expect(landed.count == 1)
    #expect(landed[0].kind == .scheduled)
    #expect(landed[0].state == .needsYou)
    #expect(landed[0].title == "Morning briefing")
    #expect(landed[0].schedule?.cadence == "weekdays")
    #expect(landed[0].lastMessage.hasPrefix("Here's the summary"))

    // Tomorrow's run lands; the unread one goes.
    claudeSession(root, id: "run2", title: "Morning briefing", task: "morning-briefing", audit: [userLine, replyLine, resultLine])
    try LocalChatFeed.apply(ClaudeAppChats.scan(root: root), store: store, seen: [:])
    #expect(try store.all().map(\.externalId) == ["claude-app:local_run2"])
}

/// Grok Bot's files: names are the base32 of their keys.
private func grokFile(_ root: URL, key: String, json: String) {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    var bits = 0, value = 0, name = ""
    for byte in Array(key.utf8) {
        value = (value << 8) | Int(byte); bits += 8
        while bits >= 5 { name.append(alphabet[(value >> (bits - 5)) & 31]); bits -= 5 }
    }
    if bits > 0 { name.append(alphabet[(value << (5 - bits)) & 31]) }
    try! json.write(to: root.appendingPathComponent(name + ".blob"), atomically: true, encoding: .utf8)
}

@Test func grokBotChatsShowRepliesUntilReadInGrok() throws {
    let root = tempDir()
    let now = Date()
    let ms = Int(now.timeIntervalSince1970 * 1000)
    func roster(unread: Int) -> String {
        #"{"schemaVersion":4,"value":{"rows":[{"id":"g1","name":"Pricing scout","hasUnread":\#(unread > 0),"unreadCount":\#(unread),"lastActivityAt":\#(ms),"newestEntryId":"e\#(unread)","lastEntry":{"kind":"text","text":"Found three competitors."}}]}}"#
    }
    let prefix = "sand.client.slice.account.google-oauth2%7Cuser_X"
    grokFile(root, key: "\(prefix).roster.last-roster", json: roster(unread: 0))
    grokFile(root, key: "\(prefix).transcript.replicas.g1", json: #"{"value":{"entries":[{"kind":"send-message","seq":1,"message":{"type":"text","content":"Find competitor prices"}}]}}"#)

    #expect(GrokBotChats.decode("onqw4za") == "sand")
    let working = GrokBotChats.scan(root: root, now: now)
    #expect(working.first?.status == .working("Thinking"))
    #expect(working.first?.asked == "Find competitor prices")
    #expect(working.first?.chatName == "Pricing scout")

    let store = try TicketStore(fileURL: tempDir().appendingPathComponent("t.json"))
    try LocalChatFeed.apply(working, store: store, seen: nil)
    #expect(try store.all().first?.state == .working)

    grokFile(root, key: "\(prefix).roster.last-roster", json: roster(unread: 2))
    grokFile(root, key: "\(prefix).transcript.replicas.g1", json: #"{"value":{"entries":[{"kind":"send-message","seq":1,"message":{"type":"text","content":"Find competitor prices"}},{"kind":"message","role":"assistant","seq":2,"isStreaming":false,"content":"Found three competitors."}]}}"#)
    try LocalChatFeed.apply(GrokBotChats.scan(root: root, now: now), store: store, seen: [:])
    let replied = try store.all()[0]
    #expect(replied.state == .needsYou)
    #expect(replied.lastMessage == "Found three competitors.")
    #expect(replied.tool == .grok)
    #expect(replied.hostApp == "com.anysphere.sand")

    // Nina reads it in Grok Bot: the unread count clears and so does the ticket.
    grokFile(root, key: "\(prefix).roster.last-roster", json: roster(unread: 0).replacingOccurrences(of: "\"e0\"", with: "\"e2\""))
    try LocalChatFeed.apply(GrokBotChats.scan(root: root, now: now), store: store, seen: [:])
    #expect(try store.all()[0].state == .done)
}

@Test func firstLookDoesNotFloodTheBoardWithOldReplies() throws {
    let old = LocalChat(key: "claude-app:old", tool: .claudeAI, kind: .interactive, chatName: "Yesterday", asked: "x",
                        status: .replied("Done."), signature: "replied|10", lastActivity: noon, hostApp: "x")
    let store = try TicketStore(fileURL: tempDir().appendingPathComponent("t.json"))
    try LocalChatFeed.apply([old], store: store, seen: nil)
    #expect(try store.all().isEmpty)
    // Something new happens in it afterwards: now it shows.
    var newer = old
    newer.signature = "replied|20"
    try LocalChatFeed.apply([newer], store: store, seen: ["claude-app:old": "replied|10"])
    #expect(try store.all().count == 1)
    // Its wait counts from the reply, not from when Control Room saw it.
    #expect(try store.all()[0].stateSince == noon)
}
