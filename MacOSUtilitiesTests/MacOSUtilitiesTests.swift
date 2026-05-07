import Testing
import AppKit
import Carbon.HIToolbox
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

    @Test func screenshotSelectionNormalizesDraggedCoordinates() {
        let rect = CGRect(x: 120, y: 90, width: -44, height: -28).normalizedForScreenshot

        #expect(rect.origin == CGPoint(x: 76, y: 62))
        #expect(rect.size == CGSize(width: 44, height: 28))
    }

    @MainActor
    @Test func screenshotSessionExportsStoredAndDraftAnnotations() {
        let session = ScreenshotCaptureSession(
            image: NSImage(size: CGSize(width: 100, height: 80)),
            screenFrame: NSRect(x: 0, y: 0, width: 100, height: 80),
            pixelWidth: 200
        )
        let stored = ScreenshotAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 30)],
            color: .orange
        )
        let draft = ScreenshotAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 30, y: 25), CGPoint(x: 70, y: 55)],
            color: .red
        )

        session.annotations = [stored]
        session.draftAnnotation = draft

        #expect(session.pixelScale == 2)
        #expect(session.exportAnnotations.map(\.id) == [stored.id, draft.id])
    }

    @MainActor
    @Test func screenshotSessionDoesNotExportDuplicateDraftAnnotations() {
        let session = ScreenshotCaptureSession(
            image: NSImage(size: CGSize(width: 100, height: 80)),
            screenFrame: NSRect(x: 0, y: 0, width: 100, height: 80),
            pixelWidth: 100
        )
        let annotation = ScreenshotAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 30)],
            color: .orange
        )

        session.annotations = [annotation]
        session.draftAnnotation = annotation

        #expect(session.exportAnnotations.map(\.id) == [annotation.id])
    }

    @Test func screenshotTextSizeClampsToSupportedRange() {
        #expect(ScreenshotAnnotation.clampedTextSize(2) == ScreenshotAnnotation.minTextSize)
        #expect(ScreenshotAnnotation.clampedTextSize(500) == ScreenshotAnnotation.maxTextSize)
        #expect(ScreenshotAnnotation.clampedTextSize(24) == 24)
    }

    @Test func screenshotTextBoundsUseMeasuredFontMetrics() {
        let annotation = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 18, y: 24)],
            color: .orange,
            text: "Hello\nWorld",
            textSize: 22,
            textFont: .mono
        )

        let bounds = annotation.approximateBounds

        #expect(bounds?.origin == CGPoint(x: 18, y: 24))
        #expect((bounds?.width ?? 0) > 0)
        #expect((bounds?.width ?? 0) <= ScreenshotAnnotation.maxTextWidth)
        #expect((bounds?.height ?? 0) > ScreenshotTextMetrics.minimumEditorSize.height)
    }

    @Test func screenshotTextBoundsDoNotUseEditorMinimumHeight() {
        let annotation = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 18, y: 24)],
            color: .orange,
            text: "One line",
            textSize: 18,
            textFont: .system
        )

        let bounds = annotation.approximateBounds
        let editorSize = ScreenshotTextMetrics.editorSize(
            for: annotation.text,
            textSize: annotation.textSize,
            textFont: annotation.textFont
        )

        #expect((bounds?.height ?? 0) < editorSize.height)
    }

    @Test func screenshotTextEditorSizeClampsToMaximumWidth() {
        let size = ScreenshotTextMetrics.editorSize(
            for: String(repeating: "wide ", count: 80),
            textSize: 20,
            textFont: .system,
            maxWidth: 180
        )

        #expect(size.width <= 180)
        #expect(size.height > ScreenshotTextMetrics.minimumEditorSize.height)
    }

    @Test func screenshotMarkupPaletteOffersExpandedColorChoices() {
        #expect(ScreenshotMarkupColor.allCases == [
            .orange,
            .white,
            .black,
            .red,
            .yellow,
            .green,
            .blue,
            .purple
        ])
    }

    @Test func screenshotCommandPolicyCancelsTextBeforeDiscardingSession() {
        #expect(ScreenshotSessionCommandPolicy.escape(activeTextEdit: true) == .cancelActiveText)
        #expect(ScreenshotSessionCommandPolicy.escape(activeTextEdit: false) == .discard)
    }

    @Test func screenshotCommandPolicyKeepsPlainReturnInsideTextEditor() {
        #expect(
            ScreenshotSessionCommandPolicy.returnKey(
                activeTextEdit: true,
                commandPressed: false
            ) == .passThrough
        )
        #expect(
            ScreenshotSessionCommandPolicy.returnKey(
                activeTextEdit: true,
                commandPressed: true
            ) == .confirmCopy
        )
        #expect(
            ScreenshotSessionCommandPolicy.returnKey(
                activeTextEdit: false,
                commandPressed: false
            ) == .confirmCopy
        )
    }

    @Test func screenshotCommandPolicyUsesCommandShortcutsForCaptureActions() {
        #expect(ScreenshotSessionCommandPolicy.copyShortcut() == .confirmCopy)
        #expect(ScreenshotSessionCommandPolicy.selectAllShortcut(activeTextEdit: false) == .selectFullScreen)
        #expect(ScreenshotSessionCommandPolicy.selectAllShortcut(activeTextEdit: true) == .passThrough)
    }

    @Test func screenshotCommandPolicyCommitsTextBeforeToolSwitch() {
        #expect(ScreenshotSessionCommandPolicy.shouldCommitTextBeforeToolSwitch(activeTextEdit: true))
        #expect(!ScreenshotSessionCommandPolicy.shouldCommitTextBeforeToolSwitch(activeTextEdit: false))
    }

    @MainActor
    @Test func screenshotSessionExportsOnlyTextDraftsWithContent() {
        let session = ScreenshotCaptureSession(
            image: NSImage(size: CGSize(width: 100, height: 80)),
            screenFrame: NSRect(x: 0, y: 0, width: 100, height: 80),
            pixelWidth: 100
        )
        let emptyText = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 20, y: 20)],
            color: .white,
            text: "   "
        )
        let visibleText = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 20, y: 20)],
            color: .white,
            text: "Label"
        )

        session.draftAnnotation = emptyText
        #expect(session.exportAnnotations.isEmpty)

        session.draftAnnotation = visibleText
        #expect(session.exportAnnotations.map(\.id) == [visibleText.id])
    }

    @MainActor
    @Test func screenshotSessionCanSelectFullScreen() {
        let session = ScreenshotCaptureSession(
            image: NSImage(size: CGSize(width: 320, height: 200)),
            screenFrame: NSRect(x: 50, y: 80, width: 320, height: 200),
            pixelWidth: 640
        )
        session.selection = CGRect(x: 20, y: 30, width: 60, height: 70)
        session.selectedTool = .rectangle
        session.selectedAnnotationID = UUID()

        session.selectFullScreen()

        #expect(session.selection == CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(session.selectedTool == .select)
        #expect(session.selectedAnnotationID == nil)
    }

    @Test func captureHotKeyUsesFlameshotStylePreset() {
        let preset = CaptureHotKeyPreset.commandShiftX

        #expect(preset.displayName == "Command-Shift-X")
        #expect(preset.carbonKeyCode == UInt32(kVK_ANSI_X))
        #expect(preset.carbonModifiers == UInt32(cmdKey) | UInt32(shiftKey))
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
