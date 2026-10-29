import AppKit
import ControlRoomCore
import SwiftUI

/// Renders the panel and faces with sample tickets to PNGs, to compare against reference/.
/// Run: ControlRoom --snapshot <folder>
@MainActor
enum Snapshot {
    /// True while rendering, so views can skip what the image renderer can't draw.
    static var rendering = false

    static func render(to folder: URL) {
        rendering = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        guard let store = try? TicketStore(fileURL: file) else { return }
        let now = Date()
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        var finished = Ticket(tool: .cursor, source: .automatic, title: "When I click check out it scrolls me to the bottom rather than the top", thread: "edify-web",
                              lastMessage: "Checkout now opens at the top, and so does the **Orders sent** page after placing orders.\n\nThe app was keeping the scroll position from one page to the next.", stateSince: ago(18))
        finished.chatName = "Predictive ordering UI sweep"
        _ = try? store.add(finished)
        _ = try? store.add(Ticket(tool: .claudeAI, source: .automatic, title: "PRD v0.2 ready for review", thread: "Quick Count PRD", stateSince: ago(7)))
        _ = try? store.add(Ticket(tool: .grok, title: "Competitor pricing research", stateSince: ago(31)))
        _ = try? store.add(Ticket(tool: .devin, source: .automatic, title: "PR #412: approve to merge", thread: "transfer-requests", stateSince: ago(2)))
        var busy = Ticket(tool: .cursor, source: .automatic, title: "Does this go across to how the variances are viewed? So all storage areas…", thread: "New AI direction 20260327", state: .working, stateSince: ago(4))
        busy.activity = "Running npm run test:e2e -- basket"
        busy.activityAt = now.addingTimeInterval(-12)
        _ = try? store.add(busy)
        _ = try? store.add(Ticket(tool: .claudeCode, source: .automatic, title: "Mixpanel plan: mapping AI events", thread: "edify-web", state: .working, stateSince: ago(11)))
        _ = try? store.add(Ticket(tool: .grok, title: "Competitor pricing research", state: .working, stateSince: ago(2)))
        for _ in 0..<4 { _ = try? store.add(Ticket(tool: .cursor, title: "d", state: .done)) }

        let scratch = UserDefaults(suiteName: "local.nina.controlroom.snapshot")!
        scratch.removePersistentDomain(forName: "local.nina.controlroom.snapshot")
        let model = AppModel(store: store, defaults: scratch)
        model.reload()
        model.panelOpen = true
        model.showWorking = true
        save(PanelView(model: model).padding(.trailing, 8).padding(.bottom, 8).padding(40).background(Theme.lavender),
             to: folder.appendingPathComponent("panel.png"))

        model.panelOpen = false
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let longAgo = now.addingTimeInterval(-40 * 24 * 3600)
        model.watch(WatchedTask(name: "QSR news scan", tool: .grok, time: f.string(from: ago(90)), cadence: .init(kind: .daily),
                                link: "https://grok.com", created: longAgo))
        model.watch(WatchedTask(name: "Morning brief", tool: .claudeAI, time: f.string(from: now.addingTimeInterval(8 * 60)), cadence: .init(kind: .daily), created: longAgo))
        model.watch(WatchedTask(name: "All-hands numbers pull", tool: .claudeAI, time: "08:00", cadence: .init(kind: .weekly, weekday: 2), created: now))
        save(BoardView(model: model, scrolls: false).frame(width: 1280, height: 2300), to: folder.appendingPathComponent("board.png"))

        let form = HandOffForm()
        form.brief = "Draft the corrective actions table for the Checklists PRD: one row per failed check type, who gets alerted, what the GM has to do, and when it escalates. Use the audits section as the source."
        form.folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude-code/control-room").path
        save(HandOffView(model: model, form: form, close: {}).frame(width: 1280, height: 800), to: folder.appendingPathComponent("handoff.png"))

        var putOff = Ticket(tool: .cursor, title: "Transfer request empty states", stateSince: ago(300))
        putOff.laterCount = 3
        _ = try? store.add(putOff)
        _ = try? store.add(Ticket(tool: .grok, title: "Summarise last three Pret calls for Alistair", state: .parked, stateSince: ago(3000)))
        model.reload()
        save(EndOfDayView(model: model, close: {}).frame(width: 1280, height: 800), to: folder.appendingPathComponent("endofday.png"))
        model.quiet(minutes: 25)
        model.panelOpen = true
        save(PanelView(model: model).padding(.trailing, 8).padding(.bottom, 8).padding(40).background(Theme.lavender),
             to: folder.appendingPathComponent("quiet.png"))
        model.wake()

        let faces = HStack(spacing: 20) {
            ForEach(Face.allCases, id: \.self) { face in
                VStack(spacing: 8) {
                    FaceView(face: face, pixel: 5).frame(width: 64, height: 64).background(Theme.ink)
                    Text(face.rawValue).font(Theme.font(11, .bold))
                }
            }
        }
        save(faces.padding(32).background(Theme.lavender), to: folder.appendingPathComponent("faces.png"))
        try? FileManager.default.removeItem(at: file)
    }

    private static func save(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view.foregroundStyle(Theme.ink))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
