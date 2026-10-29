import AppKit
import ControlRoomCore
import SwiftUI

/// Colours and type from SPEC section 7. Colour means state, never tool.
enum Theme {
    static let paper = Color(hex: 0xF6F3EC)
    static let ink = Color(hex: 0x111111)
    static let pink = Color(hex: 0xF8A9C9)
    static let coral = Color(hex: 0xE8604F)
    static let sky = Color(hex: 0xA9C4F2)
    static let mint = Color(hex: 0xBFE3C4)
    static let yellow = Color(hex: 0xF8C94A)
    static let lavender = Color(hex: 0xCFC9EC)
    static let bodyGrey = Color(hex: 0x4A4640)
    static let white = Color.white

    static func color(_ signal: Signal) -> Color {
        switch signal {
        case .pink: pink
        case .coral: coral
        case .sky: sky
        case .mint: mint
        case .paper: paper
        }
    }

    /// Archivo when it's available, otherwise the system font at the same weight.
    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        hasArchivo ? .custom("Archivo", size: size).weight(weight) : .system(size: size, weight: weight)
    }

    static let hasArchivo = NSFontManager.shared.availableFontFamilies.contains("Archivo")

    /// Loads Archivo from the app bundle if it was packaged with it.
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Solid ink shadow, no blur (SPEC section 7).
    func hardShadow(_ offset: CGFloat) -> some View {
        background(Theme.ink.offset(x: offset, y: offset))
    }

    /// Black 900 caps label with +12% tracking at labels, +8% on buttons.
    func label(_ size: CGFloat = 12, tracking: CGFloat = 0.1, weight: Font.Weight = .black) -> some View {
        font(Theme.font(size, weight)).tracking(size * tracking)
    }
}
