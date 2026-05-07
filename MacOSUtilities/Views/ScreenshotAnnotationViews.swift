import AppKit
import SwiftUI

struct ScreenshotAnnotationLayer: View {
    let annotations: [ScreenshotAnnotation]
    let selectionOrigin: CGPoint
    var selectedAnnotationID: UUID? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(annotations) { annotation in
                ZStack(alignment: .topLeading) {
                    if annotation.id == selectedAnnotationID {
                        selectionHighlight(annotation)
                    }

                    annotationView(annotation)
                }
            }
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: ScreenshotAnnotation) -> some View {
        switch annotation.kind {
        case .text:
            textAnnotation(annotation)
        case .pen, .rectangle, .arrow:
            ScreenshotAnnotationShape(
                annotation: annotation,
                selectionOrigin: selectionOrigin
            )
            .stroke(
                annotation.color.color,
                style: StrokeStyle(
                    lineWidth: annotation.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        }
    }

    private func textAnnotation(_ annotation: ScreenshotAnnotation) -> some View {
        Group {
            if let point = annotation.points.first,
               !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(annotation.text)
                    .font(.system(size: annotation.textSize, weight: .semibold, design: annotation.textFont.design))
                    .foregroundStyle(annotation.color.color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: ScreenshotAnnotation.maxTextWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.72), radius: 3, x: 0, y: 1)
                    .offset(
                        x: point.x - selectionOrigin.x,
                        y: point.y - selectionOrigin.y
                    )
            }
        }
    }

    @ViewBuilder
    private func selectionHighlight(_ annotation: ScreenshotAnnotation) -> some View {
        switch annotation.kind {
        case .text:
            if let bounds = annotation.approximateBounds {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.2)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    }
                    .frame(width: bounds.width + 10, height: bounds.height + 8)
                    .offset(x: bounds.minX - selectionOrigin.x - 5, y: bounds.minY - selectionOrigin.y - 4)
                    .shadow(color: .orange.opacity(0.40), radius: 8)
            }
        case .pen, .rectangle, .arrow:
            ScreenshotAnnotationShape(
                annotation: annotation,
                selectionOrigin: selectionOrigin
            )
            .stroke(
                Color.white.opacity(0.85),
                style: StrokeStyle(
                    lineWidth: annotation.lineWidth + 5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(color: .orange.opacity(0.55), radius: 8)
        }
    }
}

struct ScreenshotTextDraftEditor: View {
    @Binding var text: String
    let color: ScreenshotMarkupColor
    let width: CGFloat
    let height: CGFloat
    let textSize: CGFloat
    let textFont: ScreenshotTextFont
    let confirmCopy: () -> Void
    let confirmSave: () -> Void
    let cancel: () -> Void

    var body: some View {
        ScreenshotTransparentTextView(
            text: $text,
            color: color.nsColor,
            font: ScreenshotTextMetrics.font(for: textFont, size: textSize),
            confirmCopy: confirmCopy,
            confirmSave: confirmSave,
            cancel: cancel
        )
        .frame(width: width, height: height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.72), radius: 3, x: 0, y: 1)
    }
}

private struct ScreenshotTransparentTextView: NSViewRepresentable {
    @Binding var text: String
    let color: NSColor
    let font: NSFont
    let confirmCopy: () -> Void
    let confirmSave: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> ScreenshotTextView {
        let textView = ScreenshotTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = CGSize(width: 5, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.menu = nil
        textView.onConfirmCopy = confirmCopy
        textView.onConfirmSave = confirmSave
        textView.onCancel = cancel
        return textView
    }

    func updateNSView(_ textView: ScreenshotTextView, context: Context) {
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        textView.textColor = color
        textView.insertionPointColor = color
        textView.font = font
        textView.onConfirmCopy = confirmCopy
        textView.onConfirmSave = confirmSave
        textView.onCancel = cancel

        DispatchQueue.main.async {
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ textView: ScreenshotTextView, coordinator: Coordinator) {
        if textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScreenshotTransparentTextView

        init(parent: ScreenshotTransparentTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
        }
    }
}

private final class ScreenshotTextView: NSTextView {
    var onConfirmCopy: (() -> Void)?
    var onConfirmSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let commandPressed = event.modifierFlags.contains(.command)

        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            onCancel?()
            return
        }

        if isReturn {
            switch ScreenshotSessionCommandPolicy.returnKey(activeTextEdit: true, commandPressed: commandPressed) {
            case .confirmCopy:
                window?.makeFirstResponder(nil)
                onConfirmCopy?()
                return
            case .passThrough:
                break
            case .cancelActiveText, .discard, .confirmSave, .selectFullScreen:
                break
            }
        }

        if event.keyCode == 8 && commandPressed {
            window?.makeFirstResponder(nil)
            onConfirmCopy?()
            return
        }

        if event.keyCode == 1 && commandPressed {
            window?.makeFirstResponder(nil)
            onConfirmSave?()
            return
        }

        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }
}

