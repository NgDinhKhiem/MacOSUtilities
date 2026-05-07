import AppKit
import SwiftUI

private enum ScreenshotDragMode {
    case create(start: CGPoint)
    case moveSelection(
        start: CGPoint,
        original: CGRect,
        originalAnnotations: [ScreenshotAnnotation],
        originalDraft: ScreenshotAnnotation?
    )
    case moveAnnotation(id: UUID, start: CGPoint, original: ScreenshotAnnotation)
    case annotate(start: CGPoint)
    case text(start: CGPoint)
    case textEditor
}

private struct ActiveScreenshotTextEdit {
    let id: UUID
    let isEditingExistingAnnotation: Bool
    var preferredOrigin: CGPoint
}

struct ScreenshotOverlayView: View {
    @ObservedObject var session: ScreenshotCaptureSession

    let copySelection: () -> Void
    let saveSelection: () -> Void
    let cancel: () -> Void

    @State private var dragMode: ScreenshotDragMode?
    @State private var hoveredAnnotationID: UUID?
    @State private var activeTextEdit: ActiveScreenshotTextEdit?
    @State private var textDraftText = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                captureSurface(in: proxy.size)

                topBadge
                    .padding(18)

                VStack {
                    Spacer()
                    if shouldShowTextFormattingBar {
                        textFormattingBar
                            .padding(.bottom, 6)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    toolbar
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
                .animation(.spring(response: 0.28, dampingFraction: 0.84), value: shouldShowTextFormattingBar)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onChange(of: textDraftText) { _, _ in
            updateTextDraftAnnotation()
        }
    }

    private func captureSurface(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: session.image)
                .resizable()
                .frame(width: size.width, height: size.height)

            dimmingLayer(size: size)

            if let selection = session.normalizedSelection {
                selectionContent(selection)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            handleHover(phase, in: size)
        }
        .gesture(captureGesture(in: size), including: .all)
        .simultaneousGesture(
            SpatialTapGesture(count: 2, coordinateSpace: .local)
                .onEnded { value in
                    handleDoubleClick(at: value.location, in: size)
                }
        )
    }

    private func dimmingLayer(size: CGSize) -> some View {
        let bounds = CGRect(origin: .zero, size: size)

        return Path { path in
            path.addRect(bounds)
            if let selection = session.normalizedSelection {
                path.addRoundedRect(
                    in: selection,
                    cornerSize: CGSize(width: 8, height: 8)
                )
            }
        }
        .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
    }

