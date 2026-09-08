import AppKit
import ScreenCaptureKit
import SnipCore

enum SelectionResult {
    case image(CGImage)
    case window(SCWindow)
    case scrolling(DisplaySnapshot, CGRect)
}

enum CaptureMode: String { case region, window, display, scrolling }

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SelectionOverlay {
    private var windows: [NSWindow] = []
    private var views: [SelectionView] { windows.compactMap { $0.contentView as? SelectionView } }
    private var keyMonitor: Any?
    private var completion: ((SelectionResult?) -> Void)?

    func show(snapshots: [DisplaySnapshot], content: SCShareableContent, mode: CaptureMode,
              completion: @escaping (SelectionResult?) -> Void) {
        close()
        self.completion = completion
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let orderedIDs = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                          as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let rank = Dictionary(orderedIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let candidates = content.windows.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
            $0.windowLayer == 0 && $0.frame.width > 30 && $0.frame.height > 30
        }.sorted { (rank[$0.windowID] ?? Int.max) < (rank[$1.windowID] ?? Int.max) }
        for snapshot in snapshots {
            let window = OverlayWindow(contentRect: snapshot.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = SelectionView(image: snapshot.image, screenFrame: snapshot.screen.frame, candidates: candidates, primaryHeight: primaryHeight, mode: mode)
            view.onComplete = { [weak self] result in self?.finish(result) }
            view.onScrollingRegion = { [weak self] rect in self?.finish(.scrolling(snapshot, rect)) }
            view.onMode = { [weak self] mode in self?.views.forEach { $0.mode = mode } }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
            if snapshot.screen.frame.contains(NSEvent.mouseLocation) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(nil); return nil }
            if let view = self?.views.first(where: { $0.window?.isKeyWindow == true }), view.handleSelectionKey(event) { return nil }
            let modes: [String: CaptureMode] = ["1": .region, "2": .window, "3": .display, "4": .scrolling, " ": .window]
            if let mode = modes[event.charactersIgnoringModifiers ?? ""] {
                self?.views.forEach { $0.mode = mode }; return nil
            }
            return event
        }
    }

    private func finish(_ result: SelectionResult?) {
        let callback = completion
        completion = nil
        close()
        callback?(result)
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
    }
}

