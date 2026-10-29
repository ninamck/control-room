import AppKit
import SwiftUI

/// Hand off as its own window, reached from the panel, the board and End of day.
@MainActor
final class HandOffWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let form = HandOffForm()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(brief: String?, replacing: String? = nil) {
        if let brief { form.brief = brief }
        form.replaces = replacing
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Hand off"
            window.contentView = NSHostingView(rootView: HandOffView(model: model, form: form) { [weak self] in self?.close() })
            window.contentMinSize = NSSize(width: 1000, height: 640)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("ControlRoomHandOff")
            if !window.setFrameUsingName("ControlRoomHandOff") { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.loadReady()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        WindowPolicy.update(closing: window)
    }
}

/// Control Room is in the Dock only while one of its windows is open.
@MainActor
enum WindowPolicy {
    static func update(closing: NSWindow?) {
        let anyOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
        NSApp.setActivationPolicy(anyOpen ? .regular : .accessory)
    }
}

/// End of day as its own window: opened from the board, and by itself once a day at the set time.
@MainActor
final class EndOfDayWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "End of day"
            window.contentView = NSHostingView(rootView: EndOfDayView(model: model) { [weak self] in self?.window?.close() })
            window.contentMinSize = NSSize(width: 1100, height: 640)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("ControlRoomEndOfDay")
            if !window.setFrameUsingName("ControlRoomEndOfDay") { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        WindowPolicy.update(closing: window)
    }
}
