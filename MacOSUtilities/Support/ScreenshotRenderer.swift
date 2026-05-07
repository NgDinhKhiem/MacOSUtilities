import AppKit
import SwiftUI

@MainActor
enum ScreenshotRenderer {
    static func render(session: ScreenshotCaptureSession) -> NSImage? {
        guard let selection = session.normalizedSelection,
              selection.width >= 2,
              selection.height >= 2 else {
            return nil
        }

        let renderer = ImageRenderer(
            content: ScreenshotExportView(
                image: session.image,
                screenSize: session.screenSize,
                selection: selection,
                annotations: session.exportAnnotations
            )
        )
        renderer.scale = session.pixelScale
        return renderer.nsImage
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct ScreenshotExportView: View {
    let image: NSImage
    let screenSize: CGSize
    let selection: CGRect
    let annotations: [ScreenshotAnnotation]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: screenSize.width, height: screenSize.height)
                .offset(x: -selection.minX, y: -selection.minY)

            ScreenshotAnnotationLayer(
                annotations: annotations,
                selectionOrigin: selection.origin
            )
        }
        .frame(width: selection.width, height: selection.height, alignment: .topLeading)
        .clipped()
    }
}
