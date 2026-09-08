import XCTest
import CoreGraphics
@testable import SnipCore

final class GeometryTests: XCTestCase {
    func testReverseDragClampedToScreen() {
        XCTAssertEqual(CaptureGeometry.rectangle(from: CGPoint(x: 150, y: 90), to: CGPoint(x: -20, y: 10),
                                                 within: CGRect(x: 0, y: 0, width: 100, height: 100)),
                       CGRect(x: 0, y: 10, width: 100, height: 80))
    }
    func testSecondaryScreenAboveMain() {
        XCTAssertEqual(CaptureGeometry.quartzRect(CGRect(x: -100, y: 1000, width: 200, height: 500), primaryHeight: 900),
                       CGRect(x: -100, y: -600, width: 200, height: 500))
    }
    func testRetinaCrop() {
        XCTAssertEqual(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 30, height: 40),
                                                pointSize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200)),
                       CGRect(x: 20, y: 40, width: 60, height: 80))
    }
}