@MainActor
final class SelectionView: NSView {
    let image: CGImage
    let screenFrame: CGRect
    let candidates: [SCWindow]
    let primaryHeight: CGFloat
    var mode: CaptureMode { didSet {
        adjustment = AdjustableSelection(); selection = .zero; hoveredWindow = nil
        refreshSelection()
    } }
    var onComplete: ((SelectionResult?) -> Void)?
    var onScrollingRegion: ((CGRect) -> Void)?
    var onMode: ((CaptureMode) -> Void)?
    private var adjustment = AdjustableSelection()
    private var selection = CGRect.zero
    private var hoveredWindow: SCWindow?
    private var tracking: NSTrackingArea?
    private var toolbar: NSStackView!
    private var confirmButton: NSButton!
    private var adjustsRegion: Bool { mode == .region || mode == .scrolling }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage, screenFrame: CGRect, candidates: [SCWindow], primaryHeight: CGFloat, mode: CaptureMode) {
        self.image = image; self.screenFrame = screenFrame; self.candidates = candidates; self.primaryHeight = primaryHeight; self.mode = mode
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        toolbar = NSStackView()
        toolbar.orientation = .horizontal; toolbar.spacing = 8
        toolbar.wantsLayer = true; toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        toolbar.layer?.cornerRadius = 12
        toolbar.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        for (index, title) in ["① 区域", "② 窗口", "③ 全屏", "④ 长截图", "取消 Esc"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(changeMode(_:)))
            button.tag = index; button.bezelStyle = .rounded
            toolbar.addArrangedSubview(button)
        }
        confirmButton = NSButton(title: "确认选区 ↵", target: self, action: #selector(confirmSelection))
        confirmButton.bezelStyle = .rounded
        confirmButton.isEnabled = false
        toolbar.addArrangedSubview(confirmButton)
        addSubview(toolbar)
        refreshSelection()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: (bounds.width - size.width) / 2, y: max(12, bounds.height - size.height - 36), width: size.width, height: size.height)
    }
    @objc private func changeMode(_ sender: NSButton) {
        if sender.tag == 4 { onComplete?(nil) }
        else { onMode?([CaptureMode.region, .window, .display, .scrolling][sender.tag]) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard adjustsRegion, adjustment.isValid else { return }
        addCursorRect(selection, cursor: .openHand)
        for handle in AdjustableSelection.Handle.allCases {
            let position = handle.position(in: selection)
            let target: CGRect
            switch handle {
            case .top, .bottom: target = CGRect(x: selection.minX + 7, y: position.y - 7, width: max(0, selection.width - 14), height: 14)
            case .left, .right: target = CGRect(x: position.x - 7, y: selection.minY + 7, width: 14, height: max(0, selection.height - 14))
            default: target = CGRect(x: position.x - 7, y: position.y - 7, width: 14, height: 14)
            }
            addCursorRect(target.intersection(bounds), cursor: resizeCursor(for: handle))
        }
    }
    private func resizeCursor(for handle: AdjustableSelection.Handle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return .frameResize(position: position, directions: .all)
        }
        switch handle {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .bottomRight: return Self.descendingResizeCursor
        case .topRight, .bottomLeft: return Self.ascendingResizeCursor
        }
    }
    // macOS 14 has no public diagonal resize cursor; draw a matching two-headed arrow.
    private static let descendingResizeCursor = diagonalResizeCursor(angle: -45)
    private static let ascendingResizeCursor = diagonalResizeCursor(angle: 45)
    private static func diagonalResizeCursor(angle: CGFloat) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: -9, y: 0)); path.line(to: NSPoint(x: 9, y: 0))
            for direction: CGFloat in [-1, 1] {
                path.move(to: NSPoint(x: direction * 4, y: -5))
                path.line(to: NSPoint(x: direction * 9, y: 0))
                path.line(to: NSPoint(x: direction * 4, y: 5))
            }
            let transform = AffineTransform(translationByX: 12, byY: 12)
            var rotation = AffineTransform(); rotation.rotate(byDegrees: angle)
            path.transform(using: rotation); path.transform(using: transform)
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
    private func refreshSelection() {
        confirmButton?.isHidden = !adjustsRegion
        confirmButton?.isEnabled = adjustsRegion && adjustment.isValid && !adjustment.isDragging
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    func handleSelectionKey(_ event: NSEvent) -> Bool {
        guard adjustsRegion else { return false }
        if event.keyCode == 36 || event.keyCode == 76 { confirmSelection(); return true }
        let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let movement: (CGFloat, CGFloat)
        switch event.keyCode {
        case 123: movement = (-delta, 0)
        case 124: movement = (delta, 0)
        case 125: movement = (0, delta)
        case 126: movement = (0, -delta)
        default: return false
        }
        adjustment.nudge(dx: movement.0, dy: movement.1, within: bounds)
        selection = adjustment.rect; refreshSelection()
        return true
    }
    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let local = point(event)
        let screenRect = CaptureGeometry.quartzRect(screenFrame, primaryHeight: primaryHeight)
        let global = CGPoint(x: screenRect.minX + local.x, y: screenRect.minY + local.y)
        hoveredWindow = candidates.first { $0.frame.contains(global) }
        let oldSelection = selection
        if let hoveredWindow {
            selection = hoveredWindow.frame.offsetBy(dx: -screenRect.minX, dy: -screenRect.minY).intersection(bounds)
        } else { selection = .zero }
        if oldSelection != selection { needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if mode == .display { onComplete?(.image(image)); return }
        if mode == .window {
            mouseMoved(with: event)
            if let hoveredWindow { onComplete?(.window(hoveredWindow)) }
            return
        }
        adjustment.begin(at: point(event))
        selection = adjustment.rect; refreshSelection()
    }
    override func mouseDragged(with event: NSEvent) {
        guard adjustsRegion, adjustment.isDragging else { return }
        adjustment.update(to: point(event), within: bounds)
        selection = adjustment.rect; refreshSelection()
    }
    override func mouseUp(with event: NSEvent) {
        guard adjustsRegion, adjustment.isDragging else { return }
        mouseDragged(with: event)
        adjustment.end()
        selection = adjustment.rect; refreshSelection()
    }
    @objc private func confirmSelection() {
        guard adjustsRegion, adjustment.isValid, !adjustment.isDragging else { return }
        if mode == .scrolling { onScrollingRegion?(selection); return }
        let pixels = CaptureGeometry.pixelRect(selection, pointSize: bounds.size,
                                               pixelSize: CGSize(width: image.width, height: image.height))
        if let crop = image.cropping(to: pixels) { onComplete?(.image(crop)) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.40).setFill()
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd; shade.fill()
        if !selection.isEmpty {
            NSColor.systemTeal.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
            if adjustsRegion, adjustment.isValid {
                for handle in AdjustableSelection.Handle.allCases {
                    let center = handle.position(in: selection)
                    let knob = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                    NSColor.white.setFill(); knob.fill()
                    NSColor.systemTeal.setStroke(); knob.lineWidth = 1.5; knob.stroke()
                }
            }
        }
        let hint: String
        switch mode {
        case .region: hint = adjustment.isValid
            ? "拖动内部移动 · 拖动边框调整 · 方向键微调（Shift 加速）· Enter 确认 · Esc 取消"
            : "拖动框选截图区域，松开后可调整 · 空格切换窗口 · Esc 取消"
        case .window: hint = "点击高亮窗口截图 · 1 切回区域 · Esc 取消"
        case .display: hint = "点击当前屏幕，截取整个屏幕 · Esc 取消"
        case .scrolling: hint = adjustment.isValid
            ? "调整选区，避开固定工具栏 · Enter 确认后开始滚动 · Esc 取消"
            : "框选可滚动的内容区域，松开后可调整，确认后再滚动"
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white]
        let size = hint.size(withAttributes: attributes)
        hint.draw(at: CGPoint(x: max(16, (bounds.width - size.width) / 2), y: 50), withAttributes: attributes)
        if adjustsRegion, !selection.isEmpty {
            let pixels = CaptureGeometry.pixelRect(selection, pointSize: bounds.size,
                                                   pixelSize: CGSize(width: image.width, height: image.height))
            let label = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
            label.draw(at: CGPoint(x: selection.minX + 6, y: max(80, selection.minY - 25)), withAttributes: attributes)
        }
    }
}
