import Foundation
import CoreGraphics

public enum CaptureGeometry {
    public static func rectangle(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
    }

    /// AppKit uses bottom-left global coordinates; ScreenCaptureKit uses top-left.
    public static func quartzRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func pixelRect(_ rect: CGRect, pointSize: CGSize, pixelSize: CGSize) -> CGRect {
        let sx = pixelSize.width / pointSize.width
        let sy = pixelSize.height / pointSize.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy,
                      width: rect.width * sx, height: rect.height * sy).integral
            .intersection(CGRect(origin: .zero, size: pixelSize))
    }
}
