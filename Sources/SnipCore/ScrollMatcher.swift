import Foundation
import CoreGraphics

public struct GrayFrame: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) { self.width = width; self.height = height; self.pixels = pixels }

    public init?(image: CGImage) {
        let width = min(96, image.width), height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let succeeded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard succeeded else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}

public enum ScrollMatch: Equatable, Sendable {
    case duplicate
    case append(offset: Int)
    case unmatched
}

public enum ScrollMatcher {
    private static func compatible(_ a: GrayFrame, _ b: GrayFrame) -> Bool {
        a.width == b.width && a.height == b.height && a.width >= 8 && a.height >= 48 &&
        a.pixels.count == a.width * a.height && b.pixels.count == b.width * b.height
    }

    public static func isDuplicate(_ a: GrayFrame, _ b: GrayFrame) -> Bool {
        compatible(a, b) && difference(a, b, offset: 0) < 0.65
    }

    public static func match(previous: GrayFrame, next: GrayFrame) -> ScrollMatch {
        guard compatible(previous, next) else { return .unmatched }
        if isDuplicate(previous, next) { return .duplicate }
        let limit = previous.height * 3 / 4
        var scores = [Double](repeating: .infinity, count: limit + 1)
        var best = Double.infinity; var bestOffset = 0
        for offset in 2...limit {
            let score = difference(previous, next, offset: offset)
            scores[offset] = score
            if score < best { best = score; bestOffset = offset }
        }
        guard best < 7.0, bestOffset > 0 else { return .unmatched }
        let alternate = scores.enumerated().filter { abs($0.offset - bestOffset) > 5 }.map(\.element).min() ?? .infinity
        // Repeated patterns have several equally plausible alignments. Do not guess.
        guard alternate > best + 1.4 else { return .unmatched }
        return .append(offset: bestOffset)
    }

    private static func difference(_ a: GrayFrame, _ b: GrayFrame, offset: Int) -> Double {
        let overlap = a.height - offset
        let margin = max(2, overlap / 20)
        let strideY = max(1, (overlap - 2 * margin) / 32)
        let strideX = max(1, a.width / 32)
        var sum = 0.0; var count = 0
        for y in stride(from: margin, to: overlap - margin, by: strideY) {
            for x in stride(from: a.width / 12, to: a.width * 11 / 12, by: strideX) {
                sum += Double(abs(Int(a.pixels[(y + offset) * a.width + x]) - Int(b.pixels[y * b.width + x])))
                count += 1
            }
        }
        return count == 0 ? .infinity : sum / Double(count)
    }
}

public enum ImageStitcher {
    public static let maximumPixels = 80_000_000
    public static let maximumHeight = 30_000

    public static func append(base: CGImage, frame: CGImage, offset: Int) -> CGImage? {
        let height = base.height + offset
        guard base.width == frame.width, offset > 0, offset < frame.height,
              height <= maximumHeight, base.width <= maximumPixels / height,
              let bottom = frame.cropping(to: CGRect(x: 0, y: frame.height - offset, width: frame.width, height: offset)),
              let context = CGContext(data: nil, width: base.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: offset, width: base.width, height: base.height))
        context.draw(bottom, in: CGRect(x: 0, y: 0, width: frame.width, height: offset))
        return context.makeImage()
    }
}
