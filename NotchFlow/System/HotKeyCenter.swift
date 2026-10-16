import Carbon.HIToolbox

/// System-wide keyboard shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey`, which still is the standard way to get global
/// shortcuts on macOS and needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        /// How the shortcut is shown in Settings, like "⌃⌥Space".
        let display: String
    }

    static let shared = HotKeyCenter()

    static let toggleNotch = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥Space")
    static let openClipboard = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥V")

    private static let signature: OSType = 0x4E464C57 // "NFLW"

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Registers a shortcut. Returns false if another app already uses it.
    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRefs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            MainActor.assumeIsolated {
                HotKeyCenter.shared.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
    }
}
