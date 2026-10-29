import AppKit
import SwiftUI

/// The companion's four faces (SPEC section 6), drawn on an 8 by 8 grid
/// exactly as in reference/02-notch-panel.html.
enum Face: String, CaseIterable {
    case asleep, needsYou, expanded, overdue

    /// Black pixels as (x, y, width, height) on the 8 by 8 grid.
    var pixels: [(Int, Int, Int, Int)] {
        switch self {
        case .asleep: [(1, 3, 2, 1), (5, 3, 2, 1), (3, 5, 2, 1)]
        case .needsYou: [(1, 1, 2, 1), (5, 1, 2, 1), (2, 3, 1, 1), (5, 3, 1, 1), (3, 6, 2, 1)]
        case .expanded: [(2, 2, 1, 1), (5, 2, 1, 1), (3, 5, 2, 2)]
        case .overdue: [(1, 2, 2, 1), (5, 2, 2, 1), (2, 3, 1, 1), (5, 3, 1, 1), (2, 6, 4, 1)]
        }
    }

    var fill: Color { self == .overdue ? Theme.coral : Theme.yellow }

    var label: String {
        switch self {
        case .asleep: "Asleep, nothing waiting"
        case .needsYou: "Something is waiting on you"
        case .expanded: "Panel open"
        case .overdue: "Something has waited over 15 minutes"
        }
    }

    /// For the menu bar fallback.
    func image(pixel: CGFloat) -> NSImage {
        let size = pixel * 8
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            NSColor(self.fill).setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            NSColor(Theme.ink).setFill()
            for (x, y, w, h) in self.pixels {
                NSRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: CGFloat(w) * pixel, height: CGFloat(h) * pixel).fill()
            }
            return true
        }
        image.accessibilityDescription = label
        return image
    }
}

/// The face at a whole number of points per grid square, so edges stay crisp.
struct FaceView: View {
    let face: Face
    let pixel: CGFloat

    var body: some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: pixel * 8, height: pixel * 8)), with: .color(face.fill))
            for (x, y, w, h) in face.pixels {
                let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: CGFloat(w) * pixel, height: CGFloat(h) * pixel)
                context.fill(Path(rect), with: .color(Theme.ink))
            }
        }
        .frame(width: pixel * 8, height: pixel * 8)
        .accessibilityElement()
        .accessibilityLabel(face.label)
    }
}
