import Foundation

@MainActor
final class LongTermClipboardStore: ObservableObject {
    @Published private(set) var entries: [LongTermClipboardEntry] = []
    @Published var selectedEntryID: LongTermClipboardEntry.ID?
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultStoreURL(fileManager: fileManager)
        load()
    }

    var selectedEntry: LongTermClipboardEntry? {
        guard let selectedEntryID else {
            return entries.first
        }

        return entries.first { $0.id == selectedEntryID } ?? entries.first
    }

    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupportURL
            .appendingPathComponent("MacOSUtilities", isDirectory: true)
            .appendingPathComponent("LongTermClipboard.json", isDirectory: false)
    }

    @discardableResult
    func save(_ entry: ClipboardHistoryEntry, title: String, savedAt: Date = Date()) -> LongTermClipboardEntry {
        let savedEntry = LongTermClipboardEntry(title: title, savedAt: savedAt, entry: entry)

        if let existingIndex = entries.firstIndex(where: { $0.entry.fingerprint == entry.fingerprint }) {
            let existingID = entries[existingIndex].id
            let updatedEntry = LongTermClipboardEntry(
                id: existingID,
                title: savedEntry.title,
                savedAt: savedAt,
                entry: entry
            )
            entries.remove(at: existingIndex)
            entries.insert(updatedEntry, at: 0)
            selectedEntryID = existingID
            persist()
            return updatedEntry
        }

        entries.insert(savedEntry, at: 0)
        selectedEntryID = savedEntry.id
        persist()
        return savedEntry
    }

    func updateTitle(for entry: LongTermClipboardEntry, title: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        entries[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func delete(_ entry: LongTermClipboardEntry) {
        entries.removeAll { $0.id == entry.id }

        if selectedEntryID == entry.id {
            selectedEntryID = entries.first?.id
        }

        persist()
    }

    func move(_ entry: LongTermClipboardEntry, to targetIndex: Int) {
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
        persist()
    }

    func clear() {
        entries.removeAll()
        selectedEntryID = nil
        persist()
    }

    @discardableResult
    func restore(_ entry: LongTermClipboardEntry, to writer: PasteboardWriting) -> Bool {
        writer.writeStoredItems(entry.entry.items)
    }

    @discardableResult
    func restoreToSystemClipboard(_ entry: LongTermClipboardEntry) -> Bool {
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

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            entries = []
            selectedEntryID = nil
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder.longTermClipboard.decode([LongTermClipboardEntry].self, from: data)
            selectedEntryID = entries.first?.id
            persistenceError = nil
        } catch {
            entries = []
            selectedEntryID = nil
            persistenceError = "Could not load long-term clipboard: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.longTermClipboard.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save long-term clipboard: \(error.localizedDescription)"
        }
    }
}

private extension JSONEncoder {
    static var longTermClipboard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var longTermClipboard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension LongTermClipboardStore {
    static var previewStore: LongTermClipboardStore {
        let store = LongTermClipboardStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.save(
            ClipboardHistoryEntry(items: [
                ClipboardStoredItem(representations: [
                    ClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data("A durable command or address worth keeping".utf8)
                    )
                ])
            ]),
            title: "Deployment snippet"
        )
        return store
    }
}
