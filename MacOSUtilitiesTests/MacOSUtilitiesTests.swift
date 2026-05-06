import Testing
import AppKit
@testable import MacOSUtilities

struct MacOSUtilitiesTests {

    @MainActor
    @Test func storePrunesToMaxHistoryLength() {
        let store = ClipboardHistoryStore()
        store.updateMaxHistoryLength(3)

        for index in 0..<5 {
            store.add(makeEntry(text: "\(index)"))
        }

        #expect(store.entries.count == 3)
        #expect(store.entries.first?.preview.title == "4")
        #expect(store.entries.last?.preview.title == "2")
    }

    @MainActor
    @Test func storeDeduplicatesByFingerprintAndMovesNewestToTop() {
        let store = ClipboardHistoryStore()

        store.add(makeEntry(text: "same", capturedAt: Date(timeIntervalSince1970: 1)))
        store.add(makeEntry(text: "different", capturedAt: Date(timeIntervalSince1970: 2)))
        store.add(makeEntry(text: "same", capturedAt: Date(timeIntervalSince1970: 3)))

        #expect(store.entries.count == 2)
        #expect(store.entries.first?.preview.title == "same")
        #expect(store.entries.first?.capturedAt == Date(timeIntervalSince1970: 3))
    }

    @MainActor
    @Test func clearRemovesEntriesAndSelection() {
        let store = ClipboardHistoryStore()
        store.add(makeEntry(text: "hello"))

        store.clear()

        #expect(store.entries.isEmpty)
        #expect(store.selectedEntryID == nil)
    }

    @MainActor
    @Test func deleteRemovesOnlyRequestedEntry() {
        let store = ClipboardHistoryStore()
        let first = makeEntry(text: "first")
        let second = makeEntry(text: "second")
        store.add(first)
        store.add(second)
        store.selectedEntryID = first.id

        store.delete(first)

        #expect(store.entries.map(\.id) == [second.id])
        #expect(store.selectedEntryID == second.id)
    }

    @MainActor
    @Test func moveReordersSessionHistoryAndPreservesSelection() {
        let store = ClipboardHistoryStore()
        let first = makeEntry(text: "first")
        let second = makeEntry(text: "second")
        let third = makeEntry(text: "third")
        store.add(third)
        store.add(second)
        store.add(first)

        store.move(first, to: 2)

        #expect(store.entries.map(\.id) == [second.id, third.id, first.id])
        #expect(store.selectedEntryID == first.id)
    }

    @MainActor
    @Test func restoreWritesAllStoredRepresentations() {
        let store = ClipboardHistoryStore()
        let entry = ClipboardHistoryEntry(items: [
            ClipboardStoredItem(representations: [
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("hello".utf8)),
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>hello</b>".utf8))
            ])
        ])
        let writer = MockPasteboardWriter()

        #expect(store.restore(entry, to: writer))
        #expect(writer.items.count == 1)
        #expect(writer.items.first?.representations.map(\.type) == [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.html.rawValue
        ])
        #expect(writer.items.first?.representations.map(\.data) == [
            Data("hello".utf8),
            Data("<b>hello</b>".utf8)
        ])
    }

    @MainActor
    @Test func longTermStorePersistsEntriesWithTitleAndOriginalPayload() {
        let fileURL = temporaryLongTermStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = LongTermClipboardStore(fileURL: fileURL)
        let entry = makeEntry(text: "full copied value", capturedAt: Date(timeIntervalSince1970: 4))

        store.save(entry, title: "Named memory", savedAt: Date(timeIntervalSince1970: 5))

        let reloadedStore = LongTermClipboardStore(fileURL: fileURL)
        let reloadedEntry = reloadedStore.entries.first

        #expect(reloadedStore.entries.count == 1)
        #expect(reloadedEntry?.title == "Named memory")
        #expect(reloadedEntry?.displayTitle == "Named memory")
        #expect(reloadedEntry?.entry.preview.title == "full copied value")
        #expect(reloadedEntry?.entry.items == entry.items)
    }

    @MainActor
    @Test func longTermStoreDeduplicatesByClipboardFingerprint() {
        let fileURL = temporaryLongTermStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = LongTermClipboardStore(fileURL: fileURL)
        let entry = makeEntry(text: "same")

        store.save(entry, title: "First title", savedAt: Date(timeIntervalSince1970: 1))
        store.save(entry, title: "Second title", savedAt: Date(timeIntervalSince1970: 2))

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.title == "Second title")
        #expect(store.entries.first?.savedAt == Date(timeIntervalSince1970: 2))
    }

    @MainActor
    @Test func longTermMovePersistsManualOrder() {
        let fileURL = temporaryLongTermStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = LongTermClipboardStore(fileURL: fileURL)
        let first = store.save(makeEntry(text: "first"), title: "First")
        let second = store.save(makeEntry(text: "second"), title: "Second")
        let third = store.save(makeEntry(text: "third"), title: "Third")

        store.move(third, to: 2)

        let reloadedStore = LongTermClipboardStore(fileURL: fileURL)

        #expect(store.entries.map(\.id) == [second.id, first.id, third.id])
        #expect(reloadedStore.entries.map(\.id) == [second.id, first.id, third.id])
    }

    @MainActor
    @Test func movingToLongTermRemovesSessionHistoryEntry() {
        let fileURL = temporaryLongTermStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let historyStore = ClipboardHistoryStore()
        let longTermStore = LongTermClipboardStore(fileURL: fileURL)
        let entry = makeEntry(text: "keep this")
        historyStore.add(entry)

        longTermStore.save(entry, title: "Important")
        historyStore.delete(entry)

        #expect(historyStore.entries.isEmpty)
        #expect(longTermStore.entries.count == 1)
        #expect(longTermStore.entries.first?.displayTitle == "Important")
    }

    @MainActor
    @Test func longTermRestoreWritesOriginalStoredRepresentations() {
        let fileURL = temporaryLongTermStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = LongTermClipboardStore(fileURL: fileURL)
        let entry = ClipboardHistoryEntry(items: [
            ClipboardStoredItem(representations: [
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("hello".utf8)),
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.rtf.rawValue, data: Data("{\\rtf1 hello}".utf8))
            ])
        ])
        let longTermEntry = store.save(entry, title: "RTF sample")
        let writer = MockPasteboardWriter()

        #expect(store.restore(longTermEntry, to: writer))
        #expect(writer.items == entry.items)
    }

    private func makeEntry(text: String, capturedAt: Date = Date()) -> ClipboardHistoryEntry {
        ClipboardHistoryEntry(capturedAt: capturedAt, items: [
            ClipboardStoredItem(representations: [
                ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
            ])
        ])
    }

    private func temporaryLongTermStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}

@MainActor
private final class MockPasteboardWriter: PasteboardWriting {
    private(set) var items: [ClipboardStoredItem] = []

    func writeStoredItems(_ items: [ClipboardStoredItem]) -> Bool {
        self.items = items
        return true
    }
}
