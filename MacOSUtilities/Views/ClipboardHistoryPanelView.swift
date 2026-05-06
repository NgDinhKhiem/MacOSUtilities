import SwiftUI

enum ClipboardPanelTab: String, CaseIterable, Identifiable {
    case history
    case longTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history:
            return "Recent"
        case .longTerm:
            return "Saved"
        }
    }

    var helpText: String {
        switch self {
        case .history:
            return "Recent clipboard items"
        case .longTerm:
            return "Saved clipboard items"
        }
    }

    var tint: Color {
        switch self {
        case .history:
            return .accentColor
        case .longTerm:
            return .orange
        }
    }
}

@MainActor
final class ClipboardPanelState: ObservableObject {
    @Published var selectedTab: ClipboardPanelTab = .history
}

struct ClipboardHistoryPanelView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var longTermStore: LongTermClipboardStore
    @ObservedObject var panelState: ClipboardPanelState
    @ObservedObject var loginItemService: LoginItemService
    @Binding var maxHistoryLength: Int
    @Binding var hotKeyPresetRawValue: String

    let dismiss: () -> Void
    let restore: (ClipboardHistoryEntry) -> Void
    let restoreLongTerm: (LongTermClipboardEntry) -> Void

    @State private var isShowingSettings = false
    @State private var savingEntry: ClipboardHistoryEntry?
    @State private var longTermTitle = ""
    @FocusState private var isTitleFieldFocused: Bool
    @Namespace private var tabBubbleNamespace

    var body: some View {
        ZStack {
            AmbientGlassBackdrop()

            VStack(spacing: 10) {
                header

                if isShowingSettings {
                    ClipboardSettingsView(
                        loginItemService: loginItemService,
                        maxHistoryLength: $maxHistoryLength,
                        hotKeyPresetRawValue: $hotKeyPresetRawValue,
                        clearAll: store.clear,
                        isCompact: true
                    )
                    .padding(12)
                    .glassSurface(material: .ultraThinMaterial)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let savingEntry {
                    saveLongTermEditor(for: savingEntry)
                        .padding(.horizontal, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Group {
                    switch panelState.selectedTab {
                    case .history:
                        ClipboardHistoryListView(
                            store: store,
                            activationMode: .restoreOnClick(restore),
                            saveLongTerm: beginSavingLongTerm,
                            bookmarkLongTerm: bookmarkLongTerm
                        )
                    case .longTerm:
                        LongTermClipboardListView(
                            store: longTermStore,
                            restore: restoreLongTerm
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(10)
        }
        .frame(width: 446, height: 462)
        .clipShape(RoundedRectangle(cornerRadius: GlassmorphismStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassmorphismStyle.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 18)
        .onChange(of: panelState.selectedTab) { _, newTab in
            selectFirst(in: newTab)
            cancelSavingLongTerm()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .glassIconTile(tint: .accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Clipboard")
                        .font(.callout)
                        .fontWeight(.semibold)

                    Text(headerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(GlassIconButtonStyle(tint: .accentColor, size: 30, isProminent: isShowingSettings))
                .help("Settings")

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor), size: 30))
                .help("Close")
            }

            tabSwitcher
        }
        .padding(12)
        .glassSurface(material: .thinMaterial, isInteractive: true)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardPanelTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.accentColor.opacity(0.08),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: panelState.selectedTab)
    }

    private func tabButton(for tab: ClipboardPanelTab) -> some View {
        let isSelected = panelState.selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                panelState.selectedTab = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    selectedTabBubble(for: tab)
                        .frame(height: 22)
                        .matchedGeometryEffect(id: "selected-tab-bubble", in: tabBubbleNamespace)
                }

                tabTitle(for: tab, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab.helpText)
    }

    private func tabTitle(for tab: ClipboardPanelTab, isSelected: Bool) -> some View {
        Text(tab.title)
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.74))
            .frame(maxWidth: .infinity)
    }

    private func selectedTabBubble(for tab: ClipboardPanelTab) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tab.tint.opacity(0.50),
                                Color.white.opacity(0.16),
                                Color.black.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.normal)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                tab.tint.opacity(0.46),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: tab.tint.opacity(0.22), radius: 6, x: 0, y: 3)
    }

    private func saveLongTermEditor(for entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)

                Text("Save")
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                Text(entry.preview.typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Title", text: $longTermTitle)
                    .glassInputField(tint: .accentColor)
                    .focused($isTitleFieldFocused)
                    .onSubmit {
                        finishSavingLongTerm(entry)
                    }

                Button {
                    finishSavingLongTerm(entry)
                } label: {
                    Label("Save", systemImage: "bookmark.fill")
                }
                .buttonStyle(GlassPillButtonStyle(tint: .accentColor, isProminent: true))
                .keyboardShortcut(.return, modifiers: [])

                Button {
                    cancelSavingLongTerm()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor), size: 28))
                .help("Cancel")
            }
        }
        .padding(10)
        .glassSurface(material: .ultraThinMaterial, tint: .accentColor, isInteractive: true)
        .onAppear {
            isTitleFieldFocused = true
        }
    }

    private var footer: some View {
        HStack {
            Label("Return restores", systemImage: "return")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Esc closes")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(footerCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .red, size: 28))
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassSurface(cornerRadius: 13, material: .ultraThinMaterial)
    }

    private var headerSubtitle: String {
        switch panelState.selectedTab {
        case .history:
            return "\(store.entries.count) recent items"
        case .longTerm:
            return "\(longTermStore.entries.count) saved items"
        }
    }

    private var footerCountText: String {
        switch panelState.selectedTab {
        case .history:
            return "\(store.entries.count)/\(maxHistoryLength)"
        case .longTerm:
            return "\(longTermStore.entries.count) saved"
        }
    }

    private func beginSavingLongTerm(_ entry: ClipboardHistoryEntry) {
        savingEntry = entry
        longTermTitle = ""
        isShowingSettings = false

        Task { @MainActor in
            isTitleFieldFocused = true
        }
    }

    private func finishSavingLongTerm(_ entry: ClipboardHistoryEntry) {
        let savedEntry = longTermStore.save(entry, title: longTermTitle)
        store.delete(entry)
        longTermStore.selectedEntryID = savedEntry.id
        panelState.selectedTab = .longTerm
        cancelSavingLongTerm()
    }

    private func bookmarkLongTerm(_ entry: ClipboardHistoryEntry) {
        let savedEntry = longTermStore.save(entry, title: "")
        store.delete(entry)
        longTermStore.selectedEntryID = savedEntry.id
        panelState.selectedTab = .longTerm
        cancelSavingLongTerm()
    }

    private func cancelSavingLongTerm() {
        savingEntry = nil
        longTermTitle = ""
        isTitleFieldFocused = false
    }

    private func selectFirst(in tab: ClipboardPanelTab) {
        switch tab {
        case .history:
            store.selectFirst()
        case .longTerm:
            longTermStore.selectFirst()
        }
    }
}
