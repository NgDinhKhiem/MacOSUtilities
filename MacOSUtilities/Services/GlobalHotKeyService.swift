import AppKit
import Carbon.HIToolbox
import Foundation

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case commandShiftV
    case commandOptionV
    case controlOptionV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandShiftV:
            return "Command-Shift-V"
        case .commandOptionV:
            return "Command-Option-V"
        case .controlOptionV:
            return "Control-Option-V"
        }
    }

    var carbonKeyCode: UInt32 {
        UInt32(kVK_ANSI_V)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftV:
            return UInt32(cmdKey) | UInt32(shiftKey)
        case .commandOptionV:
            return UInt32(cmdKey) | UInt32(optionKey)
        case .controlOptionV:
            return UInt32(controlKey) | UInt32(optionKey)
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .commandShiftV:
            return 1
        case .commandOptionV:
            return 2
        case .controlOptionV:
            return 3
        }
    }
}

@MainActor
final class GlobalHotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature = fourCharacterCode("MCUH")

    func register(preset: HotKeyPreset, action: @escaping () -> Void) {
        self.action = action
        installEventHandlerIfNeeded()
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: signature, id: preset.hotKeyID)
        let status = RegisterEventHotKey(
            preset.carbonKeyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("Unable to register clipboard history hotkey %@. OSStatus: %d", preset.displayName, status)
        }
    }

    func unregister() {
        unregisterHotKey()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        action = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.action?()
                }

                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("Unable to install clipboard history hotkey handler. OSStatus: %d", status)
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

private func fourCharacterCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) + OSType(byte)
    }
}
