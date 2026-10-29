import ControlRoomCore
import SwiftUI

/// The board window, matching reference/01-board-window.html.
struct BoardView: View {
    @ObservedObject var model: AppModel
    /// Off only for snapshots: the image renderer can't draw scroll views.
    var scrolls = true
    @State private var adding = false
    @State private var showAllWorking = false
    @State private var showDone = false

    static let workingShown = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            if adding {
                QuickAddField(model: model)
                    .background(Theme.white)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    .hardShadow(6)
                    .padding(.horizontal, 32).padding(.vertical, 16)
                    .bottomRule()
            }
            HStack(spacing: 0) {
                blocks
                    .frame(width: 340)
                    .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
                if scrolls {
                    ScrollView { main }
                } else {
                    main.frame(maxHeight: .infinity, alignment: .top).clipped()
                }
            }
        }
        .background(PaperGrid())
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 960, minHeight: 640)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            FaceView(face: model.restingFace, pixel: 3)
            Text("CONTROL ROOM").label(13, tracking: 0.12)
            Spacer()
            Text(Self.dateLine(model.now)).font(Theme.font(13, .medium))
                .padding(.trailing, 4)
            ShadowButton(title: adding ? "CLOSE" : "+ ADD") { adding.toggle() }
                .accessibilityLabel(adding ? "Close add a ticket" : "Add a ticket")
            ShadowButton(title: "HAND OFF", fill: Theme.yellow) { model.openHandOff(nil) }
        }
        .padding(.horizontal, 32)
        .frame(height: 56)
        .background(Theme.paper)
        .bottomRule()
    }

    static func dateLine(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE d MMM · HH:mm"
        return f.string(from: date)
    }

    // MARK: Left column

    private var blocks: some View {
        GeometryReader { geo in
            let unit = geo.size.height / 7
            VStack(spacing: 0) {
                BigBlock(label: "WAITING ON YOU", number: model.waiting.count, numeral: 160, colour: Theme.pink) {
                    if let oldest = model.waiting.first {
                        Text("oldest\n\(Wait(since: oldest.stateSince, now: model.now).phrase)")
                    }
                }
                .frame(height: unit * 3)
                .bottomRule()
                BigBlock(label: "WORKING", number: model.workingCount, numeral: 96, colour: Theme.sky) {
                    Text("leave them\nalone")
                }
                .frame(height: unit * 2)
                .bottomRule()
                BigBlock(label: "DONE TODAY", number: model.doneCount, numeral: 96, colour: Theme.mint) {
                    if model.doneCount > 0 {
                        Button { showDone.toggle() } label: {
                            Text(showDone ? "hide" : "see all").underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showDone ? "Hide what's done today" : "See all done today")
                    }
                }
                .frame(height: unit * 2)
            }
        }
    }

    // MARK: Main

    private var main: some View {
        VStack(alignment: .leading, spacing: 28) {
            decisions
            if !model.working.isEmpty { working }
            if showDone { done }
        }
        .padding(.horizontal, 32).padding(.vertical, 28)
        .padding(.trailing, 6)  // room for card shadows
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var decisions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NEEDS A DECISION").label(12, tracking: 0.12)
                .accessibilityAddTraits(.isHeader)
            if model.waiting.isEmpty {
                Text("Nothing needs you right now.")
                    .font(Theme.font(13.5, .regular))
                    .foregroundStyle(Theme.bodyGrey)
            }
            ForEach(model.waiting) { ticket in
                DecisionCard(ticket: ticket, model: model)
            }
        }
    }

    private var working: some View {
        let all = model.working
        let shown = showAllWorking ? all : Array(all.prefix(Self.workingShown))
        return VStack(alignment: .leading, spacing: 14) {
            Text("STILL WORKING").label(12, tracking: 0.12)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(shown) { ticket in
                    CompactRow(ticket: ticket, model: model, colour: Theme.sky)
                }
            }
            if all.count > Self.workingShown {
                Button { showAllWorking.toggle() } label: {
                    Text(showAllWorking ? "show fewer" : (all.count - Self.workingShown == 1 ? "and one more" : "and \(all.count - Self.workingShown) more"))
                        .font(Theme.font(12, .bold)).underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DONE TODAY").label(12, tracking: 0.12)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.done) { ticket in
                    CompactRow(ticket: ticket, model: model, colour: Theme.mint)
                }
            }
        }
    }
}

