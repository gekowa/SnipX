import XCTest
import CoreGraphics
@testable import SnipCore

final class AdjustableSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func selected() -> AdjustableSelection {
        var selection = AdjustableSelection()
        selection.begin(at: CGPoint(x: 50, y: 60))
        selection.update(to: CGPoint(x: 250, y: 200), within: bounds)
        selection.end()
        return selection
    }

    func testReleasePreservesSelectionForRepeatedAdjustments() {
        var selection = selected()
        XCTAssertTrue(selection.isValid)
        XCTAssertFalse(selection.isDragging)
        selection.begin(at: CGPoint(x: 120, y: 120))
        selection.update(to: CGPoint(x: 140, y: 130), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 70, y: 70, width: 200, height: 140))
        selection.begin(at: CGPoint(x: 270, y: 210))
        selection.update(to: CGPoint(x: 300, y: 240), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 70, y: 70, width: 230, height: 170))
    }

    func testEveryResizeHandleChangesOnlyItsEdges() {
        let expected: [AdjustableSelection.Handle: CGRect] = [
            .topLeft: CGRect(x: 60, y: 80, width: 190, height: 120),
            .top: CGRect(x: 50, y: 80, width: 200, height: 120),
            .topRight: CGRect(x: 50, y: 80, width: 210, height: 120),
            .right: CGRect(x: 50, y: 60, width: 210, height: 140),
            .bottomRight: CGRect(x: 50, y: 60, width: 210, height: 160),
            .bottom: CGRect(x: 50, y: 60, width: 200, height: 160),
            .bottomLeft: CGRect(x: 60, y: 60, width: 190, height: 160),
            .left: CGRect(x: 60, y: 60, width: 190, height: 140)
        ]
        for handle in AdjustableSelection.Handle.allCases {
            var selection = selected()
            let point = handle.position(in: selection.rect)
            selection.begin(at: point)
            selection.update(to: CGPoint(x: point.x + 10, y: point.y + 20), within: bounds)
            selection.end()
            XCTAssertEqual(selection.rect, expected[handle], "\(handle)")
        }
    }

    func testMoveClampsWithoutShrinking() {
        var selection = selected()
        selection.begin(at: CGPoint(x: 100, y: 100))
        selection.update(to: CGPoint(x: 1000, y: -1000), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 200, y: 0, width: 200, height: 140))
    }

    func testResizeClampsToScreenAndMinimumSize() {
        var selection = selected()
        selection.begin(at: CGPoint(x: 50, y: 60))
        selection.update(to: CGPoint(x: -100, y: -100), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 0, y: 0, width: 250, height: 200))
        selection.begin(at: CGPoint(x: 0, y: 0))
        selection.update(to: CGPoint(x: 400, y: 300), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 242, y: 192, width: 8, height: 8))
    }

    func testOutsideDragStartsNewSelectionAndTinyDragIsDiscarded() {
        var selection = selected()
        selection.begin(at: CGPoint(x: 390, y: 290))
        selection.update(to: CGPoint(x: 300, y: 220), within: bounds)
        selection.end()
        XCTAssertEqual(selection.rect, CGRect(x: 300, y: 220, width: 90, height: 70))
        selection.begin(at: CGPoint(x: 10, y: 10))
        selection.update(to: CGPoint(x: 12, y: 12), within: bounds)
        selection.end()
        XCTAssertFalse(selection.isValid)
        XCTAssertEqual(selection.rect, .zero)
    }

    func testNudgeClampsAndDoesNotInterruptDrag() {
        var selection = selected()
        selection.nudge(dx: 1, dy: -10, within: bounds)
        XCTAssertEqual(selection.rect.origin, CGPoint(x: 51, y: 50))
        selection.nudge(dx: -1000, dy: 1000, within: bounds)
        XCTAssertEqual(selection.rect, CGRect(x: 0, y: 160, width: 200, height: 140))
        selection.begin(at: CGPoint(x: 100, y: 200))
        selection.nudge(dx: 10, dy: -10, within: bounds)
        XCTAssertEqual(selection.rect.origin, CGPoint(x: 0, y: 160))
    }
}
