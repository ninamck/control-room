import AppKit
import ControlRoomCore
import SwiftUI

/// Hand off, matching reference/04-hand-off.html.
struct HandOffView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: HandOffForm
    let close: () -> Void
    @FocusState private var briefFocused: Bool

    /// The four squares. Claude here starts Claude Code.
    static let tools: [(Tool, String)] = [(.claudeCode, "CLAUDE"), (.cursor, "CURSOR"), (.devin, "DEVIN"), (.grok, "GROK")]

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                main
                    .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
                ReadyList(model: model, form: form)
                    .frame(width: 400)
            }
        }
        .background(PaperGrid())
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 1000, minHeight: 640)
        .onAppear {
            briefFocused = true
            if form.folder == nil, let first = model.handOffPlaces.first { form.pick(first, model: model) }
            model.loadReady()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FaceView(face: model.restingFace, pixel: 3)
            Text("CONTROL ROOM").label(13, tracking: 0.12)
            Spacer()
            HardStopBlock(model: model)
            Text(clock.string(from: model.now)).font(Theme.font(13, .medium))
                .padding(.leading, 4)
        }
        .padding(.horizontal, 32)
        .frame(height: 56)
        .background(Theme.paper)
        .bottomRule()
    }

    private var clock: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HAND OFF").label(12, tracking: 0.12)
                Text("What should it do?")
                    .font(Theme.font(40, .black))
                    .tracking(-1.2)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Brief").font(Theme.font(12, .bold))
                TextEditor(text: $form.brief)
                    .font(Theme.font(15, .regular))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11).padding(.vertical, 10)
                    .frame(height: 140)
                    .background(Theme.white)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    .hardShadow(6)
                    .focused($briefFocused)
                    .accessibilityLabel("Brief")
                    // Enter sends, Shift+Enter is a new line.
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        go()
                        return .handled
                    }
                Text("Shift+Enter for a new line. Enter sends.")
                    .font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
                    .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tool").font(Theme.font(12, .bold))
                    HStack(spacing: 0) {
                        ForEach(Self.tools, id: \.0) { tool, name in
                            ToolSquare(tool: tool, name: name, selected: form.tool == tool,
                                       last: tool == Self.tools.last?.0) { form.choose(tool, model: model) }
                        }
                    }
                    .background(Theme.white)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    Text("Claude and Devin start on their own. Cursor and Grok open with the brief copied.")
                        .font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Where").font(Theme.font(12, .bold))
                    WherePicker(model: model, form: form)
                    Text(form.tool == .grok ? "Grok starts a new chat." : form.tool == .devin ? "Devin picks the repo from your brief." : "Last used first.")
                        .font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
                }
                .frame(maxWidth: .infinity)
            }

            if let problem = form.problem {
                Text(problem)
                    .font(Theme.font(13, .regular))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.coral)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            }

            Spacer(minLength: 0)

            HStack {
                Text("Becomes a Working ticket. You'll hear from it only when it needs you.")
                    .font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
                Spacer()
                ShadowButton(title: "CANCEL", action: close)
                GoButton(action: go)
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func go() {
        let folder = (form.tool == .grok || form.tool == .devin) ? nil : form.folder
        if let problem = model.handOff(brief: form.brief, tool: form.tool, folder: folder, notionPage: form.notionPage) {
            form.problem = problem
        } else {
            if let old = form.replaces { model.removeTicket(old) }
            form.reset()
            close()
        }
    }
}

/// What's being handed off. Kept between openings so a half-written brief isn't lost.
@MainActor
final class HandOffForm: ObservableObject {
    @Published var brief = ""
    @Published var tool: Tool = .claudeCode
    @Published var folder: String?
    @Published var notionPage: String?
    @Published var problem: String?
    /// The End of day ticket this hand-off replaces, removed once it starts.
    var replaces: String?

    func choose(_ tool: Tool, model: AppModel) {
        self.tool = tool
        problem = nil
    }

    /// Choosing a project brings back the tool last handed off there (DECISIONS.md).
    func pick(_ path: String, model: AppModel) {
        folder = path
        if let remembered = model.places.lastTool(for: path), HandOffView.tools.contains(where: { $0.0 == remembered }) {
            tool = remembered
        }
        problem = nil
    }

