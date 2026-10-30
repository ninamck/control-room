import AppKit
import ControlRoomCore
import SwiftUI

/// End of day, matching reference/06-end-of-day.html.
struct EndOfDayView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var allDone = false

    static let doneShown = 6

    var body: some View {
        let summary = model.endOfDay
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FaceView(face: model.restingFace, size: 24)
                Text("CONTROL ROOM").label(13, tracking: 0.12)
                Spacer()
                Text(BoardView.dateLine(model.now)).font(Theme.font(13, .medium))
            }
            .padding(.horizontal, 32)
            .frame(height: 56)
            .background(Theme.paper)
            .bottomRule()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("END OF DAY").label(12, tracking: 0.12)
                        Text(summary.headline)
                            .font(Theme.font(40, .black))
                            .tracking(-1.2)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    BlackButton(title: "CLOSE THE DAY") {
                        model.closeTheDay()
                        close()
                    }
                    .accessibilityHint("Anything still waiting goes quiet until 9am, Done clears, and the companion sleeps until 9.")
                }

                HStack(alignment: .top, spacing: 24) {
                    doneBlock(summary)
                    waitingBlock(summary)
                    putOffBlock(summary)
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 32)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(PaperGrid())
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 1100, minHeight: 640)
    }

    // MARK: Blocks

    private func doneBlock(_ summary: EndOfDay) -> some View {
        let shown = allDone ? summary.done : Array(summary.done.prefix(Self.doneShown))
        return EndBlock(number: summary.done.count, label: "DONE", colour: Theme.mint) {
            ForEach(shown) { t in
                HStack(spacing: 12) {
                    Text(t.title).font(Theme.font(13, .medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(t.tool.displayName.replacingOccurrences(of: " Code", with: ""))
                        .font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlay(alignment: .bottom) { Color(hex: 0xE8E3D8).frame(height: 1) }
            }
            if summary.done.count > Self.doneShown {
                Button { allDone.toggle() } label: {
                    Text(allDone ? "show fewer" : "and \(EndOfDay.words(summary.done.count - Self.doneShown)) more")
                        .font(Theme.font(13, .bold)).underline()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            if summary.done.isEmpty { empty("Nothing finished today.") }
        } footer: { EmptyView() }
    }

    private func waitingBlock(_ summary: EndOfDay) -> some View {
        EndBlock(number: summary.waiting.count, label: "STILL WAITING", colour: Theme.pink) {
            ForEach(summary.waiting) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(context(t)).font(Theme.font(11, .bold))
                    Text(t.title).font(Theme.font(15, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SmallButton(title: "OPEN", dark: true) { model.open(t) }
                        if t.state == .needsYou {
                            SmallButton(title: "TOMORROW 9AM") { model.apply(.tomorrow, to: t) }
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .bottomRule()
            }
            if summary.waiting.isEmpty { empty("Nothing still wants you.") }
        } footer: {
            note("Anything left here goes quiet overnight and wakes the companion at 9am.")
        }
    }

    private func putOffBlock(_ summary: EndOfDay) -> some View {
        EndBlock(number: summary.putOff.count, label: "PUT OFF AND NEVER CAME BACK", colour: Theme.coral) {
            ForEach(summary.putOff) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(Theme.font(15, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(EndOfDay.neverStarted(t) && t.laterCount < 3 ? "never handed off" : EndOfDay.reason(t, now: model.now))
                        .font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
                    HStack(spacing: 8) {
                        if EndOfDay.neverStarted(t) {
                            SmallButton(title: "HAND OFF", dark: true) { model.openHandOff(t.brief ?? t.title, replacing: t.id) }
                        } else {
                            SmallButton(title: "KEEP", dark: true) { model.apply(.keep, to: t) }
                        }
                        SmallButton(title: "DROP") { model.drop(t) }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .bottomRule()
            }
            if summary.putOff.isEmpty { empty("Nothing's been put off.") }
        } footer: {
            note("Dropped tickets are gone, and unticked Agent in Notion if they came from there. Kept ones get one more day, then they come back here.")
        }
    }

    // MARK: Pieces

    private func context(_ t: Ticket) -> String {
        [t.tool.displayName, t.contextName, Wait(since: t.stateSince, now: model.now).phrase]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
    }
}

/// One of the three cards: a big number on its colour, a list, and a note at the bottom.
struct EndBlock<Rows: View, Footer: View>: View {
    let number: Int
    let label: String
    let colour: Color
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("\(number)").font(Theme.font(72, .black)).tracking(-2.9)
                Spacer()
                Text(label).label(12, tracking: 0.12).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(colour)
            .bottomRule()
            .accessibilityElement(children: .combine)
            if Snapshot.rendering {
                VStack(spacing: 0) { rows() }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 0) { rows() }
                }
            }
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.white)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .hardShadow(6)
    }
}

/// The 32pt buttons inside End of day rows: OPEN (black), TOMORROW 9AM, KEEP, DROP.
struct SmallButton: View {
    let title: String
    var dark = false
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(11, tracking: dark ? 0.08 : 0.06, weight: dark ? .black : .bold)
                .foregroundStyle(dark ? Theme.white : Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(dark ? Theme.ink : Theme.white)
                .overlay(Rectangle().strokeBorder(focused ? Theme.yellow : Theme.ink, lineWidth: focused ? 3 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
    }
}

/// A black button with a 3px shadow, like CLOSE THE DAY.
struct BlackButton: View {
    let title: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(13, tracking: 0.08)
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 20)
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
    }
}
