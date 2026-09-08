import XCTest
import AppKit
import ScreenCaptureKit
@testable import SnipX

final class SelectionViewTests: XCTestCase {
    func testMouseReleaseWaitsForConfirmationAndExportsAdjustedCrop() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let screen = try XCTUnwrap(NSScreen.main)
            let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let view = SelectionView(image: try XCTUnwrap(context.makeImage()), screenFrame: screen.frame, candidates: [], primaryHeight: screen.frame.height, mode: .region)
            let window = OverlayWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            defer { window.close() }
            var images: [CGImage] = []
            var scrollingRegions: [CGRect] = []
            view.onScrollingRegion = { scrollingRegions.append($0) }
            view.onComplete = { if case .image(let image) = $0 { images.append(image) } }
            @MainActor func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                                                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1))
            }
            let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: window.windowNumber, context: nil, characters: "\r",
                                                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            XCTAssertTrue(view.handleSelectionKey(enter))
            XCTAssertTrue(images.isEmpty)
            view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 50, y: 60)))
            view.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 250, y: 200)))
            XCTAssertTrue(images.isEmpty, "Releasing the initial selection must not open the editor")
            view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 250, y: 200)))
            view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 280, y: 220)))
            XCTAssertTrue(view.handleSelectionKey(enter))
            XCTAssertTrue(images.isEmpty, "Confirmation must not interrupt an active resize")
            view.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 280, y: 220)))
            XCTAssertTrue(images.isEmpty)
            XCTAssertTrue(view.handleSelectionKey(enter))
            XCTAssertEqual(images.count, 1)
            XCTAssertEqual(images.first?.width, 460)
            XCTAssertEqual(images.first?.height, 320)
            view.mode = .scrolling
            XCTAssertTrue(view.handleSelectionKey(enter))
            XCTAssertTrue(scrollingRegions.isEmpty, "Changing mode must clear the previous selection")
            view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 40, y: 40)))
            view.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 200, y: 180)))
            XCTAssertTrue(scrollingRegions.isEmpty)
            XCTAssertTrue(view.handleSelectionKey(enter))
            XCTAssertEqual(scrollingRegions, [CGRect(x: 40, y: 40, width: 160, height: 140)])
        }
    }
}