    func fill(from item: NotionReady.Item) {
        brief = item.brief
        notionPage = item.id
        problem = nil
    }

    func reset() {
        brief = ""
        notionPage = nil
        replaces = nil
        problem = nil
    }
}

struct ToolSquare: View {
    let tool: Tool
    let name: String
    let selected: Bool
    let last: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(tool.initial).font(Theme.font(16, .black))
                Text(name).label(10, tracking: 0.08, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(selected ? Theme.white : Theme.ink)
            .background(selected ? Theme.ink : Theme.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(selected ? Theme.yellow : Theme.ink, lineWidth: 3) } }
        .overlay(alignment: .trailing) { if !last { Theme.ink.frame(width: 1) } }
        .accessibilityLabel(name.capitalized)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Where: known project folders, last used first, plus choosing another.
struct WherePicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: HandOffForm

    var body: some View {
        Menu {
            if form.tool == .grok || form.tool == .devin {
                Button(form.tool == .devin ? "New session" : "New chat") {}
            } else {
                ForEach(model.handOffPlaces, id: \.self) { path in
                    Button(Self.label(path)) { form.pick(path, model: model) }
                }
                Divider()
                Button("Choose a folder…") { choose() }
            }
        } label: {
            HStack {
                Text(form.tool == .grok ? "New chat" : form.tool == .devin ? "New Devin session" : form.folder.map(Self.label) ?? "Choose a project folder")
                    .font(Theme.font(14, .medium))
                    .lineLimit(1)
                Spacer()
                Text("▾").font(Theme.font(12, .bold))
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Theme.white)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Where")
    }

    /// "edify-web · ~/Documents/New AI direction"
    static func label(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        return "\(url.lastPathComponent) · \(parent)"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { form.pick(url.path, model: model) }
    }
}

struct GoButton: View {
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text("GO →")
                .label(13, tracking: 0.08)
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(Theme.ink)
                .overlay { if focused { Rectangle().strokeBorder(Theme.yellow, lineWidth: 3) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .hardShadow(3)
        .accessibilityLabel("Go")
    }
}

/// Ready to delegate: Task Tracker tasks with Agent ticked.
struct ReadyList: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: HandOffForm

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("READY TO DELEGATE").label(12, tracking: 0.12)
                Text("From Notion, ticked Agent. Click one to fill the brief.").font(Theme.font(12.5, .regular))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(Theme.lavender)
            .bottomRule()

            ScrollView {
                VStack(spacing: 0) {
                    if let problem = model.readyProblem {
                        Text(problem)
                            .font(Theme.font(13, .regular))
                            .foregroundStyle(Theme.bodyGrey)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    } else if model.ready.isEmpty {
                        Text(model.readyLoading ? "Loading from Notion…" : "Nothing ticked Agent in Task Tracker.")
                            .font(Theme.font(13, .regular))
                            .foregroundStyle(Theme.bodyGrey)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    }
                    ForEach(model.ready) { item in
                        ReadyRow(item: item, selected: form.notionPage == item.id, now: model.now) { form.fill(from: item) }
                    }
                }
            }

            HStack {
                Text(model.ready.isEmpty ? "" : "\(model.ready.count) shown")
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.notion.so/328c88a034db80f4a9a9ef206e8bb33c")!)
                } label: { Text("Open in Notion").underline() }
                    .buttonStyle(.plain)
            }
            .font(Theme.font(12, .bold))
            .padding(.horizontal, 24).padding(.vertical, 16)
            .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
        }
        .background(Theme.white)
    }
}

struct ReadyRow: View {
    let item: NotionReady.Item
    let selected: Bool
    let now: Date
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Theme.font(15, .bold)).multilineTextAlignment(.leading)
                Text(NotionReady.meta(item, now: now)).font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(selected ? Theme.paper : Theme.white)
            .overlay { if focused { Rectangle().strokeBorder(Theme.ink, lineWidth: 3) } }
            .bottomRule()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .accessibilityLabel("\(item.title), \(NotionReady.meta(item, now: now)). Fill the brief.")
    }
}
