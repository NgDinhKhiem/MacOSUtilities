import AppKit
import SwiftUI

enum ClipboardHistoryActivationMode {
    case selectOnly
    case restoreOnClick((ClipboardHistoryEntry) -> Void)
}

private enum ClipboardRowMetrics {
    static let rowHeight: CGFloat = 54
    static let deleteThreshold: CGFloat = 150
    static let maximumHorizontalDrag: CGFloat = 190
}

private enum ClipboardRowSwipeAction {
    case delete
    case bookmark

    var systemImage: String {
        switch self {
        case .delete:
            return "trash"
        case .bookmark:
            return "bookmark"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .delete:
            return "trash.fill"
        case .bookmark:
            return "bookmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .delete:
            return .red
        case .bookmark:
            return .accentColor
        }
    }
}

private struct ClipboardRowDragState: Equatable {
    let id: UUID
    let startIndex: Int
    var translation: CGSize

    func swipeAction(allowsBookmark: Bool) -> ClipboardRowSwipeAction? {
        guard abs(translation.width) >= ClipboardRowMetrics.deleteThreshold
            && abs(translation.width) > abs(translation.height)
        else {
            return nil
        }

        if translation.width < 0 {
            return .delete
        }

        return allowsBookmark ? .bookmark : nil
    }
}

private func reorderTargetIndex(startIndex: Int, translation: CGFloat, count: Int) -> Int {
    guard count > 0 else {
        return 0
    }

    let offset = Int((translation / ClipboardRowMetrics.rowHeight).rounded(.toNearestOrAwayFromZero))
    return min(max(startIndex + offset, 0), count - 1)
}

