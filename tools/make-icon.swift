// Draws the app icon: the companion's asleep face, 8×8 pixels, yellow, crisp at every size.
// Run from the repo:  swift tools/make-icon.swift  → writes Resources/AppIcon.icns
import AppKit

let yellow = NSColor(srgbRed: 0xF8 / 255, green: 0xC9 / 255, blue: 0x4A / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
// Same grid as Face.asleep: eyes and mouth as (x, y, width, height).
let pixels = [(1, 3, 2, 1), (5, 3, 2, 1), (3, 5, 2, 1)]

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.shouldAntialias = false
    NSGraphicsContext.current = context
    let unit = CGFloat(size) / 8
    yellow.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    ink.setFill()
    for (x, y, w, h) in pixels {
        // Bitmaps count up from the bottom; the grid counts down from the top. Round to whole pixels.
        let left = (CGFloat(x) * unit).rounded(), right = (CGFloat(x + w) * unit).rounded()
        let top = (CGFloat(y) * unit).rounded(), bottom = (CGFloat(y + h) * unit).rounded()
        NSRect(x: left, y: CGFloat(size) - bottom, width: right - left, height: bottom - top).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
