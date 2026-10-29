import ControlRoomCore
import SwiftUI

/// The drop-down panel, matching reference/02-notch-panel.html and 05-quiet-and-quick-reply.html.
struct PanelView: View {
    @ObservedObject var model: AppModel
    /// Most rows shown before "and N more".
    static let maxRows = 6
    static let maxWorkingRows = 8
    static let width: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                if let problem = model.serverProblem {
                    Text(problem)
                        .font(Theme.font(12.5, .regular))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.coral)
                        .bottomRule()
                }
                let waiting = model.waiting
                if waiting.isEmpty {
                    Text("Nothing is waiting on you.")
                        .font(Theme.font(13.5, .regular))
                        .foregroundStyle(Theme.bodyGrey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .bottomRule()
                }
                ForEach(waiting.prefix(Self.maxRows)) { ticket in
                    TicketRow(ticket: ticket, model: model)
                }
                if waiting.count > Self.maxRows {
                    Text("and \(waiting.count - Self.maxRows) more")
                        .font(Theme.font(12, .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .bottomRule()
                }
                counts
                if model.showWorking {
                    let working = model.working
                    ForEach(working.prefix(Self.maxWorkingRows)) { ticket in
                        WorkingRow(ticket: ticket, model: model)
                    }
                    if working.count > Self.maxWorkingRows {
                        Text("and \(working.count - Self.maxWorkingRows) more")
                            .font(Theme.font(12, .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .bottomRule()
                    }
                }
                QuickAddField(model: model)
            }
            .background(Theme.white)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1).padding(.top, -1))
            .hardShadow(8)
        }
        .frame(width: Self.width)
        .foregroundStyle(Theme.ink)
    }

    private var header: some View {
        HStack(spacing: 12) {
            FaceView(face: .expanded, pixel: 3.5)
            Text(model.waiting.isEmpty ? "NOTHING WAITING" : "\(model.waiting.count) WAITING ON YOU")
                .label(13)
            Spacer()
            if let oldest = model.waiting.first {
                Text("oldest \(Wait(since: oldest.stateSince, now: model.now).phrase)")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.lavender)
            }
        }
        .foregroundStyle(Theme.white)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.ink)
        .accessibilityElement(children: .combine)
    }

    private var counts: some View {
        HStack(spacing: 0) {
            WorkingToggle(model: model)
                .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            CountBlock(number: model.doneCount, label: "DONE TODAY", colour: Theme.mint)
        }
        .bottomRule()
    }
}

/// How long something has waited, for the time block and the header.
struct Wait {
    let number: Int
    let unit: String
    let phrase: String

    init(since: Date, now: Date) {
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        if minutes < 60 {
            number = minutes; unit = "MIN"; phrase = "\(minutes) min"
        } else {
            number = minutes / 60; unit = "HR"
            phrase = minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
        }
    }
}

struct TicketRow: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel

    var body: some View {
        let wait = Wait(since: ticket.stateSince, now: model.now)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("\(wait.number)").font(Theme.font(22, .black))
                Text(wait.unit).label(9)
            }
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .background(Theme.color(ticket.signal(at: model.now)))
            .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Waiting \(wait.phrase)")

            if ticket.source == .manual {
                VStack(spacing: 0) {
                    details.padding(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                    HStack(spacing: 0) {
                        CellButton(title: "✓ DONE", fill: Theme.mint, strong: true) { model.apply(.done, to: ticket) }
                        CellButton(title: "STILL RUNNING") { model.apply(.stillRunning, to: ticket) }
                        CellButton(title: "OPEN", strong: true, width: 90, divider: false) { model.open(ticket) }
                    }
                    .frame(height: 40)
                    .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
                }
            } else {
                details.padding(.horizontal, 16).padding(.vertical, 12)
                CellButton(title: "OPEN", strong: true, divider: false) { model.open(ticket) }
                    .frame(width: 90)
                    .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .bottomRule()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ToolBadge(tool: ticket.tool, size: 14)
                Text(context).font(Theme.font(11, .bold))
            }
            Text(ticket.title)
                .font(Theme.font(16, .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Cursor · edify-web", "Grok · added by you", "Devin · transfer-requests · blocked".
    private var context: String {
        var parts = [ticket.tool.displayName]
        parts.append(ticket.thread.isEmpty ? (ticket.source == .manual ? "added by you" : "") : ticket.thread)
        if ticket.state == .blocked { parts.append("blocked") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A tool is a black square with its initial. Never a colour.
struct ToolBadge: View {
    let tool: Tool
    var size: CGFloat = 18

    var body: some View {
        Text(tool.initial)
            .font(Theme.font(size * 0.56, .black))
            .foregroundStyle(Theme.white)
            .frame(width: size, height: size)
            .background(Theme.ink)
            .accessibilityHidden(true)
    }
}

struct CountBlock: View {
    let number: Int
    let label: String
    let colour: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)").font(Theme.font(26, .black))
            Text(label).label(11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(colour)
        .accessibilityElement(children: .combine)
    }
}

/// The Working count, which also shows or hides the list of what's running.
struct WorkingToggle: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        let count = model.workingCount
        Button { model.showWorking.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(count)").font(Theme.font(26, .black))
                Text("WORKING").label(11)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(model.showWorking ? "HIDE" : "SHOW").label(10, tracking: 0.08)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CellStyle(fill: Theme.sky))
        .disabled(count == 0)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(Theme.ink, lineWidth: 3) } }
        .accessibilityLabel("\(count) working")
        .accessibilityHint(model.showWorking ? "Hides the list" : "Shows what's running")
    }
}

/// One running agent: compact, no actions beyond Open. Working never asks for attention.
struct WorkingRow: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Text(Wait(since: ticket.stateSince, now: model.now).phrase)
                .font(Theme.font(11, .black))
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .background(Theme.sky)
                .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
                .accessibilityLabel("Running for \(Wait(since: ticket.stateSince, now: model.now).phrase)")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ToolBadge(tool: ticket.tool, size: 12)
                    Text(ticket.thread.isEmpty ? ticket.tool.displayName : "\(ticket.tool.displayName) · \(ticket.thread)")
                        .font(Theme.font(10.5, .bold))
                        .lineLimit(1)
                }
                Text(ticket.title)
                    .font(Theme.font(13.5, .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            CellButton(title: "OPEN", strong: true, divider: false) { model.open(ticket) }
                .frame(width: 90)
                .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
        }
        .frame(height: 46)
        .bottomRule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ticket.tool.displayName): \(ticket.title)")
    }
}

/// A full-height button cell inside a row. Square, with a square focus ring.
struct CellButton: View {
    let title: String
    var fill: Color = Theme.white
    var strong = false
    var width: CGFloat? = nil
    var divider = true
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(12, tracking: strong ? 0.08 : 0.06, weight: strong ? .black : .bold)
                .frame(maxWidth: width == nil ? .infinity : width, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(CellStyle(fill: fill))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(Theme.ink, lineWidth: 3) } }
        .frame(width: width)
        .overlay(alignment: .trailing) { if divider { Theme.ink.frame(width: 1) } }
    }
}

struct CellStyle: ButtonStyle {
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(configuration.isPressed ? Theme.ink.opacity(0.12) : .clear)
            .background(fill)
    }
}

extension View {
    func bottomRule() -> some View {
        overlay(alignment: .bottom) { Theme.ink.frame(height: 1) }
    }
}
