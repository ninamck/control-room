import AppKit
import ControlRoomCore
import SwiftUI

/// A landed scheduled result, matching the cards in reference/07-scheduled.html.
struct LandedCard: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(ticket.schedule.map { PanelView.clock.string(from: $0.expected) } ?? "—")
                    .font(Theme.font(22, .black))
                Text("RAN").label(10)
            }
            .frame(width: 92)
            .frame(maxHeight: .infinity)
            .background(Theme.pink)
            .overlay(alignment: .trailing) { Theme.ink.frame(width: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ran at \(ticket.schedule.map { PanelView.clock.string(from: $0.expected) } ?? "unknown time")")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ToolBadge(tool: ticket.tool)
                    Text(context).font(Theme.font(12, .bold))
                }
                Text(ticket.title).font(Theme.font(22, .bold)).tracking(-0.2)
                Text(ticket.lastMessage.isEmpty
                     ? "\(ticket.tool.displayName) can't tell Control Room it finished, so this appears at the expected time. Mark it read once you've looked."
                     : ticket.lastMessage)
                    .font(Theme.font(13.5, .regular))
                    .foregroundStyle(Theme.bodyGrey)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                if ticket.lastMessage.isEmpty {
                    CardButton(title: "OPEN", fill: Theme.ink, text: Theme.white, strong: true) { model.open(ticket) }
                    CardButton(title: "READ IT", fill: Theme.mint, strong: true) { model.markRead(ticket) }
                } else {
                    CardButton(title: "READ", fill: Theme.ink, text: Theme.white, strong: true) { model.read(ticket) }
                    CardButton(title: "✓ DONE", fill: Theme.mint, strong: true) { model.markRead(ticket) }
                }
                CardButton(title: "DIDN'T RUN") { model.markMissed(ticket) }
            }
            .frame(width: 128)
            .overlay(alignment: .leading) { Theme.ink.frame(width: 1) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.white)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .hardShadow(6)
    }

    /// "Grok · scheduled · weekdays · no feed"
    private var context: String {
        [ticket.tool.displayName, "scheduled", ticket.schedule?.cadence ?? "", ticket.lastMessage.isEmpty ? "no feed" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// ON A SCHEDULE: the watch list. Read only; schedules are edited in the tool.
struct WatchSection: View {
    @ObservedObject var model: AppModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ON A SCHEDULE").label(12, tracking: 0.12).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Edit schedules in the tool. This only watches.")
                    .font(Theme.font(12, .regular)).foregroundStyle(Theme.bodyGrey)
                Button { adding.toggle() } label: {
                    Text(adding ? "close" : "+ watch one").font(Theme.font(12, .bold)).underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            VStack(spacing: 0) {
                if adding { WatchForm(model: model) { adding = false } }
                if model.watched.isEmpty && !adding {
                    Text("Nothing on a schedule yet. Add the ones you run in Claude or Grok so their results land here.")
                        .font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                ForEach(model.watched.sorted { $0.time < $1.time }) { task in
                    WatchRow(task: task, model: model)
                }
            }
            .background(Theme.white)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        }
    }
}

struct WatchRow: View {
    let task: WatchedTask
    @ObservedObject var model: AppModel

    var body: some View {
        let status = WatchList.status(task, tickets: model.tickets, now: model.now)
        HStack(spacing: 12) {
            Text(task.time).font(Theme.font(13, .black)).frame(width: 78, alignment: .leading)
            HStack(spacing: 8) {
                ToolBadge(tool: task.tool, size: 16)
                Text(task.name).font(Theme.font(13, .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(task.cadence.label).font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
                .frame(width: 120, alignment: .leading)
            pill(status).frame(width: 100, alignment: .leading)
            Text(WatchList.lastResult(task)).font(Theme.font(13, .regular)).foregroundStyle(Theme.bodyGrey)
                .frame(width: 110, alignment: .trailing)
            Button { model.stopWatching(task.id) } label: { Text("×").font(Theme.font(15, .bold)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop watching \(task.name)")
                .help("Stop watching")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .bottomRule()
        .accessibilityElement(children: .contain)
    }

    private func pill(_ status: WatchList.Status) -> some View {
        let (text, colour): (String, Color) = switch status {
        case .soon(let minutes): ("IN \(minutes) MIN", Theme.sky)
        case .later(let when): (when, Theme.paper)
        case .unread: ("UNREAD", Theme.pink)
        case .missed: ("MISSED", Theme.coral)
        }
        return Text(text).label(11, tracking: 0.06)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(colour)
    }
}

/// Adding a schedule to watch: name, tool, time, how often, and where its results show up.
struct WatchForm: View {
    @ObservedObject var model: AppModel
    let done: () -> Void
    @State private var name = ""
    @State private var tool: Tool = .claudeAI
    @State private var time = "09:00"
    @State private var kind: WatchedTask.Cadence.Kind = .weekdays
    @State private var weekday = 2
    @State private var link = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                field("Name", text: $name, prompt: "Morning brief").frame(maxWidth: .infinity)
                field("Time", text: $time, prompt: "09:00").frame(width: 80)
                Picker("Tool", selection: $tool) {
                    Text("Claude").tag(Tool.claudeAI)
                    Text("Grok").tag(Tool.grok)
                }
                .frame(width: 150)
                Picker("How often", selection: $kind) {
                    Text("Daily").tag(WatchedTask.Cadence.Kind.daily)
                    Text("Weekdays").tag(WatchedTask.Cadence.Kind.weekdays)
                    Text("Weekly").tag(WatchedTask.Cadence.Kind.weekly)
                    Text("Fortnightly").tag(WatchedTask.Cadence.Kind.fortnightly)
                }
                .frame(width: 200)
                if kind == .weekly || kind == .fortnightly {
                    Picker("on", selection: $weekday) {
                        ForEach(2...6, id: \.self) { d in Text(Calendar(identifier: .gregorian).shortWeekdaySymbols[d - 1]).tag(d) }
                    }
                    .frame(width: 110)
                }
            }
            HStack(spacing: 10) {
                field("Where results show up (optional)", text: $link, prompt: "https://claude.ai/project/…").frame(maxWidth: .infinity)
                ShadowButton(title: "WATCH IT", fill: Theme.yellow, action: add)
            }
            if let problem {
                Text(problem).font(Theme.font(12, .regular)).padding(8).background(Theme.coral)
            }
        }
        .font(Theme.font(13, .regular))
        .padding(16)
        .background(Theme.paper)
        .bottomRule()
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        TextField(label, text: text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.white)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .accessibilityLabel(label)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { problem = "Give it a name."; return }
        let task = WatchedTask(name: trimmed, tool: tool, time: time.trimmingCharacters(in: .whitespaces),
                               cadence: .init(kind: kind, weekday: kind == .weekly || kind == .fortnightly ? weekday : nil,
                                              anchor: kind == .fortnightly ? Date() : nil),
                               link: link.isEmpty ? nil : link)
        guard task.nextRun(after: Date()) != nil else { problem = "Time should look like 09:00."; return }
        model.watch(task)
        done()
    }
}

/// The reader pane: a scheduled result's full text in the app's type, no chat chrome. One action: Done.
struct ReaderView: View {
    let ticket: Ticket
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ToolBadge(tool: ticket.tool)
                    Text([ticket.tool.displayName, "scheduled", ticket.schedule.map { "ran \(PanelView.clock.string(from: $0.expected))" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.font(12, .bold))
                }
                Text(ticket.title).font(Theme.font(32, .black)).tracking(-0.8)
            }
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 20)
            .bottomRule()
            ScrollView {
                Text(ticket.lastMessage)
                    .font(Theme.font(15, .regular))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 40).padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                BlackButton(title: "✓ DONE") {
                    model.markRead(ticket)
                    close()
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 18)
            .overlay(alignment: .top) { Theme.ink.frame(height: 1) }
        }
        .background(Theme.white)
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 640, minHeight: 480)
    }
}

/// The reader pane in its own window.
@MainActor
final class ReaderWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(_ ticket: Ticket) {
        window?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = ticket.title
        window.contentView = NSHostingView(rootView: ReaderView(ticket: ticket, model: model) { [weak window] in window?.close() })
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        WindowPolicy.update(closing: notification.object as? NSWindow)
    }
}
