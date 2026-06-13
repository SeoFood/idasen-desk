import Carbon.HIToolbox
import Foundation

@MainActor
public final class ShortcutManager: @unchecked Sendable {
    public var onAction: ((ShortcutAction) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var refs: [String: EventHotKeyRef] = [:]
    private var actionsByHotKeyID: [UInt32: ShortcutAction] = [:]

    public init() {}

    public func apply(bindings: [ShortcutBinding]) {
        unregisterAll()
        installHandlerIfNeeded()

        for (index, binding) in bindings.filter(\.isEnabled).enumerated() {
            register(binding: binding, hotKeyID: UInt32(index + 1))
        }
    }

    public func unregisterAll() {
        let refsToRemove = Array(refs.values)
        refs.removeAll()
        actionsByHotKeyID.removeAll()

        for ref in refsToRemove {
            UnregisterEventHotKey(ref)
        }
    }

    private func register(binding: ShortcutBinding, hotKeyID: UInt32) {
        let eventHotKeyID = EventHotKeyID(signature: fourCharCode("IDSK"), id: hotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers.carbonFlags,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return
        }

        refs[binding.id] = hotKeyRef
        actionsByHotKeyID[hotKeyID] = binding.action
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            shortcutEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }

    fileprivate func handleHotKey(id: UInt32) {
        let action = actionsByHotKeyID[id]
        if let action {
            onAction?(action)
        }
    }
}

private let shortcutEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return noErr
    }

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

    guard status == noErr else {
        return status
    }

    let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

private func fourCharCode(_ string: StaticString) -> OSType {
    var result: UInt32 = 0
    for byte in string.utf8Start.withMemoryRebound(to: UInt8.self, capacity: string.utf8CodeUnitCount, { buffer in
        UnsafeBufferPointer(start: buffer, count: string.utf8CodeUnitCount)
    }) {
        result = (result << 8) + UInt32(byte)
    }
    return OSType(result)
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if contains(.option) {
            flags |= UInt32(optionKey)
        }
        if contains(.control) {
            flags |= UInt32(controlKey)
        }
        if contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }
}
