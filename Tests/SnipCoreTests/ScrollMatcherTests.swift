import XCTest
@testable import SnipCore

final class ScrollMatcherTests: XCTestCase {
    private func page(width: Int = 64, height: Int = 600) -> [UInt8] {
        var seed: UInt64 = 13
        return (0..<(width * height)).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return UInt8((seed >> 32) % 256)
        }
    }
    func testFindsExactOverlap() {
        let pixels = page()
        let first = GrayFrame(width: 64, height: 300, pixels: Array(pixels[0..<(64 * 300)]))
        let next = GrayFrame(width: 64, height: 300, pixels: Array(pixels[(64 * 107)..<(64 * 407)]))
        XCTAssertEqual(ScrollMatcher.match(previous: first, next: next), .append(offset: 107))
    }
    func testDuplicateDoesNotAppend() {
        let frame = GrayFrame(width: 64, height: 300, pixels: Array(page().prefix(64 * 300)))
        XCTAssertEqual(ScrollMatcher.match(previous: frame, next: frame), .duplicate)
    }
    func testUnrelatedContentRejected() {
        let pixels = page()
        let first = GrayFrame(width: 64, height: 300, pixels: Array(pixels.prefix(64 * 300)))
        let next = GrayFrame(width: 64, height: 300, pixels: Array(pixels.suffix(64 * 300)))
        XCTAssertEqual(ScrollMatcher.match(previous: first, next: next), .unmatched)
    }
    func testReverseScrollRejected() {
        let pixels = page()
        let first = GrayFrame(width: 64, height: 300, pixels: Array(pixels[(64 * 100)..<(64 * 400)]))
        let next = GrayFrame(width: 64, height: 300, pixels: Array(pixels.prefix(64 * 300)))
        XCTAssertEqual(ScrollMatcher.match(previous: first, next: next), .unmatched)
    }
    func testMismatchedDimensionsRejected() {
        XCTAssertEqual(ScrollMatcher.match(previous: GrayFrame(width: 10, height: 100, pixels: [UInt8](repeating: 0, count: 1000)),
                                           next: GrayFrame(width: 20, height: 100, pixels: [UInt8](repeating: 0, count: 2000))), .unmatched)
    }
}
