import AppKit
import ControlRoomCore

/// Starting and opening the tools Hand off sends work to.
@MainActor
enum Launcher {
    /// Where Anthropic's installer and other common setups put the `claude` command.
    static func claudeCode() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Opens a Terminal window in the project running Claude Code with the brief as its first message.
    /// The session id is fixed up front so its hook events land on the hand-off ticket.
    static func startClaudeCode(_ claude: String, brief: String, folder: String, sessionID: String) throws {
        let dir = Config.directory.appendingPathComponent("handoff", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The brief goes in its own file so nothing in it can be mistaken for a command.
        let briefFile = dir.appendingPathComponent("\(sessionID).txt")
        try brief.write(to: briefFile, atomically: true, encoding: .utf8)
        let script = """
        #!/bin/zsh -l
        # Started by Control Room's Hand off.
        cd \(quoted(folder)) || exit 1
        # Which Terminal window this is, so a quick reply from the panel types into this one only.
        tty > \(quoted(dir.appendingPathComponent("\(sessionID).tty").path))
        clear
        \(quoted(claude)) --session-id \(sessionID) "$(cat \(quoted(briefFile.path)))"

        """
        let command = dir.appendingPathComponent("\(sessionID).command")
        try script.write(to: command, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        // .command files open in Terminal.
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw RuleError("Terminal isn't on this Mac.")
        }
        NSWorkspace.shared.open([command], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The Terminal device of a session Hand off started, if it's still recorded.
    static func handOffTerminal(for session: String) -> String? {
        let file = Config.directory.appendingPathComponent("handoff/\(session).tty")
        guard let tty = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              tty.hasPrefix("/dev/") else { return nil }
        return tty
    }

    /// Types an answer into the Terminal window running that Claude Code session, then Return.
    /// The first time, macOS asks Nina to let Control Room control Terminal.
    static func type(_ answer: String, intoClaudeSession session: String) throws {
        guard let tty = handOffTerminal(for: session) else { throw RuleError("Control Room doesn't know that session's Terminal window.") }
        let text = answer.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        do script "\(text)" in t
                        return "sent"
                    end if
                end repeat
            end repeat
        end tell
        return "closed"
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                throw RuleError("Control Room isn't allowed to control Terminal. Allow it in System Settings → Privacy & Security → Automation.")
            }
            throw RuleError(error[NSAppleScript.errorMessage] as? String ?? "Terminal didn't take the reply.")
        }
        guard result?.stringValue == "sent" else { throw RuleError("That session's Terminal window has been closed.") }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Single-quoted for the shell.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
