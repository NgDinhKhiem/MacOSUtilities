import AppKit
import SwiftUI

enum ScreenshotTextMetrics {
    static let textPadding = CGSize(width: 10, height: 8)
    static let minimumEditorSize = CGSize(width: 74, height: 34)

    static func font(for textFont: ScreenshotTextFont, size: CGFloat) -> NSFont {
        let clampedSize = ScreenshotAnnotation.clampedTextSize(size)

        switch textFont {
        case .rounded:
            return NSFont.systemFont(ofSize: clampedSize, weight: .semibold)
        case .system:
            return NSFont.systemFont(ofSize: clampedSize, weight: .semibold)
        case .serif:
            return NSFont(name: "Times New Roman Bold", size: clampedSize)
                ?? NSFont.systemFont(ofSize: clampedSize, weight: .semibold)
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: clampedSize, weight: .semibold)
        }
    }

    static func editorSize(
        for text: String,
        textSize: CGFloat,
        textFont: ScreenshotTextFont,
        maxWidth: CGFloat = ScreenshotAnnotation.maxTextWidth
    ) -> CGSize {
        measuredSize(
            for: text.isEmpty ? " " : text,
            textSize: textSize,
            textFont: textFont,
            maxWidth: maxWidth
        )
    }

    static func bounds(for annotation: ScreenshotAnnotation) -> CGRect? {
        guard annotation.kind == .text,
              let point = annotation.points.first else {
            return nil
        }

        let size = measuredSize(
            for: annotation.text,
            textSize: annotation.textSize,
            textFont: annotation.textFont,
            maxWidth: ScreenshotAnnotation.maxTextWidth,
            includesEditorChrome: false
        )
        return CGRect(origin: point, size: size)
    }

    private static func measuredSize(
        for text: String,
        textSize: CGFloat,
        textFont: ScreenshotTextFont,
        maxWidth: CGFloat,
        includesEditorChrome: Bool = true
    ) -> CGSize {
        let padding = includesEditorChrome ? textPadding : .zero
        let minimumSize = includesEditorChrome ? minimumEditorSize : .zero
        let usableMaxWidth = max(1, maxWidth - padding.width)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: textFont, size: textSize),
            .paragraphStyle: paragraphStyle
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: usableMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return CGSize(
            width: min(
                maxWidth,
                max(minimumSize.width, ceil(bounds.width) + padding.width)
            ),
            height: max(minimumSize.height, ceil(bounds.height) + padding.height)
        )
    }
}
