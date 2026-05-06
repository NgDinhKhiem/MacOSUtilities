import AppKit
import SwiftUI

private enum ClipboardSidePanelMetrics {
    static let size = NSSize(width: 446, height: 462)
    static let screenInset: CGFloat = 16
    static let offscreenInset: CGFloat = 18
    static let showAnimationDuration = 0.22
    static let hideAnimationDuration = 0.16
}

private final class ClipboardHistorySidePanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
final class ClipboardPanelController: NSObject {
    private weak var store: ClipboardHistoryStore?
    private weak var longTermStore: LongTermClipboardStore?
    private weak var loginItemService: LoginItemService?
    private var maxHistoryLength: Binding<Int>?
    private var hotKeyPresetRawValue: Binding<String>?
    private var restore: ((ClipboardHistoryEntry) -> Void)?
    private var restoreLongTerm: ((LongTermClipboardEntry) -> Void)?

    private let panelState = ClipboardPanelState()
    private var panel: ClipboardHistorySidePanelWindow?
    private var hostingController: NSHostingController<ClipboardHistoryPanelView>?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func configure(
        store: ClipboardHistoryStore,
        longTermStore: LongTermClipboardStore,
        loginItemService: LoginItemService,
        maxHistoryLength: Binding<Int>,
        hotKeyPresetRawValue: Binding<String>,
        restore: @escaping (ClipboardHistoryEntry) -> Void,
        restoreLongTerm: @escaping (LongTermClipboardEntry) -> Void
    ) {
        self.store = store
        self.longTermStore = longTermStore
        self.loginItemService = loginItemService
        self.maxHistoryLength = maxHistoryLength
        self.hotKeyPresetRawValue = hotKeyPresetRawValue
        self.restore = restore
        self.restoreLongTerm = restoreLongTerm
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func hidePanel() {
        removeEventMonitors()

        guard let panel, panel.isVisible else {
            return
        }

        let targetFrame = offscreenFrame(for: panel.frame, on: panel.screen ?? activeScreen())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ClipboardSidePanelMetrics.hideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(targetFrame, display: false)
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    private func showPanel() {
        guard let store,
              let longTermStore,
              let loginItemService,
              let maxHistoryLength,
              let hotKeyPresetRawValue else {
            return
        }

        switch panelState.selectedTab {
        case .history:
            store.selectFirst()
        case .longTerm:
            longTermStore.selectFirst()
        }

        let rootView = ClipboardHistoryPanelView(
            store: store,
            longTermStore: longTermStore,
            panelState: panelState,
            loginItemService: loginItemService,
            maxHistoryLength: maxHistoryLength,
            hotKeyPresetRawValue: hotKeyPresetRawValue,
            dismiss: { [weak self] in
                self?.hidePanel()
            },
            restore: { [weak self] entry in
                self?.restore?(entry)
            },
            restoreLongTerm: { [weak self] entry in
                self?.restoreLongTerm?(entry)
            }
        )

        let panel = panel ?? makePanel()
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            panel.contentViewController = hostingController
            self.hostingController = hostingController
        }

        let screen = activeScreen()
        let finalFrame = visibleFrame(on: screen)
        let startFrame = offscreenFrame(for: finalFrame, on: screen)

        panel.setFrame(startFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = ClipboardSidePanelMetrics.showAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }

        installEventMonitors()
    }

    private func makePanel() -> ClipboardHistorySidePanelWindow {
        let panel = ClipboardHistorySidePanelWindow(
            contentRect: NSRect(origin: .zero, size: ClipboardSidePanelMetrics.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.worksWhenModal = true
        self.panel = panel
        return panel
    }

    private func activeScreen() -> NSScreen {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }

        guard let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("No screen is available for clipboard panel presentation.")
        }

        return fallbackScreen
    }

    private func visibleFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let size = ClipboardSidePanelMetrics.size
        let x = visibleFrame.maxX - size.width - ClipboardSidePanelMetrics.screenInset
        let y = visibleFrame.maxY - size.height - ClipboardSidePanelMetrics.screenInset

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func offscreenFrame(for frame: NSRect, on screen: NSScreen) -> NSRect {
        var offscreenFrame = frame
        offscreenFrame.origin.x = screen.visibleFrame.maxX + ClipboardSidePanelMetrics.offscreenInset
        return offscreenFrame
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyDown(event) == true {
                return nil
            }

            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.shouldHideForLocalMouseEvent(event) == true {
                self?.hidePanel()
            }

            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hidePanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func shouldHideForLocalMouseEvent(_ event: NSEvent) -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }

        return event.window !== panel
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let store else {
            return false
        }

        if NSApp.keyWindow?.firstResponder is NSTextView {
            return false
        }

        switch event.keyCode {
        case 53:
            hidePanel()
            return true
        case 125:
            switch panelState.selectedTab {
            case .history:
                store.selectNext()
            case .longTerm:
                longTermStore?.selectNext()
            }
            return true
        case 126:
            switch panelState.selectedTab {
            case .history:
                store.selectPrevious()
            case .longTerm:
                longTermStore?.selectPrevious()
            }
            return true
        case 36, 76:
            switch panelState.selectedTab {
            case .history:
                if let selectedEntry = store.selectedEntry {
                    restore?(selectedEntry)
                }
            case .longTerm:
                if let selectedEntry = longTermStore?.selectedEntry {
                    restoreLongTerm?(selectedEntry)
                }
            }
            return true
        case 18:
            panelState.selectedTab = .history
            store.selectFirst()
            return true
        case 19:
            panelState.selectedTab = .longTerm
            longTermStore?.selectFirst()
            return true
        default:
            return false
        }
    }
}
