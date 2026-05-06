import SwiftUI

@MainActor
final class ClipboardAppController: ObservableObject {
    private let monitor = PasteboardMonitor()
    private let hotKeyService = GlobalHotKeyService()
    private let panelController = ClipboardPanelController()

    private weak var store: ClipboardHistoryStore?
    private weak var longTermStore: LongTermClipboardStore?
    private weak var loginItemService: LoginItemService?
    private var isConfigured = false
    private var registeredHotKeyRawValue: String?

    func configure(
        store: ClipboardHistoryStore,
        longTermStore: LongTermClipboardStore,
        loginItemService: LoginItemService,
        maxHistoryLength: Binding<Int>,
        hotKeyPresetRawValue: Binding<String>
    ) {
        self.store = store
        self.longTermStore = longTermStore
        self.loginItemService = loginItemService

        store.updateMaxHistoryLength(maxHistoryLength.wrappedValue)
        panelController.configure(
            store: store,
            longTermStore: longTermStore,
            loginItemService: loginItemService,
            maxHistoryLength: maxHistoryLength,
            hotKeyPresetRawValue: hotKeyPresetRawValue
        ) { [weak self] entry in
            self?.restore(entry)
        } restoreLongTerm: { [weak self] entry in
            self?.restoreLongTerm(entry)
        }

        if !isConfigured {
            monitor.start(store: store)
            isConfigured = true
        }

        updateHotKey(rawValue: hotKeyPresetRawValue.wrappedValue)
    }

    func updateHotKey(rawValue: String) {
        guard registeredHotKeyRawValue != rawValue else {
            return
        }

        let preset = HotKeyPreset(rawValue: rawValue) ?? .commandShiftV
        registeredHotKeyRawValue = preset.rawValue

        hotKeyService.register(preset: preset) { [weak self] in
            self?.showPanel()
        }
    }

    func showPanel() {
        panelController.togglePanel()
    }

    private func restore(_ entry: ClipboardHistoryEntry) {
        guard let store else {
            return
        }

        if store.restoreToSystemClipboard(entry) {
            panelController.hidePanel()
        }
    }

    private func restoreLongTerm(_ entry: LongTermClipboardEntry) {
        guard let longTermStore else {
            return
        }

        if longTermStore.restoreToSystemClipboard(entry) {
            panelController.hidePanel()
        }
    }
}
