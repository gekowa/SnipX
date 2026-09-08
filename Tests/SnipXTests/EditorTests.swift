import XCTest
import AppKit
@testable import SnipX

final class EditorTests: XCTestCase {
    func testHoverCursorMatchesDragAndOptionDrawing() async throws {
        await MainActor.run {
            _ = NSApplication.shared
            let canvas = AnnotationCanvas(image: fixture())
            canvas.append(Annotation(tool: .rectangle, points: [CGPoint(x: 40, y: 40), CGPoint(x: 140, y: 100)], color: .red, width: 5))
            @MainActor func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: flags,
                                   timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
            }
            NSCursor.arrow.set()
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 40, y: 60)))
            XCTAssertEqual(NSCursor.current, NSCursor.openHand)
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 40, y: 60)))
            XCTAssertEqual(NSCursor.current, NSCursor.closedHand)
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 40, y: 60)))
            XCTAssertEqual(NSCursor.current, NSCursor.openHand)
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 40, y: 60), flags: .option))
            XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 80, y: 70)))
            XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
            canvas.tool = .text
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 80, y: 70)))
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 40, y: 60)))
            XCTAssertEqual(NSCursor.current, NSCursor.openHand)
            let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            canvas.mouseExited(with: exit)
            XCTAssertEqual(NSCursor.current, NSCursor.arrow)
        }
    }
    func testMoveAnnotationsAndPanAtDifferentZooms() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let canvas = AnnotationCanvas(image: fixture())
            let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
            let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll; scroll.documentView = canvas
            defer { window.close() }
            @MainActor func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            for zoom: CGFloat in [0.5, 1, 2] {
                canvas.setFrameSize(CGSize(width: 960 * zoom, height: 560 * zoom))
                canvas.setBoundsSize(CGSize(width: 960, height: 560))
                scroll.contentView.scroll(to: .zero)
                let item = Annotation(tool: .rectangle, points: [CGPoint(x: 40, y: 40), CGPoint(x: 140, y: 100)], color: .red, width: 5)
                canvas.append(item)
                let before = try canvas.flattened()
                let start = canvas.convert(CGPoint(x: 40, y: 60), to: nil)
                let end = canvas.convert(CGPoint(x: 60, y: 75), to: nil)
                canvas.mouseDown(with: event(.leftMouseDown, start))
                canvas.mouseDragged(with: event(.leftMouseDragged, end))
                canvas.mouseUp(with: event(.leftMouseUp, end))
                XCTAssertEqual(canvas.annotations.last?.points, [CGPoint(x: 60, y: 55), CGPoint(x: 160, y: 115)])
                canvas.undoAnnotation()
                XCTAssertEqual(canvas.annotations.last?.points, item.points)
                XCTAssertEqual(NSBitmapImageRep(cgImage: before).representation(using: .png, properties: [:]),
                               NSBitmapImageRep(cgImage: try canvas.flattened()).representation(using: .png, properties: [:]))
                canvas.redoAnnotation()
                XCTAssertEqual(canvas.annotations.last?.points.first, CGPoint(x: 60, y: 55))
                canvas.undoAnnotation(); canvas.undoAnnotation()
                let origin = scroll.contentView.bounds.origin
                canvas.rightMouseDown(with: event(.rightMouseDown, CGPoint(x: 150, y: 100)))
                canvas.rightMouseDragged(with: event(.rightMouseDragged, CGPoint(x: 120, y: 120)))
                canvas.rightMouseUp(with: event(.rightMouseUp, CGPoint(x: 120, y: 120)))
                XCTAssertEqual(scroll.contentView.bounds.origin.x, origin.x + 30, accuracy: 0.01)
                XCTAssertEqual(scroll.contentView.bounds.origin.y, origin.y + 20, accuracy: 0.01)
                XCTAssertTrue(canvas.annotations.isEmpty)
            }
        }
    }

    func testHitTestingAndOptionDrawing() async throws {
        await MainActor.run {
            let canvas = AnnotationCanvas(image: fixture())
            for tool in AnnotationTool.allCases {
                canvas.append(Annotation(tool: tool, points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)], color: .red, width: 10, text: "测试"))
                let hit = tool == .oval ? CGPoint(x: 150, y: 100) : CGPoint(x: 100, y: 100)
                XCTAssertEqual(canvas.annotationIndex(at: hit), canvas.annotations.count - 1, "\(tool)")
            }
            XCTAssertNil(canvas.annotationIndex(at: CGPoint(x: 400, y: 400)))
            let point = canvas.convert(CGPoint(x: 100, y: 100), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
            canvas.mouseDown(with: down); canvas.mouseUp(with: up)
            XCTAssertEqual(canvas.annotations.count, AnnotationTool.allCases.count + 1)
            XCTAssertEqual(canvas.annotations.last?.tool, .pen)
            canvas.undoAnnotation()
            canvas.append(Annotation(tool: .step, points: [.zero], color: .red, width: 20, text: "1"))
            XCTAssertFalse(canvas.canRedo)
        }
    }
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