    private func selectionContent(_ selection: CGRect) -> some View {
        let displayedAnnotations = annotationsForDisplay

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.96),
                            Color.white.opacity(0.72),
                            Color.orange.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.35), lineWidth: 4)
                }

            ScreenshotAnnotationLayer(
                annotations: displayedAnnotations,
                selectionOrigin: selection.origin,
                selectedAnnotationID: highlightedAnnotationID
            )
            .frame(width: selection.width, height: selection.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let activeTextEdit {
                textDraftEditor(selection: selection, edit: activeTextEdit)
            }

            selectionHandles
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
    }

    private func textDraftEditor(selection: CGRect, edit: ActiveScreenshotTextEdit) -> some View {
        let frame = textEditorFrame(for: edit, in: selection)

        return ScreenshotTextDraftEditor(
            text: $textDraftText,
            color: session.selectedColor,
            width: frame.width,
            height: frame.height,
            textSize: session.selectedTextSize,
            textFont: session.selectedTextFont,
            confirmCopy: confirmCopy,
            confirmSave: confirmSave,
            cancel: cancelTextDraft
        )
        .position(x: frame.midX - selection.minX, y: frame.midY - selection.minY)
    }

    private var selectionHandles: some View {
        GeometryReader { proxy in
            ZStack {
                handleCircle
                    .position(x: 0, y: 0)
                handleCircle
                    .position(x: proxy.size.width, y: 0)
                handleCircle
                    .position(x: 0, y: proxy.size.height)
                handleCircle
                    .position(x: proxy.size.width, y: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var handleCircle: some View {
        Circle()
            .fill(.thinMaterial)
            .overlay {
                Circle()
                    .fill(Color.orange.opacity(0.52))
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
            }
            .frame(width: 10, height: 10)
            .shadow(color: .orange.opacity(0.42), radius: 6)
    }

    private var topBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .glassIconTile(tint: .orange)

            Text(session.normalizedSelection == nil ? "Drag a capture area" : "\(Int(session.normalizedSelection?.width ?? 0)) x \(Int(session.normalizedSelection?.height ?? 0))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(8)
        .glassSurface(cornerRadius: 15, material: .thinMaterial, tint: .orange, isInteractive: true)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotTool.allCases) { tool in
                Button {
                    selectTool(tool)
                } label: {
                    Image(systemName: tool.systemImage)
                }
                .buttonStyle(
                    GlassIconButtonStyle(
                        tint: tool == .select ? .accentColor : .orange,
                        size: 32,
                        isProminent: session.selectedTool == tool
                    )
                )
                .disabled(session.normalizedSelection == nil && tool != .select)
                .help(tool.helpText)
            }

            divider

            ForEach(ScreenshotMarkupColor.allCases) { color in
                Button {
                    selectColor(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.62), lineWidth: 0.8)
                        }
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(
                    GlassIconButtonStyle(
                        tint: color.color,
                        size: 26,
                        isProminent: session.selectedColor == color
                    )
                )
                .disabled(session.normalizedSelection == nil)
                .help(color.displayName)
            }

            divider

            Button {
                undoLastAnnotation()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(GlassIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor), size: 32))
            .disabled(session.annotations.isEmpty && activeTextEdit == nil)
            .help("Undo")

            Button {
                confirmCopy()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .orange, size: 34, isProminent: true))
            .disabled(session.normalizedSelection == nil)
            .help("Copy")

            Button {
                confirmSave()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .accentColor, size: 34, isProminent: true))
            .disabled(session.normalizedSelection == nil)
            .help("Save")

            Button {
                discard()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .red, size: 32))
            .help("Cancel")
        }
        .padding(8)
        .glassSurface(cornerRadius: 20, material: .thinMaterial, tint: .orange, isInteractive: true)
    }

    private var shouldShowTextFormattingBar: Bool {
        guard session.normalizedSelection != nil else {
            return false
        }

        return activeTextEdit != nil
            || session.selectedTool == .text
            || selectedAnnotation?.kind == .text
    }

    private var textFormattingBar: some View {
        ScreenshotTextFormattingBar(
            font: Binding {
                activeTextFont
            } set: { newFont in
                applyTextFont(newFont)
            },
            size: Binding {
                Double(activeTextSize)
            } set: { newSize in
                applyTextSize(CGFloat(newSize))
            }
        )
    }

    private var selectedAnnotation: ScreenshotAnnotation? {
        guard let selectedAnnotationID = session.selectedAnnotationID else {
            return nil
        }

        return session.annotations.first(where: { $0.id == selectedAnnotationID })
    }

    private var highlightedAnnotationID: UUID? {
        hoveredAnnotationID ?? session.selectedAnnotationID
    }

    private var activeTextFont: ScreenshotTextFont {
        if activeTextEdit != nil,
           let draftAnnotation = session.draftAnnotation,
           draftAnnotation.kind == .text {
            return draftAnnotation.textFont
        }

        if let selectedAnnotation,
           selectedAnnotation.kind == .text {
            return selectedAnnotation.textFont
        }

        return session.selectedTextFont
    }

    private var activeTextSize: CGFloat {
        if activeTextEdit != nil,
           let draftAnnotation = session.draftAnnotation,
           draftAnnotation.kind == .text {
            return draftAnnotation.textSize
        }

        if let selectedAnnotation,
           selectedAnnotation.kind == .text {
            return selectedAnnotation.textSize
        }

        return session.selectedTextSize
    }

    private var divider: some View {
        Capsule()
            .fill(Color.white.opacity(0.20))
            .frame(width: 1, height: 24)
    }

    private func captureGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                updateDrag(value, in: size)
            }
            .onEnded { value in
                finishDrag(value, in: size)
            }
    }

    private func updateDrag(_ value: DragGesture.Value, in size: CGSize) {
        let start = clampedPoint(value.startLocation, in: size)
        let location = clampedPoint(value.location, in: size)

        if dragMode == nil {
            dragMode = makeDragMode(start: start)
        }

        switch dragMode {
        case .create(let start):
            session.selection = clampedRect(rect(from: start, to: location), in: size)
            session.draftAnnotation = nil
            session.selectedAnnotationID = nil
        case .moveSelection(let start, let original, let originalAnnotations, let originalDraft):
            let offset = CGSize(width: location.x - start.x, height: location.y - start.y)
            let movedSelection = clampedRect(original.offsetBy(dx: offset.width, dy: offset.height), in: size)
            let actualOffset = CGSize(
                width: movedSelection.minX - original.minX,
                height: movedSelection.minY - original.minY
            )

            session.selection = movedSelection
            session.annotations = originalAnnotations.map {
                $0.withOffset(dx: actualOffset.width, dy: actualOffset.height)
            }
            session.draftAnnotation = originalDraft?.withOffset(dx: actualOffset.width, dy: actualOffset.height)
        case .moveAnnotation(let id, let start, let original):
            NSCursor.closedHand.set()
            guard let selection = session.normalizedSelection else {
                return
            }

            let offset = CGSize(width: location.x - start.x, height: location.y - start.y)
            let movedAnnotation = original.clampedInside(selection, afterOffset: offset)
            replaceAnnotation(id: id, with: movedAnnotation)
        case .annotate(let start):
            updateDraftAnnotation(start: start, location: location)
        case .text:
            break
        case .textEditor:
            break
        case nil:
            break
        }
    }

    private func finishDrag(_ value: DragGesture.Value, in size: CGSize) {
        if case .annotate = dragMode,
           let draftAnnotation = session.draftAnnotation,
           draftAnnotation.isRenderable {
            session.draftAnnotation = nil
            session.annotations.append(draftAnnotation)
            selectAnnotation(draftAnnotation)
        }

        if case .text(let start) = dragMode {
            beginTextDraft(at: start)
        }

        if let selection = session.normalizedSelection,
           selection.width < 8 || selection.height < 8 {
            session.selection = nil
        }

        if activeTextEdit == nil,
           session.draftAnnotation?.kind != .text {
            session.draftAnnotation = nil
        }
        dragMode = nil
        if hoveredAnnotationID == nil {
            NSCursor.arrow.set()
        } else {
            NSCursor.openHand.set()
        }
    }

    private func makeDragMode(start: CGPoint) -> ScreenshotDragMode {
        if let activeTextEdit {
            if let selection = session.normalizedSelection,
               textEditorFrame(for: activeTextEdit, in: selection).contains(start) {
                return .textEditor
            }

            commitTextDraft()
        }

        guard let selection = session.normalizedSelection else {
            return .create(start: start)
        }

        if let annotation = topAnnotation(at: start, in: selection) {
            selectAnnotation(annotation)
            hoveredAnnotationID = annotation.id
            NSCursor.closedHand.set()
            return .moveAnnotation(id: annotation.id, start: start, original: annotation)
        }

        if session.selectedTool == .select {
            session.selectedAnnotationID = nil
            hoveredAnnotationID = nil
            return selection.contains(start)
                ? .moveSelection(
                    start: start,
                    original: selection,
                    originalAnnotations: session.annotations,
                    originalDraft: session.draftAnnotation
                )
                : .create(start: start)
        }

        if session.selectedTool == .text {
            session.selectedAnnotationID = nil
            hoveredAnnotationID = nil
            return selection.contains(start) ? .text(start: start) : .create(start: start)
        }

        session.selectedAnnotationID = nil
        hoveredAnnotationID = nil
        return selection.contains(start) ? .annotate(start: start) : .create(start: start)
    }

    private func handleHover(_ phase: HoverPhase, in size: CGSize) {
        guard activeTextEdit == nil,
              dragMode == nil,
              let selection = session.normalizedSelection else {
            if dragMode == nil {
                hoveredAnnotationID = nil
            }
            return
        }

        switch phase {
        case .active(let location):
            let point = clampedPoint(location, in: size)
            let hoveredAnnotation = topAnnotation(at: point, in: selection)
            hoveredAnnotationID = hoveredAnnotation?.id

            if hoveredAnnotation == nil {
                NSCursor.arrow.set()
            } else {
                NSCursor.openHand.set()
            }
        case .ended:
            hoveredAnnotationID = nil
            NSCursor.arrow.set()
        }
    }

    private func handleDoubleClick(at location: CGPoint, in size: CGSize) {
        guard activeTextEdit == nil,
              let selection = session.normalizedSelection else {
            return
        }

        let point = clampedPoint(location, in: size)
        guard let annotation = topAnnotation(at: point, in: selection),
              annotation.kind == .text else {
            return
        }

        beginEditingText(annotation)
    }

    private func updateDraftAnnotation(start: CGPoint, location: CGPoint) {
        let kind: ScreenshotAnnotation.Kind
        switch session.selectedTool {
        case .pen:
            kind = .pen
        case .rectangle:
            kind = .rectangle
        case .arrow:
            kind = .arrow
        case .text:
            return
        case .select:
            return
        }

        var points: [CGPoint]
        if kind == .pen {
            points = session.draftAnnotation?.points ?? [start]
            if let lastPoint = points.last,
               hypot(location.x - lastPoint.x, location.y - lastPoint.y) > 1.5 {
                points.append(location)
            }
        } else {
            points = [start, location]
        }

        session.draftAnnotation = ScreenshotAnnotation(
            kind: kind,
            points: points,
            color: session.selectedColor
        )
    }

    private func selectTool(_ tool: ScreenshotTool) {
        if ScreenshotSessionCommandPolicy.shouldCommitTextBeforeToolSwitch(activeTextEdit: activeTextEdit != nil) {
            commitTextDraft()
        }

        if tool != .select {
            session.selectedAnnotationID = nil
        }

        session.selectedTool = tool
    }

    private func confirmCopy() {
        perform(.confirmCopy)
    }

    private func confirmSave() {
        perform(.confirmSave)
    }

    private func discard() {
        perform(.discard)
    }

    private func perform(_ command: ScreenshotSessionCommand) {
        switch command {
        case .cancelActiveText:
            cancelTextDraft()
        case .discard:
            cancel()
        case .confirmCopy:
            commitTextDraft()
            copySelection()
        case .confirmSave:
            commitTextDraft()
            saveSelection()
        case .selectFullScreen:
            commitTextDraft()
            session.selectFullScreen()
        case .passThrough:
            break
        }
    }

    private func selectColor(_ color: ScreenshotMarkupColor) {
        session.selectedColor = color
        if activeTextEdit != nil {
            updateTextDraftAnnotation()
            return
        }

        if let selectedAnnotationID = session.selectedAnnotationID {
            updateAnnotation(id: selectedAnnotationID) { annotation in
                annotation.color = color
            }
        }
        updateTextDraftAnnotation()
    }

    private func undoLastAnnotation() {
        if activeTextEdit != nil {
            cancelTextDraft()
        } else if !session.annotations.isEmpty {
            session.annotations.removeLast()
        }
    }

    private func beginTextDraft(at point: CGPoint) {
        commitTextDraft()
        session.selectedAnnotationID = nil
        let id = UUID()
        activeTextEdit = ActiveScreenshotTextEdit(
            id: id,
            isEditingExistingAnnotation: false,
            preferredOrigin: point
        )
        textDraftText = ""
        session.draftAnnotation = ScreenshotAnnotation(
            id: id,
            kind: .text,
            points: [point],
            color: session.selectedColor,
            lineWidth: 0,
            textSize: session.selectedTextSize,
            textFont: session.selectedTextFont
        )
    }

    private func beginEditingText(_ annotation: ScreenshotAnnotation) {
        guard let point = annotation.points.first else {
            return
        }

        commitTextDraft()
        session.selectedAnnotationID = annotation.id
        session.selectedColor = annotation.color
        session.selectedTextSize = annotation.textSize
        session.selectedTextFont = annotation.textFont
        activeTextEdit = ActiveScreenshotTextEdit(
            id: annotation.id,
            isEditingExistingAnnotation: true,
            preferredOrigin: point
        )
        textDraftText = annotation.text
        updateTextDraftAnnotation()
    }

    private func commitTextDraft() {
        guard let activeTextEdit else {
            return
        }

        updateTextDraftAnnotation()
        guard let draftAnnotation = session.draftAnnotation,
              draftAnnotation.kind == .text else {
            clearTextDraft()
            return
        }

        if draftAnnotation.isRenderable {
            replaceOrAppendTextAnnotation(draftAnnotation)
            selectAnnotation(draftAnnotation)
        } else if activeTextEdit.isEditingExistingAnnotation {
            removeAnnotation(id: activeTextEdit.id)
            session.selectedAnnotationID = nil
        }

        session.draftAnnotation = nil
        clearTextDraft()
    }

    private func cancelTextDraft() {
        let cancelledEdit = activeTextEdit
        if session.draftAnnotation?.kind == .text {
            session.draftAnnotation = nil
        }

        clearTextDraft()
        if cancelledEdit?.isEditingExistingAnnotation == true {
            session.selectedAnnotationID = cancelledEdit?.id
        }
    }

    private func clearTextDraft() {
        activeTextEdit = nil
        textDraftText = ""
    }

    private func updateTextDraftAnnotation() {
        guard let activeTextEdit else {
            return
        }

        let origin = resolvedTextOrigin(for: activeTextEdit)
        session.draftAnnotation = ScreenshotAnnotation(
            id: activeTextEdit.id,
            kind: .text,
            points: [origin],
            color: session.selectedColor,
            lineWidth: 0,
            text: textDraftText,
            textSize: session.selectedTextSize,
            textFont: session.selectedTextFont
        )
    }

    private func applyTextFont(_ font: ScreenshotTextFont) {
        session.selectedTextFont = font

        if activeTextEdit != nil {
            updateTextDraftAnnotation()
            return
        }

        guard let selectedAnnotationID = session.selectedAnnotationID else {
            return
        }

        updateAnnotation(id: selectedAnnotationID) { annotation in
            guard annotation.kind == .text else {
                return
            }

            annotation.textFont = font
        }
    }

    private func applyTextSize(_ size: CGFloat) {
        let clampedSize = ScreenshotAnnotation.clampedTextSize(size)
        session.selectedTextSize = clampedSize

        if activeTextEdit != nil {
            updateTextDraftAnnotation()
            return
        }

        guard let selectedAnnotationID = session.selectedAnnotationID else {
            return
        }

        updateAnnotation(id: selectedAnnotationID) { annotation in
            guard annotation.kind == .text else {
                return
            }

            annotation.textSize = clampedSize
        }
    }

    private func selectAnnotation(_ annotation: ScreenshotAnnotation) {
        session.selectedAnnotationID = annotation.id
        session.selectedColor = annotation.color

        if annotation.kind == .text {
            session.selectedTextSize = annotation.textSize
            session.selectedTextFont = annotation.textFont
        }
    }

    private func topAnnotation(at point: CGPoint, in selection: CGRect) -> ScreenshotAnnotation? {
        session.annotations.reversed().first { annotation in
            guard annotation.isRenderable,
                  let bounds = annotation.approximateBounds else {
                return false
            }

            let hitBounds = bounds
                .intersection(selection)
                .insetBy(dx: -10, dy: -10)
            return hitBounds.contains(point)
        }
    }

    private func replaceAnnotation(id: UUID, with replacement: ScreenshotAnnotation) {
        guard let index = session.annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        session.annotations[index] = replacement
    }

    private func updateAnnotation(id: UUID, update: (inout ScreenshotAnnotation) -> Void) {
        guard let index = session.annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&session.annotations[index])
    }

    private var annotationsForDisplay: [ScreenshotAnnotation] {
        guard let activeTextEdit else {
            return session.exportAnnotations
        }

        return session.annotations.filter { $0.id != activeTextEdit.id }
    }

    private func replaceOrAppendTextAnnotation(_ annotation: ScreenshotAnnotation) {
        if let index = session.annotations.firstIndex(where: { $0.id == annotation.id }) {
            session.annotations[index] = annotation
        } else {
            session.annotations.append(annotation)
        }
    }

    private func removeAnnotation(id: UUID) {
        session.annotations.removeAll { $0.id == id }
    }

    private func resolvedTextOrigin(for edit: ActiveScreenshotTextEdit) -> CGPoint {
        guard let selection = session.normalizedSelection else {
            return edit.preferredOrigin
        }

        return textEditorFrame(for: edit, in: selection).origin
    }

    private func textEditorFrame(for edit: ActiveScreenshotTextEdit, in selection: CGRect) -> CGRect {
        let inset: CGFloat = 6
        let maxWidth = max(
            ScreenshotTextMetrics.minimumEditorSize.width,
            min(ScreenshotAnnotation.maxTextWidth, selection.width - inset * 2)
        )
        let size = ScreenshotTextMetrics.editorSize(
            for: textDraftText,
            textSize: activeTextSize,
            textFont: activeTextFont,
            maxWidth: maxWidth
        )
        let maxX = max(selection.minX + inset, selection.maxX - size.width - inset)
        let maxY = max(selection.minY + inset, selection.maxY - size.height - inset)
        let origin = CGPoint(
            x: min(max(edit.preferredOrigin.x, selection.minX + inset), maxX),
            y: min(max(edit.preferredOrigin.y, selection.minY + inset), maxY)
        )

        return CGRect(origin: origin, size: size)
    }

    private func clampedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func clampedRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let normalized = rect.normalizedForScreenshot
        let width = min(normalized.width, size.width)
        let height = min(normalized.height, size.height)
        let x = min(max(normalized.minX, 0), max(size.width - width, 0))
        let y = min(max(normalized.minY, 0), max(size.height - height, 0))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
