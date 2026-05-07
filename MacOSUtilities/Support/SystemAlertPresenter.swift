import AppKit

@MainActor
enum SystemAlertPresenter {
    @discardableResult
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        return alert.runModal()
    }
}
