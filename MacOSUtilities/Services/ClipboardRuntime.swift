import Foundation
import SwiftUI

@MainActor
final class ClipboardRuntime: ObservableObject {
    let store: ClipboardHistoryStore
    let longTermStore: LongTermClipboardStore
    let appController: ClipboardAppController
    let loginItemService: LoginItemService

    @Published private(set) var maxHistoryLength: Int
    @Published private(set) var hotKeyPresetRawValue: String

    private var isStarted = false

    init() {
        self.store = ClipboardHistoryStore()
        self.longTermStore = LongTermClipboardStore()
        self.appController = ClipboardAppController()
        self.loginItemService = LoginItemService()

        let savedMaxLength = UserDefaults.standard.object(forKey: AppPreferenceKeys.maxHistoryLength) as? Int
        self.maxHistoryLength = ClipboardHistoryStore.clampedMaxHistoryLength(
            savedMaxLength ?? ClipboardHistoryStore.defaultMaxHistoryLength
        )

        let savedHotKey = UserDefaults.standard.string(forKey: AppPreferenceKeys.hotKeyPreset)
        if let savedHotKey, HotKeyPreset(rawValue: savedHotKey) != nil {
            self.hotKeyPresetRawValue = savedHotKey
        } else {
            self.hotKeyPresetRawValue = HotKeyPreset.commandShiftV.rawValue
        }

        Task { @MainActor in
            start()
        }
    }

    var currentHotKeyPreset: HotKeyPreset {
        HotKeyPreset(rawValue: hotKeyPresetRawValue) ?? .commandShiftV
    }

    var maxHistoryLengthBinding: Binding<Int> {
        Binding {
            self.maxHistoryLength
        } set: { newValue in
            self.setMaxHistoryLength(newValue)
        }
    }

    var hotKeyPresetBinding: Binding<String> {
        Binding {
            self.hotKeyPresetRawValue
        } set: { newValue in
            self.setHotKeyPreset(rawValue: newValue)
        }
    }

    var openAtLoginBinding: Binding<Bool> {
        Binding {
            self.loginItemService.isEnabled
        } set: { isEnabled in
            self.loginItemService.setEnabled(isEnabled)
        }
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        store.updateMaxHistoryLength(maxHistoryLength)
        loginItemService.refresh()
        appController.configure(
            store: store,
            longTermStore: longTermStore,
            loginItemService: loginItemService,
            maxHistoryLength: maxHistoryLengthBinding,
            hotKeyPresetRawValue: hotKeyPresetBinding
        )
    }

    func showPanel() {
        start()
        appController.showPanel()
    }

    func clearHistory() {
        store.clear()
    }

    func setMaxHistoryLength(_ value: Int) {
        let clampedValue = ClipboardHistoryStore.clampedMaxHistoryLength(value)
        guard maxHistoryLength != clampedValue else {
            return
        }

        maxHistoryLength = clampedValue
        UserDefaults.standard.set(clampedValue, forKey: AppPreferenceKeys.maxHistoryLength)
        store.updateMaxHistoryLength(clampedValue)
    }

    func setHotKeyPreset(rawValue: String) {
        let preset = HotKeyPreset(rawValue: rawValue) ?? .commandShiftV
        guard hotKeyPresetRawValue != preset.rawValue else {
            return
        }

        hotKeyPresetRawValue = preset.rawValue
        UserDefaults.standard.set(preset.rawValue, forKey: AppPreferenceKeys.hotKeyPreset)
        appController.updateHotKey(rawValue: preset.rawValue)
    }
}
