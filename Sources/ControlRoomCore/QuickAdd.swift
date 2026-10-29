import Foundation

/// Reads what Nina types into the quick-add field, for example
/// "Grok · pricing research" or "PRD review https://claude.ai/chat/abc".
public struct QuickAdd: Equatable, Sendable {
    public var tool: Tool?
    public var title: String
    public var link: String?

    public static func parse(_ text: String) -> QuickAdd {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // A pasted link or project folder becomes the deep link.
        var link: String?
        if let i = words.firstIndex(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") || Self.localFolder($0) != nil }) {
            link = words.remove(at: i)
        }
        var rest = words.joined(separator: " ")

        // A tool named before a separator: "Grok · title", "cursor: title", "Claude Code - title".
        var tool: Tool?
        let lower = rest.lowercased()
        search: for (names, t) in toolNames {
            for name in names {
                for sep in ["·", ":", "-", "–", "—", "/"] {
                    for prefix in ["\(name) \(sep)", "\(name)\(sep)"] where lower.hasPrefix(prefix) {
                        tool = t
                        rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        break search
                    }
                }
            }
        }

        if tool == nil, let link { tool = Self.tool(forLink: link) }
        return QuickAdd(tool: tool, title: rest.trimmingCharacters(in: .whitespaces), link: link)
    }

    /// Longest names first so "claude code" wins over "claude".
    private static let toolNames: [([String], Tool)] = [
        (["claude code", "cc"], .claudeCode),
        (["claude"], .claudeAI),
        (["cursor"], .cursor),
        (["grok"], .grok),
        (["devin"], .devin),
    ]

    /// A link that points at a folder on this Mac: "/Users/nina/code/edify-web", "~/code/edify-web" or a file:// URL.
    public static func localFolder(_ link: String) -> URL? {
        if link.hasPrefix("file://") { return URL(string: link) }
        if link.hasPrefix("~/") { return URL(fileURLWithPath: (link as NSString).expandingTildeInPath, isDirectory: true) }
        if link.hasPrefix("/") && link.count > 1 { return URL(fileURLWithPath: link, isDirectory: true) }
        return nil
    }

    /// The thread name to show when only a folder was given: its last part, like "edify-web".
    public static func threadName(forLink link: String) -> String? {
        guard let folder = localFolder(link) else { return nil }
        let name = folder.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    static func tool(forLink link: String) -> Tool? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        if host.hasSuffix("claude.ai") { return .claudeAI }
        if host.hasSuffix("grok.com") { return .grok }
        if host.hasSuffix("devin.ai") { return .devin }
        if host.hasSuffix("cursor.com") || host.hasSuffix("cursor.sh") { return .cursor }
        return nil
    }
}
