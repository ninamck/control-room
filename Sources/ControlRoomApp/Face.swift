import AppKit
import SwiftUI

/// The companion's faces (SPEC section 6, companion/SPEC-companion.md): a square with round eyes and a flat mouth,
/// drawn from the geometry in companion/faces/faces.json on a 100 by 100 square.
enum Face: String, CaseIterable {
    case asleep, alert, talking, worried, quiet, blocked, pleased
    /// Shipped but not used in v1.
    case neutral, working, inverted

    /// One shape on the 100 by 100 square. `angle` turns a bar about the given centre, in degrees.
    enum Shape {
        case eye(x: CGFloat, y: CGFloat, r: CGFloat)
        case bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat = 0, about: CGPoint = .zero)
    }

    var shapes: [Shape] {
        let eyes: [Shape] = [.eye(x: 30, y: 38, r: 5.5), .eye(x: 70, y: 38, r: 5.5)]
        let closed: [Shape] = [.bar(x: 22, y: 36, w: 16, h: 4), .bar(x: 62, y: 36, w: 16, h: 4)]
        let wideMouth = Shape.bar(x: 30, y: 64, w: 40, h: 4)
        let smallMouth = Shape.bar(x: 38, y: 64, w: 24, h: 4)
        switch self {
        case .neutral, .inverted: return eyes + [wideMouth]
        case .asleep: return closed + [smallMouth]
        case .alert: return [.eye(x: 30, y: 36, r: 7), .eye(x: 70, y: 36, r: 7), smallMouth]
        case .talking: return eyes + [.bar(x: 40, y: 60, w: 20, h: 12)]
        case .worried:
            return [.eye(x: 30, y: 40, r: 5.5), .eye(x: 70, y: 40, r: 5.5),
                    .bar(x: 20, y: 22, w: 18, h: 4, angle: 14, about: CGPoint(x: 29, y: 24)),
                    .bar(x: 62, y: 22, w: 18, h: 4, angle: -14, about: CGPoint(x: 71, y: 24)),
                    .bar(x: 42, y: 66, w: 16, h: 4)]
        case .pleased:
            return eyes + [.bar(x: 26, y: 62, w: 4, h: 8), .bar(x: 30, y: 66, w: 40, h: 4), .bar(x: 70, y: 62, w: 4, h: 8)]
        case .working: return [.eye(x: 34, y: 38, r: 5.5), .eye(x: 74, y: 38, r: 5.5), wideMouth]
        case .quiet: return closed + [.bar(x: 74, y: 60, w: 4, h: 12), .bar(x: 82, y: 60, w: 4, h: 12), smallMouth]
        case .blocked:
            return [30, 70].flatMap { (x: CGFloat) -> [Shape] in
                [45, -45].map { .bar(x: x - 7, y: 36, w: 14, h: 4, angle: $0, about: CGPoint(x: x, y: 38)) }
            } + [wideMouth]
        }
    }

    var ground: Color {
        switch self {
        case .worried, .blocked: Theme.coral
        case .pleased: Theme.mint
        case .inverted: Theme.ink
        default: Theme.yellow
        }
    }

    var features: Color { self == .inverted ? Theme.yellow : Theme.ink }

    var label: String {
        switch self {
        case .asleep: "Asleep, nothing waiting"
        case .alert: "Something is waiting on you"
        case .talking: "Panel open"
        case .worried: "Something has waited over 15 minutes"
        case .quiet: "Quiet"
        case .blocked: "Something is blocked"
        case .pleased: "All clear"
        case .neutral: "Neutral"
        case .working: "Working"
        case .inverted: "Asleep, nothing waiting"
        }
    }

    /// Ground and features at `size` points, in a top-down coordinate space.
    func paths(size: CGFloat) -> (ground: Path, features: Path) {
        let unit = size / 100
        // Under 32 points the 4-unit bars would fall below a pixel and vanish: keep them at least 1 point thick.
        let minimum: CGFloat = size < 32 ? 1 / unit : 0
        var features = Path()
        for shape in shapes {
            switch shape {
            case let .eye(x, y, r):
                features.addEllipse(in: CGRect(x: (x - r) * unit, y: (y - r) * unit, width: r * 2 * unit, height: r * 2 * unit))
            case let .bar(x, y, w, h, angle, about):
                // Thin side grows about its centre so the bar stays where it was drawn.
                let width = max(w, w < h ? minimum : 0), height = max(h, h <= w ? minimum : 0)
                let rect = CGRect(x: x - (width - w) / 2, y: y - (height - h) / 2, width: width, height: height)
                let turn = CGAffineTransform(translationX: about.x, y: about.y)
                    .rotated(by: angle * .pi / 180)
                    .translatedBy(x: -about.x, y: -about.y)
                features.addPath(Path(rect).applying(angle == 0 ? .identity : turn).applying(CGAffineTransform(scaleX: unit, y: unit)))
            }
        }
        return (Path(CGRect(x: 0, y: 0, width: size, height: size)), features)
    }

    /// For the menu bar fallback.
    func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let (ground, features) = self.paths(size: size)
            context.setFillColor(NSColor(self.ground).cgColor)
            context.addPath(ground.cgPath)
            context.fillPath()
            context.setFillColor(NSColor(self.features).cgColor)
            context.addPath(features.cgPath)
            context.fillPath()
            return true
        }
        image.accessibilityDescription = label
        return image
    }
}

struct FaceView: View {
    let face: Face
    let size: CGFloat

    var body: some View {
        Canvas { context, _ in
            let (ground, features) = face.paths(size: size)
            context.fill(ground, with: .color(face.ground))
            context.fill(features, with: .color(face.features))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(face.label)
    }
}