struct ScreenshotTextFormattingBar: View {
    @Binding var font: ScreenshotTextFont
    @Binding var size: Double

    var body: some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(ScreenshotTextFont.allCases) { option in
                    Button {
                        font = option
                    } label: {
                        Label(option.displayName, systemImage: option == font ? "checkmark" : "textformat")
                    }
            }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "textformat")
                        .font(.system(size: 11, weight: .semibold))
                    Text(font.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .buttonStyle(GlassPillButtonStyle(tint: .orange, horizontalPadding: 8))
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)

            Image(systemName: "textformat.size.smaller")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(
                value: $size,
                in: Double(ScreenshotAnnotation.minTextSize)...Double(ScreenshotAnnotation.maxTextSize),
                step: 1
            )
            .controlSize(.small)
            .frame(width: 84)

            Text("\(Int(size))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 22, alignment: .trailing)
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .glassSurface(cornerRadius: 13, material: .thinMaterial, tint: .orange, isInteractive: true)
    }
}

extension ScreenshotAnnotation {
    func withOffset(dx: CGFloat, dy: CGFloat) -> ScreenshotAnnotation {
        var annotation = self
        annotation.offsetBy(dx: dx, dy: dy)
        return annotation
    }

    func clampedInside(_ selection: CGRect, afterOffset offset: CGSize) -> ScreenshotAnnotation {
        var adjustedOffset = offset

        if let bounds = approximateBounds {
            let movedBounds = bounds.offsetBy(dx: offset.width, dy: offset.height)
            if movedBounds.width <= selection.width {
                if movedBounds.minX < selection.minX {
                    adjustedOffset.width += selection.minX - movedBounds.minX
                } else if movedBounds.maxX > selection.maxX {
                    adjustedOffset.width -= movedBounds.maxX - selection.maxX
                }
            }

            if movedBounds.height <= selection.height {
                if movedBounds.minY < selection.minY {
                    adjustedOffset.height += selection.minY - movedBounds.minY
                } else if movedBounds.maxY > selection.maxY {
                    adjustedOffset.height -= movedBounds.maxY - selection.maxY
                }
            }
        }

        return withOffset(dx: adjustedOffset.width, dy: adjustedOffset.height)
    }
}

struct ScreenshotAnnotationShape: Shape {
    let annotation: ScreenshotAnnotation
    let selectionOrigin: CGPoint

    func path(in rect: CGRect) -> Path {
        switch annotation.kind {
        case .pen:
            return penPath()
        case .rectangle:
            return rectanglePath()
        case .arrow:
            return arrowPath()
        case .text:
            return Path()
        }
    }

    private func penPath() -> Path {
        var path = Path()
        let localPoints = annotation.points.map(localPoint)

        guard let firstPoint = localPoints.first else {
            return path
        }

        path.move(to: firstPoint)
        for point in localPoints.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    private func rectanglePath() -> Path {
        guard let firstPoint = annotation.points.first,
              let lastPoint = annotation.points.last else {
            return Path()
        }

        let start = localPoint(firstPoint)
        let end = localPoint(lastPoint)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
        return path
    }

    private func arrowPath() -> Path {
        guard let firstPoint = annotation.points.first,
              let lastPoint = annotation.points.last else {
            return Path()
        }

        let start = localPoint(firstPoint)
        let end = localPoint(lastPoint)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 18
        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        path.move(to: end)
        path.addLine(to: left)
        path.move(to: end)
        path.addLine(to: right)
        return path
    }

    private func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - selectionOrigin.x,
            y: point.y - selectionOrigin.y
        )
    }
}