/// One of the three big colour blocks on the left.
struct BigBlock<Note: View>: View {
    let label: String
    let number: Int
    let numeral: CGFloat
    let colour: Color
    @ViewBuilder let note: () -> Note

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).label(12, tracking: 0.12)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                Text("\(number)")
                    .font(Theme.font(numeral, .black))
                    .tracking(-numeral * 0.04)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                note()
                    .font(Theme.font(13, .bold))
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(colour)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(number) \(label.lowercased())")
    }
}

/// A full card for something that needs Nina: time block, where it is, title, last message, actions.
struct DecisionCard: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel

    var body: some View {
        let wait = Wait(since: ticket.stateSince, now: model.now)
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("\(wait.number)").font(Theme.font(26, .black)).tracking(-0.5)
                Text(wait.unit).label(10)
            }
            .frame(width: 72)
            .frame(maxHeight: .infinity)
            .background(Theme.color(ticket.signal(at: model.now)))
            .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Waiting \(wait.phrase)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ToolBadge(tool: ticket.tool)
                    Text(context).font(Theme.font(12, .bold)).lineLimit(1)
                }
                Text(ticket.title)
                    .font(Theme.font(22, .bold))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = preview {
                    Text(message)
                        .font(Theme.font(13.5, .regular))
                        .foregroundStyle(Theme.bodyGrey)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                CardButton(title: "OPEN", fill: Theme.ink, text: Theme.white, strong: true) { model.open(ticket) }
                CardButton(title: "✓ DONE", fill: Theme.mint, strong: true) { model.apply(.done, to: ticket) }
                if ticket.source == .manual {
                    CardButton(title: "STILL RUNNING") { model.apply(.stillRunning, to: ticket) }
                } else if ticket.state == .needsYou {
                    CardButton(title: "LATER") { model.apply(.later, to: ticket) }
                }
            }
            .frame(width: 128)
            .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.white)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .hardShadow(6)
        .accessibilityElement(children: .contain)
    }

    private var context: String {
        var parts = [ticket.tool.displayName]
        parts.append(ticket.contextName.isEmpty ? (ticket.source == .manual ? "added by you" : "") : ticket.contextName)
        if ticket.state == .blocked { parts.append("blocked") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var preview: String? {
        let text = ticket.lastMessage
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}

/// A stacked action in a card's right column. The first one fills, the rest get a rule above.
struct CardButton: View {
    let title: String
    var fill: Color = Theme.white
    var text: Color = Theme.ink
    var strong = false
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(strong ? 13 : 12, tracking: strong ? 0.08 : 0.06, weight: strong ? .black : .bold)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(CellStyle(fill: fill))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay { if focused { Rectangle().strokeBorder(fill == Theme.ink ? Theme.yellow : Theme.ink, lineWidth: 3) } }
        .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
    }
}

/// A compact row for Still working and Done today. Clicking it opens the chat; nothing else.
struct CompactRow: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel
    let colour: Color
    @FocusState private var focused: Bool

    var body: some View {
        Button { model.open(ticket) } label: {
            HStack(spacing: 14) {
                colour.frame(width: 10)
                    .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ticket.title)
                        .font(Theme.font(13.5, .medium))
                        .lineLimit(1)
                    if ticket.state == .working, let activity = ticket.activity, let at = ticket.activityAt {
                        Text("\(activity) · \(WorkingRow.ago(at, model.now))")
                            .font(Theme.font(11, .regular))
                            .foregroundStyle(Theme.bodyGrey)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(ticket.tool.displayName.replacingOccurrences(of: " Code", with: "")) · \(Self.short(ticket.stateSince, model.now))")
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.bodyGrey)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.trailing, 14)
            .frame(height: 48)
            .background(Theme.white)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: focused ? 3 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .help(ticket.contextName.isEmpty ? ticket.title : "\(ticket.contextName): \(ticket.title)")
        .accessibilityLabel("\(ticket.tool.displayName): \(ticket.title). Open.")
    }

    /// "4m", "1h 12m".
    static func short(_ since: Date, _ now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// White button with a solid 3px ink shadow, like + ADD.
struct ShadowButton: View {
    let title: String
    var fill: Color = Theme.white
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(13, tracking: 0.04, weight: .bold)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(fill)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: focused ? 3 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .hardShadow(3)
    }
}

/// Paper with the 40px grid from the style sheet. Decorative only.
struct PaperGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.paper))
            var lines = Path()
            for x in stride(from: 0, through: size.width, by: 40) {
                lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 40) {
                lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            }
            context.fill(lines, with: .color(Color(hex: 0xE8E3D8)))
        }
        .accessibilityHidden(true)
    }
}
