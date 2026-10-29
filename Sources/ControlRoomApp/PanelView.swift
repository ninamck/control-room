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
                if let problem = model.serverProblem ?? model.devinProblem {
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
                QuickAddField(model: model, showsOpenBoard: true)
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
            FaceView(face: model.isQuiet ? .asleep : .expanded, pixel: 3.5)
            if model.isQuiet, let until = model.quietUntil {
                // reference/05-quiet-and-quick-reply.html
                Text("QUIET UNTIL \(Self.clock.string(from: until))").label(13)
                Spacer()
                HeaderButtons(items: [("+25", false, { model.extendQuiet(minutes: 25) }),
                                      ("+50", false, { model.extendQuiet(minutes: 50) }),
                                      ("WAKE", true, { model.wake() })])
            } else {
                Text(model.waiting.isEmpty ? "NOTHING WAITING" : "\(model.waiting.count) WAITING ON YOU")
                    .label(13)
                Spacer()
                if choosingQuiet {
                    Text("QUIET FOR").label(11).foregroundStyle(Theme.lavender)
                    HeaderButtons(items: [25, 50, 90].map { minutes in
                        ("\(minutes)", false, { model.quiet(minutes: minutes); choosingQuiet = false })
                    })
                } else {
                    if let oldest = model.waiting.first {
                        Text("oldest \(Wait(since: oldest.stateSince, now: model.now).phrase)")
                            .font(Theme.font(12, .medium))
                            .foregroundStyle(Theme.lavender)
                    }
                    HeaderButtons(items: [("QUIET", false, { choosingQuiet = true })])
                }
            }
        }
        .foregroundStyle(Theme.white)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.ink)
    }

    @State private var choosingQuiet = false

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var counts: some View {
        HStack(spacing: 0) {
            WorkingToggle(model: model)
                .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            CountBlock(number: model.doneCount, label: "DONE TODAY", colour: Theme.mint)
        }
        .bottomRule()
    }
}

/// Small outlined buttons on the black panel header, like +25 +50 WAKE in the quiet mockup.
struct HeaderButtons: View {
    let items: [(String, Bool, () -> Void)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                HeaderButton(title: items[i].0, highlighted: items[i].1, divider: i < items.count - 1, action: items[i].2)
            }
        }
        .frame(height: 28)
        .overlay(Rectangle().strokeBorder(Theme.white, lineWidth: 1))
    }
}

struct HeaderButton: View {
    let title: String
    let highlighted: Bool
    let divider: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(11, tracking: 0.04, weight: highlighted ? .black : .bold)
                .foregroundStyle(highlighted ? Theme.ink : Theme.white)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .background(highlighted ? Theme.yellow : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(Theme.yellow, lineWidth: 2) } }
        .overlay(alignment: .trailing) { if divider { Theme.white.frame(width: 1) } }
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
        let ran = ticket.kind == .scheduled ? ticket.schedule.map { PanelView.clock.string(from: $0.expected) } : nil
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(ran ?? "\(wait.number)").font(Theme.font(ran == nil ? 22 : 17, .black))
                Text(ran == nil ? wait.unit : "RAN").label(9)
            }
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .background(Theme.color(ticket.signal(at: model.now)))
            .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Waiting \(wait.phrase)")

            VStack(spacing: 0) {
                details.padding(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                HStack(spacing: 0) {
                    if ticket.kind == .scheduled {
                        CellButton(title: ticket.lastMessage.isEmpty ? "READ IT" : "✓ DONE", fill: Theme.mint, strong: true) { model.markRead(ticket) }
                        if !ticket.lastMessage.isEmpty { CellButton(title: "READ") { model.read(ticket) } }
                    } else if let replies = model.quickReplies(for: ticket) {
                        // Answer from here (reference/05-quick-reply). The affirmative is mint; Open stays as the fallback.
                        ForEach(replies.indices, id: \.self) { n in
                            let reply = replies[n]
                            CellButton(title: reply.label, fill: reply.affirmative ? Theme.mint : Theme.white, strong: reply.affirmative) {
                                model.quickReply(ticket, reply.answer)
                            }
                        }
                    } else {
                    // Done is always Nina's call. Manual tickets can also go back to running;
                    // agent tickets go back on their own when she prompts again, so they get Later instead.
                    CellButton(title: "✓ DONE", fill: Theme.mint, strong: true) { model.apply(.done, to: ticket) }
                    if ticket.source == .manual {
                        CellButton(title: "STILL RUNNING") { model.apply(.stillRunning, to: ticket) }
                    } else if ticket.state == .needsYou {
                        CellButton(title: "LATER") { model.apply(.later, to: ticket) }
                    }
                    }
                    CellButton(title: "OPEN", strong: true, width: 90, divider: false) { model.open(ticket) }
                }
                .frame(height: 40)
                .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
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
            if let reply = replyPreview {
                Text(reply)
                    .font(Theme.font(12.5, .regular))
                    .foregroundStyle(Theme.bodyGrey)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityLabel("Reply: \(reply)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The start of the agent's last reply, so Nina can tell whether to go back now.
    private var replyPreview: String? {
        guard ticket.source == .automatic else { return nil }
        let text = ticket.lastMessage
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// "Cursor · Predictive ordering UI sweep", "Grok · added by you", "Devin · transfer-requests · blocked".
    private var context: String {
        var parts = [ticket.tool.displayName]
        parts.append(ticket.contextName.isEmpty ? (ticket.source == .manual ? "added by you" : "") : ticket.contextName)
        if ticket.state == .blocked { parts.append("blocked") }
        // "· yes or no" / "· pick one", as in reference/05-quiet-and-quick-reply.html.
        if model.quickReplies(for: ticket) != nil {
            if case .choice = ticket.questionType { parts.append("pick one") } else { parts.append("yes or no") }
        }
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
                    Text(ticket.contextName.isEmpty ? ticket.tool.displayName : "\(ticket.tool.displayName) · \(ticket.contextName)")
                        .font(Theme.font(10.5, .bold))
                        .lineLimit(1)
                }
                Text(ticket.title)
                    .font(Theme.font(13.5, .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let activity = ticket.activity, let at = ticket.activityAt {
                    Text("\(activity) · \(Self.ago(at, model.now))")
                        .font(Theme.font(11.5, .regular))
                        .foregroundStyle(Theme.bodyGrey)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Now: \(activity), \(Self.ago(at, model.now))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            CellButton(title: "OPEN", strong: true, divider: false) { model.open(ticket) }
                .frame(width: 90)
                .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .bottomRule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ticket.tool.displayName): \(ticket.title)")
    }

    /// "just now", "12s ago", "4 min ago".
    static func ago(_ date: Date, _ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60)h ago"
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
