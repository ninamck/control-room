import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Puts the companion in the notch of the MacBook screen, and in the menu bar
/// when there is no notch or Nina is working on another screen (DECISIONS.md).
@MainActor
final class Companion: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var notch: (window: CompanionPanel, host: CompanionHostingView, screen: NSScreen, size: NotchSize)?
    private var statusItem: NSStatusItem?
    private var menuPanel: (window: CompanionPanel, host: CompanionHostingView)?
    /// Opened by a click or the shortcut: stays open until Nina clicks elsewhere or presses Escape.
    private var pinned = false
    /// Whether the notch window is showing the panel rather than just the face.
    private var notchExpanded = false
    /// Drives the grow-out-of-the-notch animation.
    private let growth = Growth()
    /// Swaps back to the face once the shrink animation has finished.
    private var pendingShrink: DispatchWorkItem?
    private var watchers: Set<AnyCancellable> = []
    private var hotKeys: [HotKey] = []

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        placeCompanion()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.placeCompanion() }
            .store(in: &watchers)
        // Which screen Nina is on has no notification, so look every couple of seconds.
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &watchers)
        model.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.layout() } }
            .store(in: &watchers)
        model.$companionOn
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.showOrHide() } }
            .store(in: &watchers)
        hotKeys = [
            // Control-Option-C opens the panel from the keyboard.
            HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: [.control, .option]) { [weak self] in self?.toggleFromKeyboard() },
            // Control-Option-N switches the companion on and off.
            HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.control, .option]) { [weak self] in self?.model.companionOn.toggle() },
        ]
    }

    // MARK: Placement

    private var notchScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    private func placeCompanion() {
        collapse()
        notch?.window.orderOut(nil)
        notch = nil
        if let screen = notchScreen {
            let size = NotchSize(screen: screen)
            let host = CompanionHostingView(rootView: notchContent(size, expanded: false))
            let window = CompanionPanel(content: host)
            window.delegate = self
            notch = (window, host, screen, size)
            layout()
            if model.companionOn { window.orderFrontRegardless() }
        }
        updateStatusItem()
    }

    private func notchContent(_ size: NotchSize, expanded: Bool) -> AnyView {
        AnyView(NotchView(model: model, growth: growth, size: size, expanded: expanded, openFromClick: { [weak self] in self?.open(pinned: true) }))
    }

    /// Swaps the notch between face and panel and resizes in the same pass, so it never shows a half-way frame.
    private func setNotchExpanded(_ expanded: Bool) {
        guard let notch, expanded != notchExpanded else { return }
        notchExpanded = expanded
        notch.host.rootView = notchContent(notch.size, expanded: expanded)
    }

    /// Switched off: everything goes away, though tickets keep updating behind it. Back on: as it was.
    private func showOrHide() {
        if model.companionOn {
            notch?.window.orderFrontRegardless()
            layout()
        } else {
            collapse()
            notch?.window.orderOut(nil)
        }
        updateStatusItem()
    }

    /// Menu bar face when there's no notch, or when the notch isn't on the screen Nina is using.
    private func updateStatusItem() {
        let wanted = model.companionOn && (notch == nil || NSScreen.main != notch?.screen)
        if wanted && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            item.button?.setAccessibilityLabel("Control Room")
            statusItem = item
        } else if !wanted, let item = statusItem, menuPanel == nil {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        statusItem?.button?.image = model.face.image(size: 16)
    }

    // MARK: Open and close

    private var pointerIsInside: Bool {
        let p = NSEvent.mouseLocation
        return [notch?.window, menuPanel?.window].contains { $0?.isVisible == true && $0!.frame.contains(p) }
    }

    private func open(pinned: Bool) {
        self.pinned = self.pinned || pinned
        if !model.panelOpen { model.panelOpen = true }
        if menuPanel == nil {
            pendingShrink?.cancel()
            if !notchExpanded { growth.grown = false }
            setNotchExpanded(true)
            resize()
            grow(true)
        } else {
            resize()
        }
        if pinned { (menuPanel?.window ?? notch?.window)?.makeKey() }
    }

    func collapse() {
        pinned = false
        if model.panelOpen { model.panelOpen = false }
        if notchExpanded {
            // Shrink back into the notch, then swap to the face.
            grow(false)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.setNotchExpanded(false)
                self.resize()
            }
            pendingShrink?.cancel()
            pendingShrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Growth.shrinkTime), execute: work)
        }
        if let panel = menuPanel {
            panel.window.orderOut(nil)
            menuPanel = nil
        }
        resize()
        updateStatusItem()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Animates the panel out of (or back into) the notch. Instant when Reduce Motion is on.
    private func grow(_ grown: Bool) {
        guard growth.grown != grown else { return }
        if reduceMotion {
            growth.grown = grown
            return
        }
        // Let the window take its full size first, then animate on the next pass.
        DispatchQueue.main.async { [growth] in
            withAnimation(grown ? Growth.growCurve : Growth.shrinkCurve) { growth.grown = grown }
        }
    }

    @objc private func statusItemClicked() {
        if menuPanel != nil { collapse(); return }
        let host = CompanionHostingView(rootView: AnyView(PanelView(model: model).padding(.trailing, 8).padding(.bottom, 8)))
        let window = CompanionPanel(content: host)
        window.delegate = self
        menuPanel = (window, host)
        open(pinned: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func toggleFromKeyboard() {
        // Switched off, the shortcut opens the board instead, where the switch is.
        guard model.companionOn else { model.openBoard(); return }
        if model.panelOpen { collapse(); return }
        if notch != nil && NSScreen.main == notch?.screen {
            open(pinned: true)
        } else {
            statusItemClicked()
        }
    }

    // A pinned panel closes when Nina clicks somewhere else.
    func windowDidResignKey(_ notification: Notification) {
        if pinned && !pointerIsInside { collapse() }
    }


    // MARK: Sizing

    /// After tickets change: SwiftUI redraws on its next pass, so resize then.
    private func layout() {
        DispatchQueue.main.async { [weak self] in self?.resize() }
    }

    private func resize() {
        if let notch {
            let frame = notch.screen.frame
            let size: NSSize
            if notchExpanded {
                size = notch.host.fittingSize
            } else {
                size = NSSize(width: notch.size.collapsedWidth, height: notch.size.height)
            }
            // The panel is centred under the notch; its 8pt shadow hangs off the right.
            notch.window.setFrame(NSRect(x: frame.midX - (size.width - (notchExpanded ? 8 : 0)) / 2,
                                         y: frame.maxY - size.height,
                                         width: size.width, height: size.height), display: true)
        }
        if let panel = menuPanel, let button = statusItem?.button, let buttonWindow = button.window {
            let size = panel.host.fittingSize
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen?.visibleFrame ?? .zero
            let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            panel.window.setFrame(NSRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height), display: true)
        }
        statusItem?.button?.image = model.face.image(size: 16)
    }
}

