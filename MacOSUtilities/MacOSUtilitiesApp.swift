import AppKit
import SwiftUI

final class ClipboardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

@main
struct MacOSUtilitiesApp: App {
    @NSApplicationDelegateAdaptor(ClipboardAppDelegate.self) private var appDelegate

    @StateObject private var runtime = ClipboardRuntime()

    var body: some Scene {
        Settings {
            EmptyView()
                .onAppear {
                    runtime.start()
                }
        }
    }
}
