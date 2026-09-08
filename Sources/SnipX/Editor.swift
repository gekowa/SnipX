import AppKit
import UniformTypeIdentifiers
import CoreImage

enum AnnotationTool: Int, CaseIterable {
    case rectangle, oval, line, arrow, pen, pixelate, text, step
    var title: String { ["矩形", "椭圆", "直线", "箭头", "画笔", "马赛克", "文字", "步骤编号"][rawValue] }
    var symbol: String { ["rectangle", "circle", "line.diagonal", "arrow.up.left", "pencil", "square.grid.3x3", "textformat", "1.circle.fill"][rawValue] }
}

struct Annotation {
    let tool: AnnotationTool
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    var text: String = ""
}

@MainActor
final class AnnotationCanvas: NSView {
    let source: CGImage
    var tool: AnnotationTool = .pen { didSet { refreshCursor() } }
    var ink: NSColor = .systemRed
    var strokeWidth: CGFloat = 5
    var textSize: CGFloat = 32
    private(set) var annotations: [Annotation] = [] { didSet { refreshCursor() } }
    private var hoverTrackingArea: NSTrackingArea?
    private var history: [[Annotation]] = []
    private var undone: [[Annotation]] = []
    private var moving: (index: Int, origin: CGPoint, before: [Annotation])?
    private var pan: (point: CGPoint, origin: CGPoint)?
    private var draft: Annotation?
    private lazy var pixelated: CGImage? = {
        let input = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIPixellate", parameters: [kCIInputImageKey: input, kCIInputScaleKey: 18]),
              let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }()
    var onChange: (() -> Void)?
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !undone.isEmpty }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage) {
        source = image
        super.init(frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() { refreshCursor() }
    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); hoverTrackingArea = area
        super.updateTrackingAreas()
        refreshCursor()
    }
    private func updateCursor(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if moving != nil || pan != nil { NSCursor.closedHand.set() }
        else if !visibleRect.contains(point) { NSCursor.arrow.set() }
        else if draft == nil, !modifiers.contains(.option), annotationIndex(at: point) != nil { NSCursor.openHand.set() }
        else { (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set() }
    }
    private func refreshCursor() {
        guard let window, window.isKeyWindow else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else { return }
        updateCursor(at: point, modifiers: NSEvent.modifierFlags)
    }
    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func cursorUpdate(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        if moving == nil, pan == nil { NSCursor.arrow.set() }
    }
    override func flagsChanged(with event: NSEvent) { refreshCursor() }
    override func draw(_ dirtyRect: NSRect) { render(includeDraft: true) }
    private func render(includeDraft: Bool) {
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        NSImage(cgImage: source, size: rect.size).draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        for annotation in annotations { draw(annotation) }
        if includeDraft, let draft { draw(draft) }
    }
    private func draw(_ annotation: Annotation) {
        guard let first = annotation.points.first, let last = annotation.points.last else { return }
        annotation.color.setStroke(); annotation.color.setFill()
        if annotation.tool == .text {
            annotation.text.draw(at: first, withAttributes: [.font: NSFont.systemFont(ofSize: annotation.width, weight: .semibold), .foregroundColor: annotation.color])
            return
        }
        if annotation.tool == .step {
            let diameter = annotation.width * 1.35
            let circle = CGRect(x: first.x - diameter / 2, y: first.y - diameter / 2, width: diameter, height: diameter)
            NSBezierPath(ovalIn: circle).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: annotation.width * 0.8, weight: .semibold), .foregroundColor: NSColor.white]
            let size = annotation.text.size(withAttributes: attributes)
            annotation.text.draw(at: CGPoint(x: first.x - size.width / 2, y: first.y - size.height / 2), withAttributes: attributes)
            return
        }
        let box = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(first.x - last.x), height: abs(first.y - last.y))
        if annotation.tool == .pixelate {
            guard let pixelated else { return }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: box).addClip()
            NSImage(cgImage: pixelated, size: bounds.size).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let path = NSBezierPath()
        path.lineWidth = annotation.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch annotation.tool {
        case .pen:
            if annotation.points.count == 1 {
                NSBezierPath(ovalIn: CGRect(x: first.x - annotation.width / 2, y: first.y - annotation.width / 2,
                                           width: annotation.width, height: annotation.width)).fill()
                return
            }
            path.move(to: first); annotation.points.dropFirst().forEach { path.line(to: $0) }
        case .line, .arrow:
            path.move(to: first); path.line(to: last)
            if annotation.tool == .arrow {
                let angle = atan2(last.y - first.y, last.x - first.x)
                let length = max(16, annotation.width * 4)
                for spread in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    path.move(to: last)
                    path.line(to: CGPoint(x: last.x - length * cos(angle + spread), y: last.y - length * sin(angle + spread)))
                }
            }
        case .rectangle: path.appendRect(box)
        case .oval: path.appendOval(in: box)
        case .text, .pixelate, .step: break
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard pan == nil else { return }
        if !event.modifierFlags.contains(.option), let index = annotationIndex(at: point) {
            moving = (index, point, annotations)
            NSCursor.closedHand.set()
            return
        }
        if tool == .step {
            let number = annotations.filter { $0.tool == .step }.count + 1
            append(Annotation(tool: .step, points: [point], color: ink, width: textSize, text: String(number)))
            return
        }
        if tool == .text {
            let alert = NSAlert()
            alert.messageText = "添加文字"; alert.informativeText = "输入要放在截图上的标注。"
            let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
            field.placeholderString = "标注内容"; field.isEditable = true
            alert.accessoryView = field; alert.addButton(withTitle: "添加"); alert.addButton(withTitle: "取消")
            guard let window else { return }
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.append(Annotation(tool: .text, points: [point], color: self.ink, width: self.textSize, text: field.stringValue))
            }
            alert.window.makeFirstResponder(field)
            return
        }
        draft = Annotation(tool: tool, points: [point], color: ink, width: strokeWidth)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if let moving {
            let point = convert(event.locationInWindow, from: nil)
            let delta = CGPoint(x: point.x - moving.origin.x, y: point.y - moving.origin.y)
            annotations[moving.index].points = moving.before[moving.index].points.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
            needsDisplay = true
            return
        }
        guard let tool = draft?.tool, let first = draft?.points.first else { return }
        let raw = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: min(max(0, raw.x), bounds.width), y: min(max(0, raw.y), bounds.height))
        if tool == .pen { draft?.points.append(point) }
        else { draft?.points = [first, point] }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let moving {
            mouseDragged(with: event)
            if annotations[moving.index].points != moving.before[moving.index].points {
                history.append(moving.before); undone.removeAll(); onChange?()
            }
            self.moving = nil
            window?.invalidateCursorRects(for: self)
            mouseMoved(with: event)
            return
        }
        guard draft != nil else { return }
        mouseDragged(with: event)
        if let draft { append(draft) }
        draft = nil; needsDisplay = true
        mouseMoved(with: event)
    }
    func append(_ annotation: Annotation) {
        history.append(annotations)
        annotations.append(annotation); undone.removeAll(); needsDisplay = true; onChange?()
    }
    @objc func undoAnnotation() {
        guard moving == nil, draft == nil, let value = history.popLast() else { return }
        undone.append(annotations); annotations = value; needsDisplay = true; onChange?()
    }
    @objc func redoAnnotation() {
        guard moving == nil, draft == nil, let value = undone.popLast() else { return }
        history.append(annotations); annotations = value; needsDisplay = true; onChange?()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard moving == nil, draft == nil, let clip = enclosingScrollView?.contentView else { return }
        pan = (event.locationInWindow, clip.bounds.origin)
        NSCursor.closedHand.set()
    }
    override func rightMouseDragged(with event: NSEvent) {
        guard let pan, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        // Convert the window-space delta without including the changing scroll origin.
        let start = clip.convert(pan.point, from: nil)
        let end = clip.convert(event.locationInWindow, from: nil)
        let proposed = CGRect(origin: CGPoint(x: pan.origin.x - (end.x - start.x),
                                              y: pan.origin.y - (end.y - start.y)), size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
    }
    override func rightMouseUp(with event: NSEvent) {
        rightMouseDragged(with: event)
        pan = nil
        window?.invalidateCursorRects(for: self)
        mouseMoved(with: event)
    }

    func annotationIndex(at point: CGPoint) -> Int? {
        let scale = max(0.001, frame.width / bounds.width)
        let tolerance = 6 / scale
        return annotations.indices.reversed().first { index in
            let item = annotations[index]
            guard let first = item.points.first, let last = item.points.last else { return false }
            let box = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                             width: abs(last.x - first.x), height: abs(last.y - first.y))
            if item.tool == .text {
                let size = item.text.size(withAttributes: [.font: NSFont.systemFont(ofSize: item.width, weight: .semibold)])
                return CGRect(origin: first, size: size).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            if item.tool == .step { return hypot(point.x - first.x, point.y - first.y) <= item.width * 1.35 / 2 + tolerance }
            if item.tool == .pixelate { return box.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            let path = CGMutablePath()
            switch item.tool {
            case .rectangle: path.addRect(box)
            case .oval: path.addEllipse(in: box)
            case .pen:
                if item.points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= item.width / 2 + tolerance }
                path.addLines(between: item.points)
            case .line, .arrow:
                path.move(to: first); path.addLine(to: last)
                if item.tool == .arrow {
                    let angle = atan2(last.y - first.y, last.x - first.x)
                    let length = max(16, item.width * 4)
                    for spread in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                        path.move(to: last)
                        path.addLine(to: CGPoint(x: last.x - length * cos(angle + spread), y: last.y - length * sin(angle + spread)))
                    }
                }
            default: return false
            }
            return path.copy(strokingWithWidth: item.width + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { redoAnnotation() } else { undoAnnotation() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    func flattened() throws -> CGImage {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: source.width, pixelsHigh: source.height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw SnipError.message("无法创建图像，请尝试较小的截图。") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.translateBy(x: 0, y: CGFloat(source.height))
        context.cgContext.scaleBy(x: 1, y: -1)
        render(includeDraft: false)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = rep.cgImage else { throw SnipError.message("图像生成失败。") }
        return image
    }
}

@MainActor
enum ImageOutput {
    static func copy(_ image: CGImage) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnipError.message("PNG 编码失败。") }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(data, forType: .png) else { throw SnipError.message("写入剪贴板失败，请重试。") }
    }
    static func save(_ image: CGImage, parent: NSWindow, completion: @escaping (Result<URL?, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "SnipX_\(formatter.string(from: Date())).png"
        panel.beginSheetModal(for: parent) { response in
            guard response == .OK, let url = panel.url else { completion(.success(nil)); return }
            do {
                let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: isJPEG ? .jpeg : .png, properties: [.compressionFactor: 0.95]) else {
                    throw SnipError.message("图像编码失败。")
                }
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch { completion(.failure(error)) }
        }
    }
}

@MainActor
final class EditorController: NSWindowController, NSWindowDelegate {
    let canvas: AnnotationCanvas
    var onPin: ((CGImage) -> Void)?
    var onScrollCapture: (() -> Void)?
    var onClose: (() -> Void)?
    private let status = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var zoom: CGFloat = 1
    private var toolButtons: [NSButton] = []

    init(image: CGImage) {
        canvas = AnnotationCanvas(image: image)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "SnipX · 标注截图"; window.minSize = NSSize(width: 960, height: 460)
        window.isReleasedWhenClosed = false; window.delegate = self
        buildUI()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func button(_ title: String, symbol: String? = nil, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); button.imagePosition = .imageLeading }
        return button
    }
    private func buildUI() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1).cgColor
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 7
        toolbar.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        toolbar.wantsLayer = true; toolbar.layer?.backgroundColor = NSColor.white.cgColor
        toolbar.layer?.cornerRadius = 32
        toolbar.shadow = NSShadow(); toolbar.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.18)
        toolbar.shadow?.shadowBlurRadius = 18; toolbar.shadow?.shadowOffset = NSSize(width: 0, height: -5)
        toolbar.appearance = NSAppearance(named: .aqua)
        for tool in AnnotationTool.allCases {
            let control = iconButton(tool.title, symbol: tool.symbol, action: #selector(toolChanged(_:)))
            control.tag = tool.rawValue; toolButtons.append(control); toolbar.addArrangedSubview(control)
        }
        addDivider(to: toolbar)
        undoButton = iconButton("撤销 ⌘Z（右键重做）", symbol: "arrow.uturn.backward", action: #selector(undoAction))
        let undoMenu = NSMenu(); let redo = NSMenuItem(title: "重做 ⇧⌘Z", action: #selector(redoAction), keyEquivalent: "")
        redo.target = self; undoMenu.addItem(redo); undoButton.menu = undoMenu
        toolbar.addArrangedSubview(undoButton)
        addDivider(to: toolbar)
        toolbar.addArrangedSubview(iconButton("滚动长截图", symbol: "rectangle.portrait.and.arrow.forward", action: #selector(startScrolling)))
        toolbar.addArrangedSubview(iconButton("保存截图", symbol: "square.and.arrow.down", action: #selector(saveImage)))
        toolbar.addArrangedSubview(iconButton("置顶贴图", symbol: "pin", action: #selector(pinImage)))
        toolbar.addArrangedSubview(iconButton("取消截图", symbol: "xmark", color: .systemRed, action: #selector(cancelCapture)))
        toolbar.addArrangedSubview(iconButton("复制到剪贴板", symbol: "checkmark", color: NSColor(calibratedRed: 0.38, green: 0.72, blue: 0.12, alpha: 1), action: #selector(copyImage)))
        updateToolSelection()

        let options = NSStackView(); options.orientation = .horizontal; options.spacing = 10
        options.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        let color = NSColorWell(); color.color = canvas.ink; color.target = self; color.action = #selector(colorChanged(_:))
        color.widthAnchor.constraint(equalToConstant: 38).isActive = true
        color.toolTip = "标注颜色"; options.addArrangedSubview(color)
        let thickness = NSPopUpButton(); thickness.addItems(withTitles: ["细", "中", "粗"])
        thickness.selectItem(at: 1); thickness.target = self; thickness.action = #selector(widthChanged(_:)); thickness.toolTip = "线宽 / 字号"
        options.addArrangedSubview(thickness)
        redoButton = button("重做", symbol: "arrow.uturn.forward", action: #selector(redoAction))
        options.addArrangedSubview(redoButton)
        options.addArrangedSubview(button("−", action: #selector(zoomOut)))
        options.addArrangedSubview(button("+", action: #selector(zoomIn)))
        options.addArrangedSubview(button("适合窗口", action: #selector(fit)))
        scroll.documentView = canvas; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.90, alpha: 1)
        status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        status.textColor = .secondaryLabelColor
        for view in [scroll, options, status, toolbar] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            options.centerXAnchor.constraint(equalTo: root.centerXAnchor), options.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), scroll.topAnchor.constraint(equalTo: options.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -20),
            toolbar.centerXAnchor.constraint(equalTo: root.centerXAnchor), toolbar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -18),
            status.centerXAnchor.constraint(equalTo: root.centerXAnchor), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        canvas.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
    }
    private func iconButton(_ title: String, symbol: String, color: NSColor = NSColor(calibratedWhite: 0.25, alpha: 1), action: Selector) -> NSButton {
        let control = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
        control.isBordered = false; control.imagePosition = .imageOnly
        control.image = control.image?.withSymbolConfiguration(.init(pointSize: 25, weight: .regular))
        control.contentTintColor = color; control.toolTip = title; control.setAccessibilityLabel(title)
        control.widthAnchor.constraint(equalToConstant: 43).isActive = true
        control.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return control
    }
    private func addDivider(to stack: NSStackView) {
        let divider = NSBox(); divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(divider)
    }
    private func updateToolSelection() {
        for button in toolButtons {
            button.wantsLayer = true; button.layer?.cornerRadius = 9
            button.layer?.backgroundColor = (button.tag == canvas.tool.rawValue ? NSColor(calibratedWhite: 0.90, alpha: 1) : .clear).cgColor
        }
    }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); window?.contentView?.layoutSubtreeIfNeeded(); fit() }
    private func updateStatus(_ text: String? = nil) {
        status.stringValue = text ?? "\(canvas.source.width) × \(canvas.source.height) px · \(Int(zoom * 100))% · 右键拖动平移 · 左键拖动标注 · ⌥ 绘制新标注 · ⌘Z 撤销 / ⇧⌘Z 重做"
        undoButton.isEnabled = canvas.canUndo; redoButton.isEnabled = canvas.canRedo
    }
    private func setZoom(_ value: CGFloat) {
        zoom = max(0.03, min(4, value))
        let size = CGSize(width: canvas.source.width, height: canvas.source.height)
        canvas.setFrameSize(CGSize(width: size.width * zoom, height: size.height * zoom)); canvas.setBoundsSize(size)
        canvas.needsDisplay = true; updateStatus()
    }
    @objc private func fit() {
        let size = scroll.contentSize
        setZoom(min(1, min(size.width / CGFloat(canvas.source.width), size.height / CGFloat(canvas.source.height))))
    }
    @objc private func zoomIn() { setZoom(zoom * 1.25) }
    @objc private func zoomOut() { setZoom(zoom / 1.25) }
    @objc private func toolChanged(_ sender: NSButton) { canvas.tool = AnnotationTool(rawValue: sender.tag) ?? .pen; window?.invalidateCursorRects(for: canvas); updateToolSelection() }
    @objc private func cancelCapture() { close() }
    @objc private func startScrolling() { onScrollCapture?() }
    @objc private func colorChanged(_ sender: NSColorWell) { canvas.ink = sender.color }
    @objc private func widthChanged(_ sender: NSPopUpButton) { canvas.strokeWidth = [2, 5, 10][sender.indexOfSelectedItem]; canvas.textSize = [20, 32, 48][sender.indexOfSelectedItem] }
    @objc private func undoAction() { canvas.undoAnnotation() }
    @objc private func redoAction() { canvas.redoAnnotation() }
    @objc private func copyImage() { perform { try ImageOutput.copy(canvas.flattened()); updateStatus("已复制到剪贴板") } }
    @objc private func pinImage() { perform { onPin?(try canvas.flattened()); updateStatus("已置顶；贴图上右键可复制、保存和关闭") } }
    @objc private func saveImage() {
        perform {
            guard let window else { return }
            ImageOutput.save(try canvas.flattened(), parent: window) { [weak self] result in
                switch result {
                case .success(let url): if let url { self?.updateStatus("已保存：\(url.lastPathComponent)") }
                case .failure(let error): self?.showError(error)
                }
            }
        }
    }
    private func perform(_ work: () throws -> Void) { do { try work() } catch { showError(error) } }
    private func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
