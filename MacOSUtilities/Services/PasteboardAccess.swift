import AppKit
import Foundation

@MainActor
protocol PasteboardReading {
    var changeCount: Int { get }
    func readStoredItems() -> [ClipboardStoredItem]
}

@MainActor
protocol PasteboardWriting {
    @discardableResult
    func writeStoredItems(_ items: [ClipboardStoredItem]) -> Bool
}

@MainActor
struct SystemPasteboard: PasteboardReading, PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readStoredItems() -> [ClipboardStoredItem] {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return []
        }

        return pasteboardItems.compactMap { pasteboardItem in
            let representations = pasteboardItem.types.compactMap { type -> ClipboardRepresentation? in
                if let data = pasteboardItem.data(forType: type) {
                    return ClipboardRepresentation(type: type.rawValue, data: data)
                }

                if let value = pasteboardItem.string(forType: type),
                   let data = value.data(using: .utf8) {
                    return ClipboardRepresentation(type: type.rawValue, data: data)
                }

                return nil
            }

            guard !representations.isEmpty else {
                return nil
            }

            return ClipboardStoredItem(representations: representations)
        }
    }

    @discardableResult
    func writeStoredItems(_ items: [ClipboardStoredItem]) -> Bool {
        let pasteboardItems = items.map { storedItem in
            let item = NSPasteboardItem()

            for representation in storedItem.representations {
                let pasteboardType = NSPasteboard.PasteboardType(representation.type)

                if pasteboardType == .string,
                   let value = String(data: representation.data, encoding: .utf8) {
                    item.setString(value, forType: pasteboardType)
                } else {
                    item.setData(representation.data, forType: pasteboardType)
                }
            }

            return item
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects(pasteboardItems)
    }
}
