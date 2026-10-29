import Foundation

/// Installs and removes Control Room's entries in Claude Code's user settings (~/.claude/settings.json).
/// Everything else in that file, including other hooks, is left alone.
public enum ClaudeCodeHooks {
    /// ~/.claude, or CONTROL_ROOM_CLAUDE_DIR if set (used by tests).
    static var claudeDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_CLAUDE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
    static var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    static var scriptURL: URL { claudeDirectory.appendingPathComponent("hooks/control-room.sh") }

    /// Adds which app the session runs in (Claude desktop, Cursor's terminal, Terminal...) so Open can go there,
    /// hands the event to Control Room in the background, and prints nothing, so Claude Code carries on as normal.
    static let script = """
    #!/bin/sh
    # Control Room: tells the notch companion what Claude Code sessions are doing.
    # Installed by `cr install-claude-hooks`; remove with `cr remove-claude-hooks`.
    CONFIG="$HOME/Library/Application Support/Control Room/config.local.json"
    payload=$(cat)
    clean() { printf '%s' "$1" | tr -d '"\\\\\\n'; }
    env_json="\\"_env\\":{\\"app\\":\\"$(clean "$__CFBundleIdentifier")\\",\\"term\\":\\"$(clean "$TERM_PROGRAM")\\",\\"entrypoint\\":\\"$(clean "$CLAUDE_CODE_ENTRYPOINT")\\"},"
    payload="{${env_json}${payload#\\{}"
    token=$(sed -n 's/.*"token" *: *"\\([^"]*\\)".*/\\1/p' "$CONFIG" 2>/dev/null)
    port=$(sed -n 's/.*"port" *: *\\([0-9]*\\).*/\\1/p' "$CONFIG" 2>/dev/null)
    # If Control Room is closed or restarting, keep the event in a queue it reads when it's back.
    QUEUE="$HOME/Library/Application Support/Control Room/queue/claude-code"
    (
      if [ -z "$token" ] || ! printf '%s' "$payload" | curl -sf -m 2 -X POST \\
          -H "Authorization: Bearer $token" -H "Content-Type: application/json" \\
          --data-binary @- "http://127.0.0.1:${port:-47821}/feeds/claude-code" >/dev/null 2>&1; then
        mkdir -p "$QUEUE" && printf '%s' "$payload" > "$QUEUE/$(date +%s)-$$.json"
      fi
    ) </dev/null >/dev/null 2>&1 &
    exit 0

    """

    static let command = "$HOME/.claude/hooks/control-room.sh"

    public static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in ClaudeCodeFeed.events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).compactMap(withoutOurs)
            groups.append(["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 5]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    public static func remove() throws {
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            let kept = (value as? [[String: Any]] ?? []).compactMap(withoutOurs)
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: scriptURL)
    }

    /// A hook group with our command taken out, or nil if nothing else was in it.
    private static func withoutOurs(_ group: [String: Any]) -> [String: Any]? {
        var group = group
        let commands = (group["hooks"] as? [[String: Any]] ?? []).filter {
            ($0["command"] as? String)?.contains("control-room.sh") != true
        }
        guard !commands.isEmpty else { return nil }
        group["hooks"] = commands
        return group
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleError("~/.claude/settings.json isn't valid JSON, so I left it alone.")
        }
        return settings
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
