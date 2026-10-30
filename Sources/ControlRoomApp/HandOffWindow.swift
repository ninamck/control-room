import AppKit
import SwiftUI

/// Control Room is in the Dock only while one of its windows is open.
@MainActor
enum WindowPolicy {
    static func update(closing: NSWindow?) {
        let anyOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
        NSApp.setActivationPolicy(anyOpen ? .regular : .accessory)
    }
}
