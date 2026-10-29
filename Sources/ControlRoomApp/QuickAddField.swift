import ControlRoomCore
import SwiftUI

/// "Add a ticket: Grok · pricing research". A pasted link becomes the ticket's Open link.
/// If no tool is named, four tool squares appear to pick one.
struct QuickAddField: View {
    @ObservedObject var model: AppModel
    /// The panel's footer has Open Board beside the field (reference/02-notch-panel.html); the board's own doesn't.
    var showsOpenBoard = false
    @State private var text = ""
    @State private var chosen: Tool?
    @FocusState private var fieldFocused: Bool

    /// The four tools in the order of the Hand off mockup. Claude here means claude.ai.
    static let pickable: [Tool] = [.claudeAI, .cursor, .devin, .grok]

    private var parsed: QuickAdd { QuickAdd.parse(text) }
    private var tool: Tool? { parsed.tool ?? chosen }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TextField("Add a ticket", text: $text, prompt: Text("Add a ticket: Grok · pricing research").foregroundStyle(Theme.bodyGrey))
                    .textFieldStyle(.plain)
                    .font(Theme.font(13, .regular))
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .onSubmit(add)
                    .accessibilityLabel("Add a ticket")
                if let tool, parsed.tool != nil {
                    HStack(spacing: 6) {
                        ToolBadge(tool: tool, size: 14)
                        Text(tool.displayName.uppercased()).label(11)
                    }
                    .padding(.trailing, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tool: \(tool.displayName)")
                }
                if showsOpenBoard {
                    CellButton(title: "OPEN BOARD", strong: true, width: 120, divider: false) { model.openBoard() }
                        .frame(height: 44)
                        .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
                }
            }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty && parsed.tool == nil {
                HStack(spacing: 0) {
                    Text("WHICH TOOL?").label(11)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)
                    ForEach(Self.pickable, id: \.self) { t in
                        ToolChoice(tool: t, selected: chosen == t) { chosen = t }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 36)
                .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
            }
        }
    }

    private func add() {
        if model.quickAdd(text, tool: chosen) {
            text = ""
            chosen = nil
        }
        fieldFocused = true
    }
}

struct ToolChoice: View {
    let tool: Tool
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tool.initial).font(Theme.font(10, .black))
                Text(tool.displayName.uppercased()).label(11)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .foregroundStyle(selected ? Theme.white : Theme.ink)
            .background(selected ? Theme.ink : Theme.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(Theme.ink, lineWidth: 3) } }
        .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
