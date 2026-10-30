// Draws the app icon: the companion's neutral face (companion/faces/01-neutral.svg), full bleed, at every size.
// Run from the repo:  swift tools/make-icon.swift  → rewrites everything in icon/
import AppKit

let yellow = NSColor(srgbRed: 0xF8 / 255, green: 0xC9 / 255, blue: 0x4A / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let unit = CGFloat(size) / 100
    // The face's 100 by 100 square counts down from the top; bitmaps count up from the bottom.
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * unit, y: CGFloat(size) - (y + h) * unit, width: w * unit, height: h * unit)
    }
    yellow.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    ink.setFill()
    for cx in [30.0, 70.0] { NSBezierPath(ovalIn: rect(cx - 5.5, 32.5, 11, 11)).fill() }
    // Under 32 pixels the mouth would fall below a pixel: keep it at least 1 pixel tall (SPEC-companion).
    var mouth = rect(30, 64, 40, 4)
    if mouth.height < 1 { mouth = NSRect(x: mouth.minX, y: mouth.midY - 0.5, width: mouth.width, height: 1) }
    mouth.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let icon = URL(fileURLWithPath: "icon")
for old in ["png", "tauri", "AppIcon.appiconset", "companion-asleep.svg", "companion-neutral.svg", "ControlRoom.icns"] {
    try? fm.removeItem(at: icon.appendingPathComponent(old))
}
try fm.copyItem(at: URL(fileURLWithPath: "companion/faces/01-neutral.svg"), to: icon.appendingPathComponent("companion-neutral.svg"))

let pngs = icon.appendingPathComponent("png")
try fm.createDirectory(at: pngs, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try png(size: size).write(to: pngs.appendingPathComponent("companion-neutral-\(size).png"))
}

let set = icon.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: set, withIntermediateDirectories: true)
var images: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(size: base * scale).write(to: set.appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(base)x\#(base)"}"#)
    }
}
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// iconutil wants a folder named .iconset holding just the images.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.copyItem(at: set, to: iconset)
try? fm.removeItem(at: iconset.appendingPathComponent("Contents.json"))
func iconutil(to out: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try task.run()
    task.waitUntilExit()
}
try iconutil(to: icon.appendingPathComponent("ControlRoom.icns"))

let tauri = icon.appendingPathComponent("tauri")
try fm.createDirectory(at: tauri, withIntermediateDirectories: true)
for (name, size) in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256), ("icon.png", 512)] {
    try png(size: size).write(to: tauri.appendingPathComponent(name))
}
try iconutil(to: tauri.appendingPathComponent("icon.icns"))
print("Wrote icon/")
