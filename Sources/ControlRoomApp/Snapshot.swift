import AppKit
import ControlRoomCore
import SwiftUI

/// Renders the panel and faces with sample tickets to PNGs, to compare against reference/.
/// Run: ControlRoom --snapshot <folder>
@MainActor
enum Snapshot {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        guard let store = try? TicketStore(fileURL: file) else { return }
        let now = Date()
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        _ = try? store.add(Ticket(tool: .cursor, source: .automatic, title: "Recipe variants: modifier group nav", thread: "edify-web", stateSince: ago(18)))
        _ = try? store.add(Ticket(tool: .claudeAI, source: .automatic, title: "PRD v0.2 ready for review", thread: "Quick Count PRD", stateSince: ago(7)))
        _ = try? store.add(Ticket(tool: .grok, title: "Competitor pricing research", stateSince: ago(31)))
        _ = try? store.add(Ticket(tool: .devin, source: .automatic, title: "PR #412: approve to merge", thread: "transfer-requests", stateSince: ago(2)))
        _ = try? store.add(Ticket(tool: .cursor, source: .automatic, title: "Does this go across to how the variances are viewed? So all storage areas…", thread: "New AI direction 20260327", state: .working, stateSince: ago(4)))
        _ = try? store.add(Ticket(tool: .claudeCode, source: .automatic, title: "Mixpanel plan: mapping AI events", thread: "edify-web", state: .working, stateSince: ago(11)))
        _ = try? store.add(Ticket(tool: .grok, title: "Competitor pricing research", state: .working, stateSince: ago(2)))
        for _ in 0..<4 { _ = try? store.add(Ticket(tool: .cursor, title: "d", state: .done)) }

        let model = AppModel(store: store)
        model.reload()
        model.panelOpen = true
        model.showWorking = true
        save(PanelView(model: model).padding(.trailing, 8).padding(.bottom, 8).padding(40).background(Theme.lavender),
             to: folder.appendingPathComponent("panel.png"))

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
