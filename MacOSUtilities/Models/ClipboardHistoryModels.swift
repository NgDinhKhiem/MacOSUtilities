import AppKit
import CryptoKit
import Foundation

struct ClipboardRepresentation: Identifiable, Hashable, Codable {
    var id: String { type }

    let type: String
    let data: Data
}

struct ClipboardStoredItem: Identifiable, Hashable, Codable {
    let id: UUID
    let representations: [ClipboardRepresentation]

    init(id: UUID = UUID(), representations: [ClipboardRepresentation]) {
        self.id = id
        self.representations = representations
    }

    var byteCount: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }

    var orderedTypeNames: [String] {
        representations.map(\.type)
    }

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        representations.first { $0.type == type.rawValue }?.data
    }

    func string(for type: NSPasteboard.PasteboardType) -> String? {
        guard let data = data(for: type) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16BigEndian)
    }

    var renderedImage: NSImage? {
        for representation in representations where representation.representsImage {
            if let image = NSImage(data: representation.data) {
                return image
            }
        }

        return nil
    }
}

struct ClipboardHistoryEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let capturedAt: Date
    let preview: ClipboardPreview
    let fingerprint: String
    let items: [ClipboardStoredItem]

    init(id: UUID = UUID(), capturedAt: Date = Date(), items: [ClipboardStoredItem]) {
        self.id = id
        self.capturedAt = capturedAt
        self.items = items
        self.preview = ClipboardPreview.make(from: items)
        self.fingerprint = Self.makeFingerprint(for: items)
    }

    var itemCount: Int {
        items.count
    }

    var totalByteCount: Int {
        items.reduce(0) { $0 + $1.byteCount }
    }

    var orderedTypeNames: [String] {
        items.flatMap(\.orderedTypeNames)
    }

    var thumbnailImage: NSImage? {
        if let image = items.lazy.compactMap(\.renderedImage).first {
            return image
        }

        guard case .fileURLs(let paths) = preview,
              let firstPath = paths.first else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: firstPath)
    }

    private static func makeFingerprint(for items: [ClipboardStoredItem]) -> String {
        var hasher = SHA256()

        for item in items {
            hasher.update(data: Data([0x1F]))

            for representation in item.representations {
                hasher.update(data: Data(representation.type.utf8))
                hasher.update(data: Data([0x1E]))
                hasher.update(data: representation.data)
                hasher.update(data: Data([0x1D]))
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ClipboardHistoryEntry {
    private enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        let items = try container.decode([ClipboardStoredItem].self, forKey: .items)

        self.id = id
        self.capturedAt = capturedAt
        self.items = items
        self.preview = ClipboardPreview.make(from: items)
        self.fingerprint = Self.makeFingerprint(for: items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(items, forKey: .items)
    }
}

struct LongTermClipboardEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    let savedAt: Date
    let entry: ClipboardHistoryEntry

    init(id: UUID = UUID(), title: String, savedAt: Date = Date(), entry: ClipboardHistoryEntry) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.savedAt = savedAt
        self.entry = entry
    }

    var displayTitle: String {
        title.isEmpty ? entry.preview.title : title
    }

    var hasCustomTitle: Bool {
        !title.isEmpty
    }
}

enum ClipboardPreview: Hashable {
    case text(String)
    case richText(String)
    case image(width: Int?, height: Int?)
    case fileURLs([String])
    case url(String)
    case unknown(typeNames: [String], itemCount: Int, byteCount: Int)

    var title: String {
        switch self {
        case .text(let value):
            return value.normalizedClipboardLine.emptyFallback("Text")
        case .richText(let format):
            return "\(format) Rich Text"
        case .image(let width, let height):
            if let width, let height {
                return "Image \(width)x\(height)"
            }
            return "Image"
        case .fileURLs(let paths):
            if paths.count == 1 {
                return URL(fileURLWithPath: paths[0]).lastPathComponent.emptyFallback("File")
            }
            return "\(paths.count) Files"
        case .url(let url):
            return url.normalizedClipboardLine.emptyFallback("URL")
        case .unknown(_, let itemCount, _):
            return itemCount == 1 ? "Clipboard Item" : "\(itemCount) Clipboard Items"
        }
    }

    var subtitle: String {
        switch self {
        case .text(let value):
            return value.normalizedClipboardLine
        case .richText(let format):
            return format
        case .image(let width, let height):
            if let width, let height {
                return "\(width) by \(height) pixels"
            }
            return "Bitmap data"
        case .fileURLs(let paths):
            return paths.prefix(2).map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }.joined(separator: ", ")
        case .url(let url):
            return url
        case .unknown(let typeNames, _, let byteCount):
            let typeSummary = typeNames.prefix(3).joined(separator: ", ")
            return "\(typeSummary)\(typeNames.count > 3 ? ", ..." : "") - \(byteCount.formatted()) bytes"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .richText:
            return "doc.richtext"
        case .image:
            return "photo"
        case .fileURLs:
            return "doc.on.doc"
        case .url:
            return "link"
        case .unknown:
            return "clipboard"
        }
    }

    var typeLabel: String {
        switch self {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .fileURLs:
            return "Files"
        case .url:
            return "URL"
        case .unknown:
            return "Data"
        }
    }

    static func make(from items: [ClipboardStoredItem]) -> ClipboardPreview {
        if let fileURLs = fileURLs(from: items), !fileURLs.isEmpty {
            return .fileURLs(fileURLs.map(\.path))
        }

        if let text = firstString(for: .string, in: items), !text.normalizedClipboardLine.isEmpty {
            return .text(text)
        }

        if let urlString = firstURLString(in: items) {
            return .url(urlString)
        }

        if let imageSize = firstImageSize(in: items) {
            return .image(width: imageSize.width, height: imageSize.height)
        }

        if containsType(.html, in: items) {
            return .richText("HTML")
        }

        if containsType(.rtf, in: items) {
            return .richText("RTF")
        }

        let typeNames = items.flatMap(\.orderedTypeNames)
        let byteCount = items.reduce(0) { $0 + $1.byteCount }
        return .unknown(typeNames: typeNames, itemCount: items.count, byteCount: byteCount)
    }

    private static func firstString(for type: NSPasteboard.PasteboardType, in items: [ClipboardStoredItem]) -> String? {
        items.lazy.compactMap { $0.string(for: type) }.first
    }

    private static func containsType(_ type: NSPasteboard.PasteboardType, in items: [ClipboardStoredItem]) -> Bool {
        items.contains { item in
            item.representations.contains { $0.type == type.rawValue }
        }
    }

    private static func firstURLString(in items: [ClipboardStoredItem]) -> String? {
        for item in items {
            if let data = item.data(for: .URL),
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url.absoluteString
            }

            if let value = item.string(for: .URL), URL(string: value) != nil {
                return value
            }
        }

        return nil
    }

    private static func fileURLs(from items: [ClipboardStoredItem]) -> [URL]? {
        let urls = items.compactMap { item -> URL? in
            if let data = item.data(for: .fileURL),
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.isFileURL {
                return url
            }

            if let value = item.string(for: .fileURL),
               let url = URL(string: value),
               url.isFileURL {
                return url
            }

            return nil
        }

        return urls.isEmpty ? nil : urls
    }

    private static func firstImageSize(in items: [ClipboardStoredItem]) -> (width: Int, height: Int)? {
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]

        for item in items {
            for type in imageTypes {
                guard let data = item.data(for: type),
                      let image = NSImage(data: data) else {
                    continue
                }

                return (
                    width: Int(image.size.width.rounded()),
                    height: Int(image.size.height.rounded())
                )
            }
        }

        return nil
    }
}

private extension ClipboardRepresentation {
    var representsImage: Bool {
        let imageTypeNames: Set<String> = [
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            "public.jpeg",
            "public.jpg",
            "public.heic",
            "public.heif",
            "public.bmp",
            "public.webp",
            "com.compuserve.gif"
        ]

        return imageTypeNames.contains(type) || type.localizedCaseInsensitiveContains("image")
    }
}

private extension String {
    var normalizedClipboardLine: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func emptyFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
