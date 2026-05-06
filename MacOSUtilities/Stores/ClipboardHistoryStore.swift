import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let defaultMaxHistoryLength = 30
    static let maxHistoryLengthRange = 1...500

    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var maxHistoryLength = defaultMaxHistoryLength
    @Published var selectedEntryID: ClipboardHistoryEntry.ID?

    var selectedEntry: ClipboardHistoryEntry? {
        guard let selectedEntryID else {
            return entries.first
        }

        return entries.first { $0.id == selectedEntryID } ?? entries.first
    }

    static func clampedMaxHistoryLength(_ value: Int) -> Int {
        min(max(value, maxHistoryLengthRange.lowerBound), maxHistoryLengthRange.upperBound)
    }

    func updateMaxHistoryLength(_ value: Int) {
        maxHistoryLength = Self.clampedMaxHistoryLength(value)
        pruneEntries()
    }

    func capture(from reader: PasteboardReading) {
        addStoredItems(reader.readStoredItems())
    }

    func addStoredItems(_ items: [ClipboardStoredItem], capturedAt: Date = Date()) {
        guard !items.isEmpty else {
            return
        }

        add(ClipboardHistoryEntry(capturedAt: capturedAt, items: items))
    }

    func add(_ entry: ClipboardHistoryEntry) {
        if let existingIndex = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            entries.remove(at: existingIndex)
        }

        entries.insert(entry, at: 0)
        pruneEntries()

        if selectedEntryID == nil || !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = entries.first?.id
        }
    }

    func clear() {
        entries.removeAll()
        selectedEntryID = nil
    }

    func delete(_ entry: ClipboardHistoryEntry) {
        entries.removeAll { $0.id == entry.id }

        if selectedEntryID == entry.id {
            selectedEntryID = entries.first?.id
        }
    }

    func move(_ entry: ClipboardHistoryEntry, to targetIndex: Int) {
        guard let sourceIndex = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        let destinationIndex = min(max(targetIndex, 0), entries.count - 1)
        guard sourceIndex != destinationIndex else {
            return
        }

        let movedEntry = entries.remove(at: sourceIndex)
        entries.insert(movedEntry, at: min(destinationIndex, entries.count))
        selectedEntryID = movedEntry.id
    }

    @discardableResult
    func restore(_ entry: ClipboardHistoryEntry, to writer: PasteboardWriting) -> Bool {
        writer.writeStoredItems(entry.items)
    }

    @discardableResult
    func restoreToSystemClipboard(_ entry: ClipboardHistoryEntry) -> Bool {
        restore(entry, to: SystemPasteboard())
    }

    @discardableResult
    func restoreSelectedToSystemClipboard() -> Bool {
        guard let selectedEntry else {
            return false
        }

        return restoreToSystemClipboard(selectedEntry)
    }

    func selectFirst() {
        selectedEntryID = entries.first?.id
    }

    func selectNext() {
        guard !entries.isEmpty else {
            selectedEntryID = nil
            return
        }

        guard let selectedEntryID,
              let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else {
            self.selectedEntryID = entries.first?.id
            return
        }

        let nextIndex = min(index + 1, entries.count - 1)
        self.selectedEntryID = entries[nextIndex].id
    }

    func selectPrevious() {
        guard !entries.isEmpty else {
            selectedEntryID = nil
            return
        }

        guard let selectedEntryID,
              let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else {
            self.selectedEntryID = entries.first?.id
            return
        }

        let previousIndex = max(index - 1, 0)
        self.selectedEntryID = entries[previousIndex].id
    }

    private func pruneEntries() {
        if entries.count > maxHistoryLength {
            entries.removeLast(entries.count - maxHistoryLength)
        }

        if let selectedEntryID,
           !entries.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = entries.first?.id
        }
    }
}

extension ClipboardHistoryStore {
    static var previewStore: ClipboardHistoryStore {
        let store = ClipboardHistoryStore()
        store.addStoredItems([
            ClipboardStoredItem(representations: [
                ClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data("A useful snippet copied from another app".utf8)
                )
            ])
        ])
        store.addStoredItems([
            ClipboardStoredItem(representations: [
                ClipboardRepresentation(
                    type: "public.url",
                    data: Data("https://example.com".utf8)
                )
            ])
        ])
        return store
    }
}