/// Measurements of the physical notch.
struct NotchSize {
    let width: CGFloat
    let height: CGFloat
    /// The face's side, in whole points.
    var face: CGFloat { max(16, floor(height * 0.55)) }
    /// Black space either side of the notch; the face sits in the right one.
    var ear: CGFloat { face + 14 }
    var collapsedWidth: CGFloat { width + ear * 2 }
    /// The notch's lower corners, curved like the screen's own notch (Nina's call: square read as too harsh).
    var cornerRadius: CGFloat { round(height * 0.3) }

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    init(screen: NSScreen) {
        height = screen.safeAreaInsets.top
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
        } else {
            width = 200
        }
    }
}

/// Whether the panel has grown out of the notch yet.
final class Growth: ObservableObject {
    @Published var grown = false
    static let growCurve = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let shrinkCurve = Animation.easeIn(duration: 0.16)
    static let shrinkTime = 0.17
}

/// What lives in the notch window: just the face, or the black strip plus the panel.
struct NotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var growth: Growth
    let size: NotchSize
    let expanded: Bool
    let openFromClick: () -> Void

    var body: some View {
        if expanded {
            VStack(spacing: 0) {
                // Sits behind the hardware notch, so the panel's header starts just below it.
                Theme.ink.frame(width: PanelView.width, height: size.height)
                PanelView(model: model)
            }
            .padding(.trailing, 8).padding(.bottom, 8)
            .fixedSize()
            // Starts as a notch-sized window onto the panel and grows to show all of it.
            .mask(alignment: .topLeading) {
                GeometryReader { full in
                    UnevenRoundedRectangle(bottomLeadingRadius: growth.grown ? 0 : size.cornerRadius,
                                           bottomTrailingRadius: growth.grown ? 0 : size.cornerRadius)
                        .frame(width: growth.grown ? full.size.width : size.collapsedWidth,
                               height: growth.grown ? full.size.height : size.height)
                        .offset(x: growth.grown ? 0 : PanelView.width / 2 - size.collapsedWidth / 2)
                }
            }
        } else {
            Button(action: openFromClick) {
                HStack(spacing: 0) {
                    Theme.ink.frame(width: size.ear + size.width)
                    FaceView(face: model.face, size: size.face)
                        .frame(width: size.ear, height: size.height)
                        .background(Theme.ink)
                }
                .frame(height: size.height)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: size.cornerRadius, bottomTrailingRadius: size.cornerRadius))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("\(model.face.label). Open Control Room.")
        }
    }
}

/// Borderless panel that floats over the menu bar and can take typing without stealing focus from other apps.
final class CompanionPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    // Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        (delegate as? Companion)?.collapse()
    }
}

/// Hosting view whose first click presses the face, even when Control Room isn't the active app.
final class CompanionHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
