import Foundation

/// Reads what Nina types into the quick-add field, for example
/// "Grok · pricing research" or "PRD review https://claude.ai/chat/abc".
public struct QuickAdd: Equatable, Sendable {
    public var tool: Tool?
    public var title: String
    public var link: String?

    public static func parse(_ text: String) -> QuickAdd {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // A pasted link becomes the deep link.
        var link: String?
        if let i = words.firstIndex(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) {
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

    static func tool(forLink link: String) -> Tool? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        if host.hasSuffix("claude.ai") { return .claudeAI }
        if host.hasSuffix("grok.com") { return .grok }
        if host.hasSuffix("devin.ai") { return .devin }
        if host.hasSuffix("cursor.com") || host.hasSuffix("cursor.sh") { return .cursor }
        return nil
    }
}
