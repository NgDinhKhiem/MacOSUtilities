import AppKit
import Foundation
import SwiftUI

@MainActor
final class ClipboardRuntime: ObservableObject {
    let store: ClipboardHistoryStore
    let longTermStore: LongTermClipboardStore
    let appController: ClipboardAppController
    let screenshotController: ScreenshotCaptureController
    let loginItemService: LoginItemService

    @Published private(set) var maxHistoryLength: Int
    @Published private(set) var hotKeyPresetRawValue: String

    private var isStarted = false
    private let captureHotKeyService = GlobalHotKeyService(signature: "MCUC", logName: "capture")
    private var didReportCaptureHotKeyFailure = false

    init() {
        self.store = ClipboardHistoryStore()
        self.longTermStore = LongTermClipboardStore()
        self.appController = ClipboardAppController()
        self.screenshotController = ScreenshotCaptureController()
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
        registerCaptureHotKey()
    }

    func showPanel() {
        start()
        appController.showPanel()
    }

    func showScreenshotOverlay() {
        start()
        screenshotController.showOverlay()
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

    private func registerCaptureHotKey() {
        let didRegister = captureHotKeyService.register(preset: CaptureHotKeyPreset.commandShiftX) { [weak self] in
            self?.showScreenshotOverlay()
        }

        if !didRegister {
            reportCaptureHotKeyFailure()
        }
    }

    private func reportCaptureHotKeyFailure() {
        guard !didReportCaptureHotKeyFailure else {
            return
        }

        didReportCaptureHotKeyFailure = true

        let alert = NSAlert()
        alert.messageText = "Capture Shortcut Unavailable"
        alert.informativeText = "MacOSUtilities could not register Command-Shift-X for Capture. Another app may already own that shortcut. Change or close the conflicting app, then restart MacOSUtilities."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        SystemAlertPresenter.run(alert)
    }
}
