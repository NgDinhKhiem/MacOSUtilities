//
//  ContentView.swift
//  MacOSUtilities

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var loginItemService: LoginItemService
    @Binding var maxHistoryLength: Int
    @Binding var hotKeyPresetRawValue: String

    let showPanel: () -> Void

    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            ClipboardHistoryListView(
                store: store,
                activationMode: .selectOnly
            )
            .navigationTitle("Clipboard")
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            .toolbar {
                ToolbarItem {
                    Button(action: showPanel) {
                        Image(systemName: "rectangle.on.rectangle")
                    }
                    .buttonStyle(GlassIconButtonStyle(tint: .accentColor, size: 30, isProminent: true))
                    .accessibilityLabel("Show Clipboard History")
                    .help("Show Clipboard History")
                }

                ToolbarItem {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(GlassIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor), size: 30))
                    .accessibilityLabel("Clipboard History Settings")
                    .help("Clipboard History Settings")
                }
            }
        } detail: {
            ClipboardDetailView(
                entry: store.selectedEntry,
                restore: { entry in
                    _ = store.restoreToSystemClipboard(entry)
                },
                clearAll: store.clear
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            ClipboardSettingsView(
                loginItemService: loginItemService,
                maxHistoryLength: $maxHistoryLength,
                hotKeyPresetRawValue: $hotKeyPresetRawValue,
                clearAll: store.clear,
                isCompact: false
            )
            .padding()
            .frame(width: 420)
        }
        .onAppear {
            if store.selectedEntryID == nil {
                store.selectFirst()
            }
        }
    }
}

#Preview {
    ContentView(
        store: ClipboardHistoryStore.previewStore,
        loginItemService: LoginItemService(),
        maxHistoryLength: .constant(30),
        hotKeyPresetRawValue: .constant(HotKeyPreset.commandShiftV.rawValue),
        showPanel: {}
    )
}
