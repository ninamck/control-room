import Testing
@testable import ControlRoomCore

@Test func toolBeforeSeparator() {
    #expect(QuickAdd.parse("Grok · pricing research") == QuickAdd(tool: .grok, title: "pricing research"))
    #expect(QuickAdd.parse("cursor: stocktake refactor") == QuickAdd(tool: .cursor, title: "stocktake refactor"))
    #expect(QuickAdd.parse("Claude Code - fix GRN save") == QuickAdd(tool: .claudeCode, title: "fix GRN save"))
    #expect(QuickAdd.parse("claude · PRD review") == QuickAdd(tool: .claudeAI, title: "PRD review"))
}

@Test func noToolNamed() {
    #expect(QuickAdd.parse("Cursor rules cleanup") == QuickAdd(tool: nil, title: "Cursor rules cleanup"))
}

@Test func linkIsPulledOutAndNamesTheTool() {
    let q = QuickAdd.parse("PRD review https://claude.ai/chat/abc")
    #expect(q == QuickAdd(tool: .claudeAI, title: "PRD review", link: "https://claude.ai/chat/abc"))
    let named = QuickAdd.parse("Cursor · thing https://example.com/x")
    #expect(named.tool == .cursor)
    #expect(named.link == "https://example.com/x")
}
