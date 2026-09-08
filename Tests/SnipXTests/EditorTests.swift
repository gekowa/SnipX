import XCTest
import AppKit
@testable import SnipX

final class EditorTests: XCTestCase {
    @MainActor private func fixture(width: Int = 960, height: Int = 560) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.23, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        "A little clarity.\nA lot of possibility.".draw(at: CGPoint(x: 70, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 46, weight: .semibold), .foregroundColor: NSColor.white])
        "SNIPX  /  CAPTURE WHAT MATTERS".draw(at: CGPoint(x: 74, y: 465), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.systemTeal])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    func testAnnotationsUndoRedoAndRasterExport() async throws {
        try await MainActor.run {
            let source = fixture()
            let canvas = AnnotationCanvas(image: source)
            for (index, tool) in AnnotationTool.allCases.enumerated() {
                canvas.append(Annotation(tool: tool, points: [CGPoint(x: 50 + index * 95, y: 400), CGPoint(x: 100 + index * 95, y: 470)], color: .systemRed, width: tool == .text || tool == .step ? 32 : 5, text: tool == .step ? "1" : "标注"))
            }
            XCTAssertTrue(canvas.canUndo); XCTAssertFalse(canvas.canRedo)
            let withAll = try canvas.flattened()
            canvas.undoAnnotation(); XCTAssertTrue(canvas.canRedo)
            canvas.redoAnnotation(); XCTAssertFalse(canvas.canRedo)
            XCTAssertEqual(NSBitmapImageRep(cgImage: withAll).representation(using: .png, properties: [:]),
                           NSBitmapImageRep(cgImage: try canvas.flattened()).representation(using: .png, properties: [:]))
            for _ in AnnotationTool.allCases { canvas.undoAnnotation() }
            XCTAssertFalse(canvas.canUndo)
            XCTAssertEqual(NSBitmapImageRep(cgImage: try canvas.flattened()).colorAt(x: 60, y: 430),
                           NSBitmapImageRep(cgImage: source).colorAt(x: 60, y: 430))
        }
    }
    func testToolbarLayoutAndGeneratePreview() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let editor = EditorController(image: fixture())
            editor.present()
            defer { editor.close() }
            editor.canvas.append(Annotation(tool: .rectangle, points: [CGPoint(x: 58, y: 130), CGPoint(x: 620, y: 265)], color: .systemTeal, width: 4))
            editor.canvas.append(Annotation(tool: .arrow, points: [CGPoint(x: 735, y: 340), CGPoint(x: 650, y: 255)], color: .systemOrange, width: 5))
            let root = try XCTUnwrap(editor.window?.contentView)
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            let toolbar = try XCTUnwrap(root.subviews.compactMap { $0 as? NSStackView }.first { stack in
                stack.arrangedSubviews.filter { ($0 as? NSButton)?.isBordered == false }.count > 10
            })
            XCTAssertTrue(root.bounds.contains(toolbar.frame))
            XCTAssertEqual(toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.count, 14)
            for button in toolbar.arrangedSubviews.compactMap({ $0 as? NSButton }) {
                XCTAssertNotNil(button.image); XCTAssertFalse(button.toolTip?.isEmpty ?? true)
                XCTAssertGreaterThan(button.frame.width, 30)
            }
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/Users/xhguo/Workspace/0.FUN/SnipX/.build/editor-preview.png"))
        }
    }
    func testFlattenPreservesResolutionAndOrientation() async throws {
        try await MainActor.run {
            let width = 120, height = 90
            let pixels = (0..<(width * height)).flatMap { index -> [UInt8] in
                index / width < 30 ? [255, 0, 0, 255] : [0, 0, 255, 255]
            }
            let source = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let canvas = AnnotationCanvas(image: source)
            canvas.setFrameSize(CGSize(width: 60, height: 45)); canvas.setBoundsSize(CGSize(width: width, height: height))
            let rendered = try canvas.flattened()
            XCTAssertEqual(rendered.width, width); XCTAssertEqual(rendered.height, height)
            let rep = NSBitmapImageRep(cgImage: rendered)
            let top = try XCTUnwrap(rep.colorAt(x: 20, y: 10)?.usingColorSpace(.deviceRGB))
            let bottom = try XCTUnwrap(rep.colorAt(x: 20, y: 80)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(top.redComponent, 0.95); XCTAssertLessThan(top.blueComponent, 0.05)
            XCTAssertGreaterThan(bottom.blueComponent, 0.95); XCTAssertLessThan(bottom.redComponent, 0.05)
        }
    }
}
