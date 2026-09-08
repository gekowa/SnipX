import CoreGraphics

/// Selection coordinates use points in the overlay's local coordinate space.
public struct AdjustableSelection {
    public enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        public func position(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .top: return CGPoint(x: rect.midX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .right: return CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .left: return CGPoint(x: rect.minX, y: rect.midY)
            }
        }
    }

    private enum Drag { case create, move, resize(Handle) }
    public private(set) var rect = CGRect.zero
    public private(set) var isDragging = false
    public var isValid: Bool { !rect.isNull && rect.width >= 8 && rect.height >= 8 }
    private var drag = Drag.create
    private var origin = CGPoint.zero
    private var initial = CGRect.zero

    public init() {}

    public func handle(at point: CGPoint) -> Handle? {
        guard isValid else { return nil }
        // Corners take priority when a very small selection has overlapping targets.
        for handle in [Handle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let center = handle.position(in: rect)
            if abs(point.x - center.x) <= 7 && abs(point.y - center.y) <= 7 { return handle }
        }
        guard rect.insetBy(dx: -7, dy: -7).contains(point) else { return nil }
        if abs(point.y - rect.minY) <= 7 { return .top }
        if abs(point.y - rect.maxY) <= 7 { return .bottom }
        if abs(point.x - rect.minX) <= 7 { return .left }
        if abs(point.x - rect.maxX) <= 7 { return .right }
        return nil
    }

    public mutating func begin(at point: CGPoint) {
        origin = point; initial = rect; isDragging = true
        if let handle = handle(at: point) { drag = .resize(handle) }
        else if isValid && rect.contains(point) { drag = .move }
        else { drag = .create; rect = .zero }
    }

    public mutating func update(to point: CGPoint, within bounds: CGRect) {
        guard isDragging else { return }
        let dx = point.x - origin.x, dy = point.y - origin.y
        switch drag {
        case .create:
            rect = CaptureGeometry.rectangle(from: origin, to: point, within: bounds)
        case .move:
            rect.origin = CGPoint(x: min(max(initial.minX + dx, bounds.minX), bounds.maxX - initial.width),
                                  y: min(max(initial.minY + dy, bounds.minY), bounds.maxY - initial.height))
        case .resize(let handle):
            var left = initial.minX, right = initial.maxX, top = initial.minY, bottom = initial.maxY
            if [.topLeft, .left, .bottomLeft].contains(handle) { left = max(bounds.minX, min(right - 8, left + dx)) }
            if [.topRight, .right, .bottomRight].contains(handle) { right = min(bounds.maxX, max(left + 8, right + dx)) }
            if [.topLeft, .top, .topRight].contains(handle) { top = max(bounds.minY, min(bottom - 8, top + dy)) }
            if [.bottomLeft, .bottom, .bottomRight].contains(handle) { bottom = min(bounds.maxY, max(top + 8, bottom + dy)) }
            rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }

    public mutating func end() {
        isDragging = false
        if !isValid { rect = .zero }
    }

    public mutating func nudge(dx: CGFloat, dy: CGFloat, within bounds: CGRect) {
        guard isValid, !isDragging else { return }
        rect.origin = CGPoint(x: min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width),
                              y: min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height))
    }
}
