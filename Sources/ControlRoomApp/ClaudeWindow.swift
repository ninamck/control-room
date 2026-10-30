import AppKit
import ApplicationServices
import ControlRoomCore

/// Reads the Claude app's window through macOS Accessibility, for plain chats that leave nothing on disk.
/// Only the window's buttons and the chat's name are read, never what was written.
enum ClaudeWindow {
    static let bundleID = "com.anthropic.claudefordesktop"

    /// Asks macOS for Accessibility once; after that, System Settings holds the answer.
    static func ensureAllowed() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !UserDefaults.standard.bool(forKey: "askedForAccessibility") {
            UserDefaults.standard.set(true, forKey: "askedForAccessibility")
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        return false
    }

    static func app() -> AXUIElement? {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let ax = AXUIElementCreateApplication(running.processIdentifier)
        // Electron only builds its accessibility tree once someone asks for it.
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return ax
    }

    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(e, name as CFString, &value)
        return value
    }

    static func string(_ e: AXUIElement, _ name: String) -> String { attr(e, name) as? String ?? "" }

    static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, "AXChildren") as? [AXUIElement] ?? [] }

    // MARK: Chats

    /// The plain chats showing in Claude's windows. Nil when Claude isn't running or the window can't be read.
    /// Walks each page from the end, where the reply box and the latest messages are, and stops once it has
    /// the latest reply and question, so the long chat list in the sidebar is almost never visited.
    static func read(claudeInFront front: Bool) -> [ClaudeChatView]? {
        guard AXIsProcessTrusted(), let ax = app(),
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let windows = attr(ax, "AXWindows") as? [AXUIElement] ?? []
        guard !windows.isEmpty else { return running.isHidden ? [] : nil }
        var views: [ClaudeChatView] = []
        for window in windows {
            let main = (attr(window, "AXMain") as? Bool) ?? false
            if let view = readPage(in: window, looking: front && main) { views.append(view) }
        }
        return views
    }

    private static func readPage(in window: AXUIElement, looking: Bool) -> ClaudeChatView? {
        var name: String?
        var replying = false
        var reply: String?
        var asked: String?
        var visited = 0
        // Things that hold only message text, or the sidebar: nothing to find inside.
        let skipRoles: Set<String> = ["AXStaticText", "AXImage", "AXTextArea", "AXList", "AXTable"]
        func walk(_ e: AXUIElement) -> Bool {
            visited += 1
            if visited > 4000 || (reply != nil && asked != nil) { return true }
            let role = string(e, "AXRole")
            if skipRoles.contains(role) || string(e, "AXSubrole") == "AXLandmarkNavigation" { return false }
            switch role {
            case "AXWebArea":
                if let found = ClaudeChatView.chatName(fromPageTitle: string(e, "AXTitle")) { name = found }
                else if name == nil, string(e, "AXTitle").hasSuffix(" - Claude Code") { return true }
            case "AXButton":
                if string(e, "AXDescription") == "Stop response" || string(e, "AXTitle") == "Stop response" { replying = true }
                return false
            case "AXHeading":
                let label = [string(e, "AXTitle"), string(e, "AXDescription")].first { !$0.isEmpty } ?? ""
                if reply == nil, let text = ClaudeChatView.strip(label, prefix: "Claude responded:") { reply = text }
                if asked == nil, let text = ClaudeChatView.strip(label, prefix: "You said:") { asked = text }
                return false
            default: break
            }
            for child in children(e).reversed() where walk(child) { return true }
            return false
        }
        _ = walk(window)
        guard let name else { return nil }
        return ClaudeChatView(name: name, replying: replying, lastReply: reply, lastAsked: asked, looking: looking)
    }

    // MARK: Probe

    static var probeFlag: URL { Config.directory.appendingPathComponent("claude-window-probe") }

    /// While working out the window's layout: when the flag file exists, writes the tree's shape next to it.
    /// Buttons, headings and links only, with their labels cut short; no message text.
    static func probeIfAsked() {
        guard FileManager.default.fileExists(atPath: probeFlag.path), let ax = app() else { return }
        try? FileManager.default.removeItem(at: probeFlag)
        var lines: [String] = ["trusted: \(AXIsProcessTrusted())"]
        var count = 0
        func walk(_ e: AXUIElement, _ depth: Int) {
            count += 1
            guard count < 20000, depth < 60 else { return }
            let role = string(e, "AXRole")
            let interesting = ["AXWindow", "AXButton", "AXHeading", "AXLink", "AXWebArea", "AXTextArea", "AXMenuButton", "AXPopUpButton"]
            if interesting.contains(role) || depth < 4 {
                let label = [string(e, "AXTitle"), string(e, "AXDescription"), string(e, "AXHelp")]
                    .filter { !$0.isEmpty }.map { String($0.prefix(40)) }.joined(separator: " | ")
                let dom = string(e, "AXDOMIdentifier")
                lines.append(String(repeating: " ", count: depth) + "\(role) [\(label)]" + (dom.isEmpty ? "" : " #\(dom)"))
            }
            for child in children(e) { walk(child, depth + 1) }
        }
        walk(ax, 0)
        lines.append("nodes: \(count)")
        let start = Date()
        let views = read(claudeInFront: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID)
        lines.append("read in \(Int(Date().timeIntervalSince(start) * 1000)) ms: " + (views?.map { "\($0.name) replying=\($0.replying) looking=\($0.looking) reply=\($0.lastReply != nil) asked=\($0.lastAsked != nil)" }.joined(separator: "; ") ?? "nil"))
        try? lines.joined(separator: "\n").write(to: Config.directory.appendingPathComponent("claude-window-probe.txt"), atomically: true, encoding: .utf8)
    }
}
