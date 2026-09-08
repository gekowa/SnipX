import XCTest
import CoreGraphics
@testable import SnipCore

final class ImageStitcherTests: XCTestCase {
    private func image(start: Int, height: Int) -> CGImage {
        let width = 64
        let bytes = (0..<(width * height)).flatMap { index -> [UInt8] in
            let row = start + index / width
            return [UInt8(row % 256), UInt8(row / 256), UInt8(index % width), 255]
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func rgba(_ image: CGImage) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: image.width * image.height * 4)
        output.withUnsafeMutableBytes { ptr in
            let context = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return output
    }
    func testComposedImageMatchesContinuousPagePixelForPixel() throws {
        let first = image(start: 0, height: 300)
        let second = image(start: 107, height: 300)
        let joined = try XCTUnwrap(ImageStitcher.append(base: first, frame: second, offset: 107))
        XCTAssertEqual(joined.height, 407)
        XCTAssertEqual(rgba(joined), rgba(image(start: 0, height: 407)))
    }
    func testGrayConversionKeepsTopToBottomRowOrder() throws {
        let first = try XCTUnwrap(GrayFrame(image: image(start: 0, height: 300)))
        let second = try XCTUnwrap(GrayFrame(image: image(start: 107, height: 300)))
        for row in 0..<193 {
            XCTAssertEqual(Array(first.pixels[((row + 107) * 64)..<((row + 108) * 64)]), Array(second.pixels[(row * 64)..<((row + 1) * 64)]))
        }
    }
    func testInvalidOffsetsAndSizeLimitRejected() {
        let frame = image(start: 0, height: 300)
        XCTAssertNil(ImageStitcher.append(base: frame, frame: frame, offset: 0))
        XCTAssertNil(ImageStitcher.append(base: frame, frame: frame, offset: 300))
        XCTAssertNil(ImageStitcher.append(base: image(start: 0, height: 30000), frame: frame, offset: 10))
    }
}
