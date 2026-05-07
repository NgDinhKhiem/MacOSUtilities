import SwiftUI

@MainActor
final class ClipboardAppController: ObservableObject {
    private let monitor = PasteboardMonitor()
    private let hotKeyService = GlobalHotKeyService(signature: "MCUH", logName: "clipboard history")
    private let panelController = ClipboardPanelController()

    private weak var store: ClipboardHistoryStore?
    private weak var longTermStore: LongTermClipboardStore?
    private weak var loginItemService: LoginItemService?
    private var isConfigured = false
    private var registeredHotKeyRawValue: String?
    private var didReportHotKeyFailure = false

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
        let didRegister = hotKeyService.register(preset: preset) { [weak self] in
            self?.showPanel()
        }

        if didRegister {
            registeredHotKeyRawValue = preset.rawValue
            didReportHotKeyFailure = false
        } else {
            registeredHotKeyRawValue = nil
            reportHotKeyFailure(preset)
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

    private func reportHotKeyFailure(_ preset: HotKeyPreset) {
        guard !didReportHotKeyFailure else {
            return
        }

        didReportHotKeyFailure = true

        let alert = NSAlert()
        alert.messageText = "Clipboard Shortcut Unavailable"
        alert.informativeText = "MacOSUtilities could not register \(preset.displayName) for Clipboard. Another app or system shortcut may already own it. Choose another preset in settings or close the conflicting shortcut owner, then restart MacOSUtilities."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        SystemAlertPresenter.run(alert)
    }
}
