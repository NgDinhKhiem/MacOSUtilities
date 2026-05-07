import AppKit
import Carbon.HIToolbox
import Foundation

protocol GlobalHotKeyPreset {
    var displayName: String { get }
    var carbonKeyCode: UInt32 { get }
    var carbonModifiers: UInt32 { get }
    var hotKeyID: UInt32 { get }
}

enum HotKeyPreset: String, CaseIterable, Identifiable, GlobalHotKeyPreset {
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

enum CaptureHotKeyPreset: String, CaseIterable, Identifiable, GlobalHotKeyPreset {
    case commandShiftX

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandShiftX:
            return "Command-Shift-X"
        }
    }

    var carbonKeyCode: UInt32 {
        UInt32(kVK_ANSI_X)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftX:
            return UInt32(cmdKey) | UInt32(shiftKey)
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .commandShiftX:
            return 20
        }
    }
}

@MainActor
final class GlobalHotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var registeredHotKeyID: EventHotKeyID?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature: OSType
    private let logName: String

    init(signature: String = "MCUH", logName: String = "global") {
        self.signature = fourCharacterCode(signature)
        self.logName = logName
    }

    @discardableResult
    func register<Preset: GlobalHotKeyPreset>(preset: Preset, action: @escaping () -> Void) -> Bool {
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
            NSLog("Unable to register %@ hotkey %@. OSStatus: %d", logName, preset.displayName, status)
            registeredHotKeyID = nil
            return false
        }

        registeredHotKeyID = hotKeyID
        return true
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
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                guard service.handles(event: event) else {
                    return OSStatus(eventNotHandledErr)
                }

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
            NSLog("Unable to install %@ hotkey handler. OSStatus: %d", logName, status)
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        registeredHotKeyID = nil
    }

    private func handles(event: EventRef) -> Bool {
        guard let registeredHotKeyID else {
            return false
        }

        var pressedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )

        guard status == noErr else {
            return false
        }

        return pressedHotKeyID.signature == registeredHotKeyID.signature
            && pressedHotKeyID.id == registeredHotKeyID.id
    }
}

private func fourCharacterCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) + OSType(byte)
    }
}