struct ClipboardHistoryListView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let activationMode: ClipboardHistoryActivationMode
    let saveLongTerm: ((ClipboardHistoryEntry) -> Void)?
    let bookmarkLongTerm: ((ClipboardHistoryEntry) -> Void)?

    @State private var hoveredEntryID: ClipboardHistoryEntry.ID?
    @State private var previewEntryID: ClipboardHistoryEntry.ID?
    @State private var previewTask: Task<Void, Never>?
    @State private var dragState: ClipboardRowDragState?

    init(
        store: ClipboardHistoryStore,
        activationMode: ClipboardHistoryActivationMode,
        saveLongTerm: ((ClipboardHistoryEntry) -> Void)? = nil,
        bookmarkLongTerm: ((ClipboardHistoryEntry) -> Void)? = nil
    ) {
        self.store = store
        self.activationMode = activationMode
        self.saveLongTerm = saveLongTerm
        self.bookmarkLongTerm = bookmarkLongTerm
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Clipboard History",
                    systemImage: "clipboard",
                    description: Text("Copied items will appear here while the app is running.")
                )
                .padding()
                .glassSurface(material: .ultraThinMaterial)
                .padding(.horizontal, 12)
            } else {
                switch activationMode {
                case .selectOnly:
                    List(selection: selectedEntryID) {
                        ForEach(store.entries) { entry in
                            ClipboardHistoryRow(
                                entry: entry,
                                isSelected: store.selectedEntryID == entry.id,
                                isPanel: false,
                                dragTranslation: dragState(for: entry.id)?.translation ?? .zero,
                                isDragging: dragState?.id == entry.id,
                                allowsBookmarkSwipe: bookmarkLongTerm != nil || saveLongTerm != nil,
                                swipeAction: swipeAction(for: entry)
                            )
                            .tag(entry.id)
                            .simultaneousGesture(reorderGesture(for: entry))
                            .onHover { isHovering in
                                updateHover(entry: entry, isHovering: isHovering)
                            }
                            .popover(isPresented: detailPreviewBinding(for: entry)) {
                                ClipboardDetailPreviewPopover(entry: entry)
                            }
                            .contextMenu {
                                if let saveLongTerm {
                                    Button {
                                        saveLongTerm(entry)
                                    } label: {
                                        Label("Save", systemImage: "bookmark")
                                    }
                                }

                                Button {
                                    _ = store.restoreToSystemClipboard(entry)
                                } label: {
                                    Label("Restore to Clipboard", systemImage: "doc.on.clipboard")
                                }

                                Button(role: .destructive) {
                                    store.delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button(role: .destructive) {
                                    store.clear()
                                } label: {
                                    Label("Clear All", systemImage: "trash.slash")
                                }
                            }
                            .zIndex(dragState?.id == entry.id ? 1 : 0)
                        }
                    }
                    .listStyle(.sidebar)
                case .restoreOnClick(let restore):
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(store.entries) { entry in
                                ClipboardHistoryRow(
                                    entry: entry,
                                    isSelected: store.selectedEntryID == entry.id,
                                    isPanel: true,
                                    dragTranslation: dragState(for: entry.id)?.translation ?? .zero,
                                    isDragging: dragState?.id == entry.id,
                                    allowsBookmarkSwipe: bookmarkLongTerm != nil || saveLongTerm != nil,
                                    swipeAction: swipeAction(for: entry)
                                )
                                .contentShape(Rectangle())
                                .simultaneousGesture(reorderGesture(for: entry))
                                .onTapGesture {
                                    restore(entry)
                                }
                                .onHover { isHovering in
                                    updateHover(entry: entry, isHovering: isHovering)
                                    if isHovering {
                                        store.selectedEntryID = entry.id
                                    }
                                }
                                .popover(isPresented: detailPreviewBinding(for: entry)) {
                                    ClipboardDetailPreviewPopover(entry: entry)
                                }
                                .contextMenu {
                                    if let saveLongTerm {
                                        Button {
                                            saveLongTerm(entry)
                                        } label: {
                                            Label("Save", systemImage: "bookmark")
                                        }
                                    }

                                    Button {
                                        _ = store.restoreToSystemClipboard(entry)
                                    } label: {
                                        Label("Restore to Clipboard", systemImage: "doc.on.clipboard")
                                    }

                                    Button(role: .destructive) {
                                        store.delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button(role: .destructive) {
                                        store.clear()
                                    } label: {
                                        Label("Clear All", systemImage: "trash.slash")
                                    }
                                }
                                .zIndex(dragState?.id == entry.id ? 1 : 0)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var selectedEntryID: Binding<ClipboardHistoryEntry.ID?> {
        Binding {
            store.selectedEntryID
        } set: { newValue in
            store.selectedEntryID = newValue
        }
    }

    private func updateHover(entry: ClipboardHistoryEntry, isHovering: Bool) {
        previewTask?.cancel()

        if isHovering {
            hoveredEntryID = entry.id
            scheduleDetailPreview(for: entry)
        } else if hoveredEntryID == entry.id {
            hoveredEntryID = nil
            previewEntryID = nil
        }
    }

    private func scheduleDetailPreview(for entry: ClipboardHistoryEntry) {
        previewTask?.cancel()
        guard dragState?.id != entry.id else {
            previewEntryID = nil
            return
        }

        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled,
                  hoveredEntryID == entry.id,
                  dragState?.id != entry.id else {
                return
            }
            previewEntryID = entry.id
        }
    }

    private func dragState(for id: ClipboardHistoryEntry.ID) -> ClipboardRowDragState? {
        dragState?.id == id ? dragState : nil
    }

    private func reorderGesture(for entry: ClipboardHistoryEntry) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                updateDrag(entry: entry, translation: value.translation)
            }
            .onEnded { value in
                finishDrag(entry: entry, translation: value.translation)
            }
    }

    private func updateDrag(entry: ClipboardHistoryEntry, translation: CGSize) {
        previewTask?.cancel()
        previewEntryID = nil
        hoveredEntryID = entry.id
        store.selectedEntryID = entry.id

        var nextState: ClipboardRowDragState
        if let currentState = dragState, currentState.id == entry.id {
            nextState = currentState
            nextState.translation = translation
        } else {
            nextState = ClipboardRowDragState(
                id: entry.id,
                startIndex: store.entries.firstIndex(where: { $0.id == entry.id }) ?? 0,
                translation: translation
            )
        }
        dragState = nextState

        guard abs(translation.height) > abs(translation.width) * 0.75 else {
            return
        }

        let targetIndex = reorderTargetIndex(
            startIndex: nextState.startIndex,
            translation: translation.height,
            count: store.entries.count
        )

        withAnimation(.easeInOut(duration: 0.16)) {
            store.move(entry, to: targetIndex)
        }
    }

    private func finishDrag(entry: ClipboardHistoryEntry, translation: CGSize) {
        var state = dragState ?? ClipboardRowDragState(
            id: entry.id,
            startIndex: store.entries.firstIndex(where: { $0.id == entry.id }) ?? 0,
            translation: translation
        )
        state.translation = translation

        withAnimation(.easeOut(duration: 0.18)) {
            switch state.swipeAction(allowsBookmark: saveLongTerm != nil) {
            case .delete:
                store.delete(entry)
            case .bookmark:
                if let bookmarkLongTerm {
                    bookmarkLongTerm(entry)
                } else {
                    saveLongTerm?(entry)
                }
            case nil:
                break
            }
            dragState = nil
        }
    }

    private func swipeAction(for entry: ClipboardHistoryEntry) -> ClipboardRowSwipeAction? {
        dragState(for: entry.id)?.swipeAction(allowsBookmark: bookmarkLongTerm != nil || saveLongTerm != nil)
    }

    private func detailPreviewBinding(for entry: ClipboardHistoryEntry) -> Binding<Bool> {
        Binding {
            previewEntryID == entry.id
        } set: { isPresented in
            if !isPresented, previewEntryID == entry.id {
                previewEntryID = nil
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    let entry: ClipboardHistoryEntry
    var titleOverride: String? = nil
    let isSelected: Bool
    let isPanel: Bool
    var dragTranslation: CGSize = .zero
    var isDragging: Bool = false
    var allowsBookmarkSwipe = false
    var swipeAction: ClipboardRowSwipeAction?

    var body: some View {
        ZStack {
            dragActionBackdrop

            rowContent
                .offset(x: horizontalDragOffset)
                .scaleEffect(isDragging ? 1.012 : 1)
                .shadow(color: .black.opacity(isDragging ? 0.20 : 0.08), radius: isDragging ? 12 : 5, x: 0, y: isDragging ? 7 : 2)
                .animation(.easeOut(duration: 0.18), value: horizontalDragOffset)
                .animation(.easeOut(duration: 0.18), value: isDragging)
        }
        .frame(height: isPanel ? ClipboardRowMetrics.rowHeight : 48)
        .contentShape(Rectangle())
        .help(dragHelpText)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            ClipboardPreviewIcon(
                entry: entry,
                isSelected: isSelected,
                isPanel: isPanel
            )

            Text(titleOverride ?? entry.preview.title)
                .font(isPanel ? .callout : .body)
                .fontWeight(isPanel ? .medium : .regular)
                .foregroundStyle(isSelected && isPanel ? .white : .primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isPanel ? 12 : 0)
        .padding(.vertical, isPanel ? 6 : 4)
        .background {
            if isSelected && isPanel {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.52),
                                Color.accentColor.opacity(0.24),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
            } else if isPanel {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
            }
        }
    }

    private var dragHelpText: String {
        allowsBookmarkSwipe
            ? "Drag up or down to reorder. Drag left to delete. Drag right to bookmark."
            : "Drag up or down to reorder. Drag left to delete."
    }

    private var horizontalDragOffset: CGFloat {
        guard isDragging else {
            return 0
        }

        let width = dragTranslation.width
        if width > 0 && !allowsBookmarkSwipe {
            return 0
        }

        guard abs(width) > abs(dragTranslation.height) * 0.55 else {
            return 0
        }

        return min(max(width, -ClipboardRowMetrics.maximumHorizontalDrag), ClipboardRowMetrics.maximumHorizontalDrag)
    }

    private var actionProgress: Double {
        min(abs(horizontalDragOffset) / ClipboardRowMetrics.deleteThreshold, 1)
    }

    private var dragActionBackdrop: some View {
        HStack {
            if horizontalDragOffset > 0 {
                if allowsBookmarkSwipe {
                    actionIcon(for: .bookmark)
                        .padding(.leading, 16)
                }

                Spacer()
            } else {
                Spacer()

                actionIcon(for: .delete)
                    .padding(.trailing, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(backdropColor.opacity(0.10 + (0.24 * actionProgress)))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(backdropColor.opacity(0.22 + (0.25 * actionProgress)), lineWidth: 0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
        }
        .opacity(isDragging && abs(horizontalDragOffset) > 8 ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: horizontalDragOffset)
    }

    private var backdropColor: Color {
        horizontalDragOffset > 0 ? .accentColor : .red
    }

    private func actionIcon(for action: ClipboardRowSwipeAction) -> some View {
        let isTarget = swipeAction == action

        return Image(systemName: isTarget ? action.activeSystemImage : action.systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background {
                Circle()
                    .fill(action.color)
                    .shadow(color: action.color.opacity(isTarget ? 0.75 : 0.32), radius: isTarget ? 12 : 4)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                    }
            }
            .scaleEffect(isTarget ? 1.08 : 1)
            .opacity(0.55 + (0.45 * actionProgress))
            .animation(.easeOut(duration: 0.12), value: isTarget)
    }
}

struct LongTermClipboardListView: View {
    @ObservedObject var store: LongTermClipboardStore
    let restore: (LongTermClipboardEntry) -> Void

    @State private var hoveredEntryID: LongTermClipboardEntry.ID?
    @State private var previewEntryID: LongTermClipboardEntry.ID?
    @State private var previewTask: Task<Void, Never>?
    @State private var dragState: ClipboardRowDragState?

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Saved Items",
                    systemImage: "bookmark",
                    description: Text("Save a recent item with a title to keep it across app launches.")
                )
                .padding()
                .glassSurface(material: .ultraThinMaterial)
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.entries) { entry in
                            ClipboardHistoryRow(
                                entry: entry.entry,
                                titleOverride: entry.displayTitle,
                                isSelected: store.selectedEntryID == entry.id,
                                isPanel: true,
                                dragTranslation: dragState(for: entry.id)?.translation ?? .zero,
                                isDragging: dragState?.id == entry.id,
                                swipeAction: swipeAction(for: entry)
                            )
                            .contentShape(Rectangle())
                            .simultaneousGesture(reorderGesture(for: entry))
                            .onTapGesture {
                                restore(entry)
                            }
                            .onHover { isHovering in
                                updateHover(entry: entry, isHovering: isHovering)
                                if isHovering {
                                    store.selectedEntryID = entry.id
                                }
                            }
                            .popover(isPresented: detailPreviewBinding(for: entry)) {
                                ClipboardDetailPreviewPopover(entry: entry.entry)
                            }
                            .contextMenu {
                                Button {
                                    _ = store.restoreToSystemClipboard(entry)
                                } label: {
                                    Label("Restore to Clipboard", systemImage: "doc.on.clipboard")
                                }

                                Button(role: .destructive) {
                                    store.delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button(role: .destructive) {
                                    store.clear()
                                } label: {
                                    Label("Clear Saved", systemImage: "trash.slash")
                                }
                            }
                            .zIndex(dragState?.id == entry.id ? 1 : 0)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func updateHover(entry: LongTermClipboardEntry, isHovering: Bool) {
        previewTask?.cancel()

        if isHovering {
            hoveredEntryID = entry.id
            scheduleDetailPreview(for: entry)
        } else if hoveredEntryID == entry.id {
            hoveredEntryID = nil
            previewEntryID = nil
        }
    }

    private func scheduleDetailPreview(for entry: LongTermClipboardEntry) {
        previewTask?.cancel()
        guard dragState?.id != entry.id else {
            previewEntryID = nil
            return
        }

        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled,
                  hoveredEntryID == entry.id,
                  dragState?.id != entry.id else {
                return
            }
            previewEntryID = entry.id
        }
    }

    private func dragState(for id: LongTermClipboardEntry.ID) -> ClipboardRowDragState? {
        dragState?.id == id ? dragState : nil
    }

    private func reorderGesture(for entry: LongTermClipboardEntry) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                updateDrag(entry: entry, translation: value.translation)
            }
            .onEnded { value in
                finishDrag(entry: entry, translation: value.translation)
            }
    }

    private func updateDrag(entry: LongTermClipboardEntry, translation: CGSize) {
        previewTask?.cancel()
        previewEntryID = nil
        hoveredEntryID = entry.id
        store.selectedEntryID = entry.id

        var nextState: ClipboardRowDragState
        if let currentState = dragState, currentState.id == entry.id {
            nextState = currentState
            nextState.translation = translation
        } else {
            nextState = ClipboardRowDragState(
                id: entry.id,
                startIndex: store.entries.firstIndex(where: { $0.id == entry.id }) ?? 0,
                translation: translation
            )
        }
        dragState = nextState

        guard abs(translation.height) > abs(translation.width) * 0.75 else {
            return
        }

        let targetIndex = reorderTargetIndex(
            startIndex: nextState.startIndex,
            translation: translation.height,
            count: store.entries.count
        )

        withAnimation(.easeInOut(duration: 0.16)) {
            store.move(entry, to: targetIndex)
        }
    }

    private func finishDrag(entry: LongTermClipboardEntry, translation: CGSize) {
        var state = dragState ?? ClipboardRowDragState(
            id: entry.id,
            startIndex: store.entries.firstIndex(where: { $0.id == entry.id }) ?? 0,
            translation: translation
        )
        state.translation = translation

        withAnimation(.easeOut(duration: 0.18)) {
            if state.swipeAction(allowsBookmark: false) == .delete {
                store.delete(entry)
            }
            dragState = nil
        }
    }

    private func swipeAction(for entry: LongTermClipboardEntry) -> ClipboardRowSwipeAction? {
        dragState(for: entry.id)?.swipeAction(allowsBookmark: false)
    }

    private func detailPreviewBinding(for entry: LongTermClipboardEntry) -> Binding<Bool> {
        Binding {
            previewEntryID == entry.id
        } set: { isPresented in
            if !isPresented, previewEntryID == entry.id {
                previewEntryID = nil
            }
        }
    }
}

private struct ClipboardDetailPreviewPopover: View {
    let entry: ClipboardHistoryEntry

    var body: some View {
        let image = entry.previewContentImage
        let text = entry.detailText

        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7)
                    }
            }

            if let text {
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: image == nil ? 220 : 150)
            } else if image == nil {
                Text("No preview available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
        }
        .padding(12)
        .frame(width: image == nil ? 300 : 324)
        .glassSurface(cornerRadius: 14, material: .regularMaterial)
    }
}

