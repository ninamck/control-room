import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Uses the Carbon hot key API, which needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    /// Every shortcut shares one handler, which looks up the pressed one by id.
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        id = UInt32(HotKey.actions.count + 1)
        HotKey.actions[id] = action
        if !HotKey.handlerInstalled {
            HotKey.handlerInstalled = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                DispatchQueue.main.async { HotKey.actions[pressed.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        var carbon: UInt32 = 0
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4352_4D52), id: id)  // "CRMR"
        RegisterEventHotKey(keyCode, carbon, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.actions[id] = nil
    }
}
