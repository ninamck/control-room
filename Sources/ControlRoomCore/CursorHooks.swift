import Foundation

/// Installs and removes Control Room's entries in Cursor's user hooks (~/.cursor/hooks.json).
/// Other hooks already in that file are left alone.
public enum CursorHooks {
    /// ~/.cursor, or CONTROL_ROOM_CURSOR_DIR if set (used by tests).
    static var cursorDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_CURSOR_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true)
    }
    static var configURL: URL { cursorDirectory.appendingPathComponent("hooks.json") }
    static var scriptURL: URL { cursorDirectory.appendingPathComponent("hooks/control-room.sh") }
    static let command = "./hooks/control-room.sh"

    /// Hands each event to Control Room in the background and answers Cursor straight away,
    /// so it can never slow down or block an agent, even if Control Room isn't running.
    static let script = """
    #!/bin/sh
    # Control Room: tells the notch companion what Cursor's agents are doing.
    # Installed by `cr install-cursor-hooks`; remove with `cr remove-cursor-hooks`.
    CONFIG="$HOME/Library/Application Support/Control Room/config.local.json"
    payload=$(cat)
    token=$(sed -n 's/.*"token" *: *"\\([^"]*\\)".*/\\1/p' "$CONFIG" 2>/dev/null)
    port=$(sed -n 's/.*"port" *: *\\([0-9]*\\).*/\\1/p' "$CONFIG" 2>/dev/null)
    if [ -n "$token" ]; then
      printf '%s' "$payload" | curl -s -m 2 -X POST \\
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" \\
        --data-binary @- "http://127.0.0.1:${port:-47821}/feeds/cursor" >/dev/null 2>&1 &
    fi
    case "$payload" in
      *'"beforeSubmitPrompt"'*) echo '{"continue": true}' ;;
      *) echo '{}' ;;
    esac
    exit 0

    """

    public static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var config = try readConfig()
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        for event in CursorFeed.events {
            var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            entries.append(["command": command, "timeout": 5])
            hooks[event] = entries
        }
        config["version"] = config["version"] ?? 1
        config["hooks"] = hooks
        try writeConfig(config)
    }

    public static func remove() throws {
        var config = try readConfig()
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            let kept = (value as? [[String: Any]] ?? []).filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        config["hooks"] = hooks
        try writeConfig(config)
        try? FileManager.default.removeItem(at: scriptURL)
    }

    public static var isInstalled: Bool {
        guard let hooks = (try? readConfig())?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { ($0 as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains("control-room.sh") == true
    }

    private static func readConfig() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL) else { return ["version": 1] }
        guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleError("~/.cursor/hooks.json isn't valid JSON, so I left it alone.")
        }
        return config
    }

    private static func writeConfig(_ config: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: configURL, options: .atomic)
    }
}
