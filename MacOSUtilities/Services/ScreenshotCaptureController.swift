import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

private final class ScreenshotOverlayWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
final class ScreenshotCaptureController: NSObject {
    private var window: ScreenshotOverlayWindow?
    private var session: ScreenshotCaptureSession?
    private var hostingController: NSHostingController<ScreenshotOverlayView>?
    private var localKeyMonitor: Any?
    private var appDeactivateObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var keyWindowObserver: NSObjectProtocol?
    private var didRequestScreenCaptureAccess = false
    private var didLogUnavailableScreenCaptureAccess = false

    func showOverlay() {
        if window?.isVisible == true {
            dismissOverlay()
            return
        }

        guard ensureScreenCaptureAccess() else {
            logUnavailableScreenCaptureAccess()
            return
        }

        let screen = activeScreen()
        guard let displayID = displayID(for: screen),
              let cgImage = CGDisplayCreateImage(displayID) else {
            showCaptureError()
            return
        }

        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        let session = ScreenshotCaptureSession(
            image: image,
            screenFrame: screen.frame,
            pixelWidth: cgImage.width
        )

        self.session = session
        showWindow(for: session, on: screen)
    }

    private func showWindow(for session: ScreenshotCaptureSession, on screen: NSScreen) {
        let rootView = ScreenshotOverlayView(
            session: session,
            copySelection: { [weak self] in
                self?.copySelection()
            },
            saveSelection: { [weak self] in
                self?.saveSelection()
            },
            cancel: { [weak self] in
                self?.dismissOverlay()
            }
        )

        let window = window ?? makeWindow()
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            window.contentViewController = hostingController
            self.hostingController = hostingController
        }

        window.setFrame(screen.frame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        installKeyMonitor()
        installDiscardMonitors(for: window)
    }

    private func makeWindow() -> ScreenshotOverlayWindow {
        let window = ScreenshotOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.acceptsMouseMovedEvents = true
        self.window = window
        return window
    }

    private func dismissOverlay() {
        removeKeyMonitor()
        removeDiscardMonitors()
        window?.orderOut(nil)
        session = nil
    }

    private func copySelection() {
        guard let image = renderedSelection() else {
            dismissOverlay()
            return
        }

        guard let pngData = ScreenshotRenderer.pngData(for: image) else {
            NSSound.beep()
            dismissOverlay()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData = image.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }
        pasteboard.writeObjects([item])
        dismissOverlay()
    }

    private func saveSelection() {
        guard let image = renderedSelection() else {
            dismissOverlay()
            return
        }

        guard let pngData = ScreenshotRenderer.pngData(for: image) else {
            NSSound.beep()
            dismissOverlay()
            return
        }

        dismissOverlay()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultScreenshotName()
        savePanel.title = "Save Screenshot"

        savePanel.begin { response in
            guard response == .OK,
                  let url = savePanel.url else {
                return
            }

            do {
                try pngData.write(to: url, options: .atomic)
            } catch {
                Task { @MainActor in
                    self.showSaveError(error)
                }
            }
        }
    }

    private func renderedSelection() -> NSImage? {
        guard let session else {
            return nil
        }

        return ScreenshotRenderer.render(session: session)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if window?.firstResponder is NSTextView {
                return event
            }

            guard let command = controllerCommand(for: event) else {
                return event
            }

            perform(command)
            return nil
        }
    }

    private func controllerCommand(for event: NSEvent) -> ScreenshotSessionCommand? {
        switch event.keyCode {
        case 53:
            return ScreenshotSessionCommandPolicy.escape(activeTextEdit: false)
        case 36, 76:
            return ScreenshotSessionCommandPolicy.returnKey(
                activeTextEdit: false,
                commandPressed: event.modifierFlags.contains(.command)
            )
        case 0 where event.modifierFlags.contains(.command):
            return ScreenshotSessionCommandPolicy.selectAllShortcut(activeTextEdit: false)
        case 8 where event.modifierFlags.contains(.command):
            return ScreenshotSessionCommandPolicy.copyShortcut()
        case 1 where event.modifierFlags.contains(.command):
            return ScreenshotSessionCommandPolicy.saveShortcut()
        default:
            return nil
        }
    }

    private func perform(_ command: ScreenshotSessionCommand) {
        switch command {
        case .discard:
            dismissOverlay()
        case .confirmCopy:
            copySelection()
        case .confirmSave:
            saveSelection()
        case .selectFullScreen:
            session?.selectFullScreen()
        case .cancelActiveText, .passThrough:
            break
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func installDiscardMonitors(for window: ScreenshotOverlayWindow) {
        removeDiscardMonitors()

        appDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissOverlayIfVisible()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissOverlayIfVisible()
            }
        }

        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self,
                      let window,
                      window.isVisible else {
                    return
                }

                await Task.yield()
                guard NSApp.isActive,
                      let keyWindow = NSApp.keyWindow,
                      keyWindow !== window else {
                    return
                }

                self.dismissOverlay()
            }
        }
    }

    private func dismissOverlayIfVisible() {
        guard window?.isVisible == true else {
            return
        }

        dismissOverlay()
    }

    private func removeDiscardMonitors() {
        let notificationCenter = NotificationCenter.default
        if let appDeactivateObserver {
            notificationCenter.removeObserver(appDeactivateObserver)
            self.appDeactivateObserver = nil
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        if let activeSpaceObserver {
            workspaceNotificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }

        if let keyWindowObserver {
            notificationCenter.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            didRequestScreenCaptureAccess = false
            didLogUnavailableScreenCaptureAccess = false
            return true
        }

        guard !didRequestScreenCaptureAccess else {
            return false
        }

        didRequestScreenCaptureAccess = true
        let granted = CGRequestScreenCaptureAccess()
        if granted || CGPreflightScreenCaptureAccess() {
            return true
        }

        return false
    }

    private func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }

        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        guard let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("No screen is available for screenshot capture.")
        }

        return fallbackScreen
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func defaultScreenshotName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }

    private func logUnavailableScreenCaptureAccess() {
        guard !didLogUnavailableScreenCaptureAccess else {
            return
        }

        didLogUnavailableScreenCaptureAccess = true
        let bundle = Bundle.main
        NSLog(
            "Capture overlay blocked by unavailable Screen Recording permission. bundleID=%@ path=%@ requestedThisLaunch=%@",
            bundle.bundleIdentifier ?? "unknown",
            bundle.bundleURL.path,
            didRequestScreenCaptureAccess.description
        )
    }

    private func showCaptureError() {
        let alert = NSAlert()
        alert.messageText = "Unable to Capture Screen"
        alert.informativeText = "macOS did not return a screen image for the active display."
        alert.alertStyle = .warning
        SystemAlertPresenter.run(alert)
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to Save Screenshot"
        SystemAlertPresenter.run(alert)
    }
}
