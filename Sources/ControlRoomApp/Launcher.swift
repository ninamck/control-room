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

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Single-quoted for the shell.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
