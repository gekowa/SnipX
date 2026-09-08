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
            let view = SelectionView(snapshot: snapshot, candidates: candidates, primaryHeight: primaryHeight, mode: mode)
            view.onComplete = { [weak self] result in self?.finish(result) }
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
    let snapshot: DisplaySnapshot
    let candidates: [SCWindow]
    let primaryHeight: CGFloat
    var mode: CaptureMode { didSet { start = nil; selection = .zero; needsDisplay = true } }
    var onComplete: ((SelectionResult?) -> Void)?
    var onMode: ((CaptureMode) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    private var hoveredWindow: SCWindow?
    private var tracking: NSTrackingArea?
    private var toolbar: NSStackView!
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(snapshot: DisplaySnapshot, candidates: [SCWindow], primaryHeight: CGFloat, mode: CaptureMode) {
        self.snapshot = snapshot; self.candidates = candidates; self.primaryHeight = primaryHeight; self.mode = mode
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
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
        addSubview(toolbar)
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
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let local = point(event)
        let screenRect = CaptureGeometry.quartzRect(snapshot.screen.frame, primaryHeight: primaryHeight)
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
        if mode == .display { onComplete?(.image(snapshot.image)); return }
        if mode == .window {
            mouseMoved(with: event)
            if let hoveredWindow { onComplete?(.window(hoveredWindow)) }
            return
        }
        start = point(event); selection = .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CaptureGeometry.rectangle(from: start, to: point(event), within: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        mouseDragged(with: event); start = nil
        guard selection.width >= 8, selection.height >= 8 else { return }
        if mode == .scrolling { onComplete?(.scrolling(snapshot, selection)); return }
        let pixels = CaptureGeometry.pixelRect(selection, pointSize: bounds.size,
                                               pixelSize: CGSize(width: snapshot.image.width, height: snapshot.image.height))
        if let crop = snapshot.image.cropping(to: pixels) { onComplete?(.image(crop)) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.40).setFill()
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd; shade.fill()
        if !selection.isEmpty {
            NSColor.systemTeal.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
        }
        let hint: String
        switch mode {
        case .region: hint = "拖动框选截图区域 · 空格切换窗口 · Esc 取消"
        case .window: hint = "点击高亮窗口截图 · 1 切回区域 · Esc 取消"
        case .display: hint = "点击当前屏幕，截取整个屏幕 · Esc 取消"
        case .scrolling: hint = "框选可滚动的内容区域，避开固定工具栏，然后手动向下滚动"
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white]
        let size = hint.size(withAttributes: attributes)
        hint.draw(at: CGPoint(x: max(16, (bounds.width - size.width) / 2), y: 50), withAttributes: attributes)
        if start != nil {
            let label = "\(Int(selection.width)) × \(Int(selection.height)) pt"
            label.draw(at: CGPoint(x: selection.minX + 6, y: max(80, selection.minY - 25)), withAttributes: attributes)
        }
    }
}
