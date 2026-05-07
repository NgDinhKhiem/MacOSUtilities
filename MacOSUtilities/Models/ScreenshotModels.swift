import AppKit
import SwiftUI

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case select
    case pen
    case rectangle
    case arrow
    case text

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .select:
            return "selection.pin.in.out"
        case .pen:
            return "pencil.tip"
        case .rectangle:
            return "rectangle"
        case .arrow:
            return "arrow.up.right"
        case .text:
            return "textformat"
        }
    }

    var helpText: String {
        switch self {
        case .select:
            return "Select or move capture area"
        case .pen:
            return "Draw freehand"
        case .rectangle:
            return "Draw rectangle"
        case .arrow:
            return "Draw arrow"
        case .text:
            return "Add text"
        }
    }
}

enum ScreenshotMarkupColor: String, CaseIterable, Identifiable {
    case orange
    case white
    case black
    case red
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .orange:
            return .orange
        case .white:
            return .white
        case .black:
            return .black
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .blue:
            return .blue
        case .purple:
            return .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .orange:
            return .systemOrange
        case .white:
            return .white
        case .black:
            return .black
        case .red:
            return .systemRed
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .blue:
            return .systemBlue
        case .purple:
            return .systemPurple
        }
    }
}

enum ScreenshotTextFont: String, CaseIterable, Identifiable {
    case rounded
    case system
    case serif
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rounded:
            return "Rounded"
        case .system:
            return "System"
        case .serif:
            return "Serif"
        case .mono:
            return "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .rounded:
            return .rounded
        case .system:
            return .default
        case .serif:
            return .serif
        case .mono:
            return .monospaced
        }
    }
}

enum ScreenshotSessionCommand: Equatable {
    case cancelActiveText
    case discard
    case confirmCopy
    case confirmSave
    case selectFullScreen
    case passThrough
}

enum ScreenshotSessionCommandPolicy {
    static func escape(activeTextEdit: Bool) -> ScreenshotSessionCommand {
        activeTextEdit ? .cancelActiveText : .discard
    }

    static func returnKey(activeTextEdit: Bool, commandPressed: Bool) -> ScreenshotSessionCommand {
        if activeTextEdit {
            return commandPressed ? .confirmCopy : .passThrough
        }

        return .confirmCopy
    }

    static func saveShortcut() -> ScreenshotSessionCommand {
        .confirmSave
    }

    static func copyShortcut() -> ScreenshotSessionCommand {
        .confirmCopy
    }

    static func selectAllShortcut(activeTextEdit: Bool) -> ScreenshotSessionCommand {
        activeTextEdit ? .passThrough : .selectFullScreen
    }

    static func shouldCommitTextBeforeToolSwitch(activeTextEdit: Bool) -> Bool {
        activeTextEdit
    }
}

struct ScreenshotAnnotation: Identifiable {
    static let defaultTextSize: CGFloat = 18
    static let minTextSize: CGFloat = 11
    static let maxTextSize: CGFloat = 56
    static let maxTextWidth: CGFloat = 260

    enum Kind: Equatable {
        case pen
        case rectangle
        case arrow
        case text
    }

    let id: UUID
    var kind: Kind
    var points: [CGPoint]
    var color: ScreenshotMarkupColor
    var lineWidth: CGFloat
    var text: String
    var textSize: CGFloat
    var textFont: ScreenshotTextFont

    init(
        id: UUID = UUID(),
        kind: Kind,
        points: [CGPoint],
        color: ScreenshotMarkupColor,
        lineWidth: CGFloat = 3,
        text: String = "",
        textSize: CGFloat = ScreenshotAnnotation.defaultTextSize,
        textFont: ScreenshotTextFont = .rounded
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.textSize = ScreenshotAnnotation.clampedTextSize(textSize)
        self.textFont = textFont
    }

    var isRenderable: Bool {
        switch kind {
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && points.first != nil
        case .pen:
            return points.count >= 2
        case .rectangle, .arrow:
            return points.count >= 2
        }
    }

    var approximateBounds: CGRect? {
        switch kind {
        case .text:
            return ScreenshotTextMetrics.bounds(for: self)
        case .pen, .rectangle, .arrow:
            guard let firstPoint = points.first else {
                return nil
            }

            return points.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { partialResult, point in
                partialResult.union(CGRect(origin: point, size: .zero))
            }
            .insetBy(dx: -max(lineWidth, 8), dy: -max(lineWidth, 8))
        }
    }

    mutating func offsetBy(dx: CGFloat, dy: CGFloat) {
        points = points.map { point in
            CGPoint(x: point.x + dx, y: point.y + dy)
        }
    }

    static func clampedTextSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minTextSize), maxTextSize)
    }
}

@MainActor
final class ScreenshotCaptureSession: ObservableObject {
    let image: NSImage
    let screenFrame: NSRect
    let screenSize: CGSize
    let pixelScale: CGFloat

    @Published var selection: CGRect?
    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var draftAnnotation: ScreenshotAnnotation?
    @Published var selectedTool: ScreenshotTool = .select
    @Published var selectedColor: ScreenshotMarkupColor = .orange
    @Published var selectedTextFont: ScreenshotTextFont = .rounded
    @Published var selectedTextSize: CGFloat = ScreenshotAnnotation.defaultTextSize
    @Published var selectedAnnotationID: UUID?

    init(image: NSImage, screenFrame: NSRect, pixelWidth: Int) {
        self.image = image
        self.screenFrame = screenFrame
        self.screenSize = screenFrame.size
        self.pixelScale = max(CGFloat(pixelWidth) / max(screenFrame.width, 1), 1)
    }

    var normalizedSelection: CGRect? {
        selection?.normalizedForScreenshot
    }

    var exportAnnotations: [ScreenshotAnnotation] {
        if let draftAnnotation, draftAnnotation.isRenderable {
            if annotations.contains(where: { $0.id == draftAnnotation.id }) {
                return annotations
            }

            return annotations + [draftAnnotation]
        }

        return annotations
    }

    func clearAnnotations() {
        annotations.removeAll()
        draftAnnotation = nil
        selectedAnnotationID = nil
    }

    func selectFullScreen() {
        selection = CGRect(origin: .zero, size: screenSize)
        selectedTool = .select
        selectedAnnotationID = nil
    }
}

extension CGRect {
    var normalizedForScreenshot: CGRect {
        let x = min(minX, maxX)
        let y = min(minY, maxY)
        let width = abs(width)
        let height = abs(height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