private extension ClipboardHistoryEntry {
    var previewContentImage: NSImage? {
        items.lazy.compactMap(\.renderedImage).first
    }

    var detailText: String? {
        if case .fileURLs(let paths) = preview {
            return paths.joined(separator: "\n")
        }

        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .string,
            .URL,
            .fileURL,
            .html,
            .rtf
        ]

        for type in preferredTypes {
            if let text = items.lazy.compactMap({ $0.string(for: type) }).first,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.clippedForClipboardPreview
            }
        }

        for representation in items.flatMap(\.representations) where representation.isLikelyText {
            if let text = String(data: representation.data, encoding: .utf8)
                ?? String(data: representation.data, encoding: .utf16),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.clippedForClipboardPreview
            }
        }

        return nil
    }
}

private extension ClipboardRepresentation {
    var isLikelyText: Bool {
        let lowercaseType = type.lowercased()
        return lowercaseType.contains("text")
            || lowercaseType.contains("string")
            || lowercaseType.contains("html")
            || lowercaseType.contains("json")
            || lowercaseType.contains("xml")
            || lowercaseType.contains("url")
            || lowercaseType.contains("rtf")
    }
}

private extension String {
    var clippedForClipboardPreview: String {
        let limit = 20_000
        guard count > limit else {
            return self
        }

        return String(prefix(limit)) + "\n..."
    }
}

private struct ClipboardPreviewIcon: View {
    let entry: ClipboardHistoryEntry
    let isSelected: Bool
    let isPanel: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(iconBackground)

            if let image = entry.thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: GlassmorphismStyle.iconCornerRadius, style: .continuous))
            } else {
                Image(systemName: entry.preview.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected && isPanel ? .white : .secondary)
            }
        }
        .frame(width: 34, height: 34)
        .overlay {
            RoundedRectangle(cornerRadius: GlassmorphismStyle.iconCornerRadius, style: .continuous)
                .strokeBorder(iconBorder, lineWidth: 0.6)
        }
    }

    private var iconBackground: AnyShapeStyle {
        if isSelected && isPanel {
            return AnyShapeStyle(Color.white.opacity(0.20))
        }

        return AnyShapeStyle(Material.ultraThinMaterial)
    }

    private var iconBorder: Color {
        if isSelected && isPanel {
            return Color.white.opacity(0.22)
        }

        return Color.secondary.opacity(0.16)
    }
}
