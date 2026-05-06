import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var loginItemService: LoginItemService
    @Binding var maxHistoryLength: Int
    @Binding var hotKeyPresetRawValue: String

    let clearAll: () -> Void
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            if !isCompact {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .glassIconTile()

                    Text("Clipboard History Settings")
                        .font(.headline)
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Label("Maximum Items", systemImage: "number")
                        .labelStyle(.titleAndIcon)

                    Spacer()

                    historyLengthControl
                }

                Picker("Shortcut", selection: $hotKeyPresetRawValue) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset.rawValue)
                    }
                }

                Toggle(isOn: openAtLogin) {
                    Label("Open at Login", systemImage: "power")
                }
                .toggleStyle(.switch)
            }
            .padding(10)
            .glassSurface(cornerRadius: 10, material: .ultraThinMaterial)


            if let statusText = loginItemStatusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(loginItemService.errorMessage == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(GlassPillButtonStyle(tint: .red))

                Spacer()
            }
        }
        .padding(isCompact ? 0 : 14)
        .background {
            if !isCompact {
                AmbientGlassBackdrop()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 0 : GlassmorphismStyle.panelCornerRadius, style: .continuous))
        .onAppear {
            maxHistoryLength = ClipboardHistoryStore.clampedMaxHistoryLength(maxHistoryLength)
            loginItemService.refresh()
            if HotKeyPreset(rawValue: hotKeyPresetRawValue) == nil {
                hotKeyPresetRawValue = HotKeyPreset.commandShiftV.rawValue
            }
        }
    }

    private var clampedMaxHistoryLength: Binding<Int> {
        Binding {
            maxHistoryLength
        } set: { newValue in
            maxHistoryLength = ClipboardHistoryStore.clampedMaxHistoryLength(newValue)
        }
    }

    private var historyLengthControl: some View {
        HStack(spacing: 6) {
            Button {
                updateMaxHistoryLength(by: -1)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(GlassIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor), size: 26))
            .disabled(maxHistoryLength <= ClipboardHistoryStore.maxHistoryLengthRange.lowerBound)
            .help("Decrease maximum items")

            TextField("Items", value: clampedMaxHistoryLength, format: .number)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 48)
                .glassInputField(tint: .accentColor)

            Button {
                updateMaxHistoryLength(by: 1)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .accentColor, size: 26, isProminent: true))
            .disabled(maxHistoryLength >= ClipboardHistoryStore.maxHistoryLengthRange.upperBound)
            .help("Increase maximum items")
        }
    }

    private var openAtLogin: Binding<Bool> {
        Binding {
            loginItemService.isEnabled
        } set: { isEnabled in
            loginItemService.setEnabled(isEnabled)
        }
    }

    private func updateMaxHistoryLength(by delta: Int) {
        maxHistoryLength = ClipboardHistoryStore.clampedMaxHistoryLength(maxHistoryLength + delta)
    }

    private var loginItemStatusText: String? {
        loginItemService.errorMessage ?? loginItemService.statusMessage
    }
}
