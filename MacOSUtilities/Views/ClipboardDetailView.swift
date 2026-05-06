import SwiftUI

struct ClipboardDetailView: View {
    let entry: ClipboardHistoryEntry?
    let restore: (ClipboardHistoryEntry) -> Void
    let clearAll: () -> Void

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: entry.preview.systemImage)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .glassIconTile()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.preview.title)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .lineLimit(2)

                                Text(entry.preview.subtitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(14)
                        .glassSurface(material: .thinMaterial, isInteractive: true)

                        HStack {
                            Button {
                                restore(entry)
                            } label: {
                                Label("Restore to Clipboard", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(GlassPillButtonStyle(tint: .accentColor, isProminent: true, horizontalPadding: 14))

                            Button(role: .destructive) {
                                clearAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                            .buttonStyle(GlassPillButtonStyle(tint: .red))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Captured") {
                                Text(entry.capturedAt, format: Date.FormatStyle(date: .abbreviated, time: .standard))
                            }

                            LabeledContent("Items") {
                                Text("\(entry.itemCount)")
                            }

                            LabeledContent("Readable Data") {
                                Text("\(entry.totalByteCount.formatted()) bytes")
                            }
                        }
                        .padding(14)
                        .glassSurface(material: .ultraThinMaterial)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pasteboard Types")
                                .font(.headline)

                            ForEach(Array(entry.orderedTypeNames.enumerated()), id: \.offset) { _, typeName in
                                Text(typeName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                            }
                        }
                        .padding(14)
                        .glassSurface(material: .ultraThinMaterial)
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                }
                .background {
                    AmbientGlassBackdrop()
                        .opacity(0.55)
                }
            } else {
                ContentUnavailableView(
                    "Select a Clipboard Item",
                    systemImage: "clipboard",
                    description: Text("Copy something in another app to start collecting session history.")
                )
                .padding(24)
                .glassSurface(material: .ultraThinMaterial)
            }
        }
        .navigationTitle("Details")
    }
}
