import SwiftUI

extension HotKeyPreset {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent("v")
    }

    var eventModifiers: EventModifiers {
        switch self {
        case .commandShiftV:
            return [.command, .shift]
        case .commandOptionV:
            return [.command, .option]
        case .controlOptionV:
            return [.control, .option]
        }
    }
}
