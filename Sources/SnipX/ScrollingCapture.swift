import AppKit
import ScreenCaptureKit
import SnipCore

@MainActor
final class ScrollingCaptureController: NSWindowController {
    let service: CaptureService
    let snapshot: DisplaySnapshot
    let region: CGRect
    let content: SCShareableContent
    var onComplete: ((CGImage?) -> Void)?
    private let label = NSTextField(labelWithString: "准备长截图…")
    private var task: Task<Void, Never>?
    private var result: CGImage?
    private var previous: GrayFrame?
    private var pending: GrayFrame?
    private var count = 0
    private var completed = false
    private var lastGoodFrameAt = Date()

    init(service: CaptureService, snapshot: DisplaySnapshot, region: CGRect, content: SCShareableContent) {
        self.service = service; self.snapshot = snapshot; self.region = region; self.content = content
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 570, height: 110), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "SnipX · 滚动长截图"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = CGRect(x: 16, y: 12, width: 538, height: 86)
        label.font = .systemFont(ofSize: 13); stack.addArrangedSubview(label)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        for (title, action) in [("完成", #selector(finish)), ("取消", #selector(cancel))] {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons); panel.contentView?.addSubview(stack)
        let screen = snapshot.screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: screen.midX - 285, y: screen.minY + 24))
    }
    required init?(coder: NSCoder) { fatalError() }
    func start() {
        window?.orderFrontRegardless()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let initial = try await service.capture(display: snapshot.display, content: content, region: region)
                guard !Task.isCancelled else { return }
                guard initial.width <= ImageStitcher.maximumPixels / max(1, initial.height),
                      let gray = GrayFrame(image: initial) else { throw SnipError.message("选区过大或无法处理，请缩小选区重试。") }
                result = initial; previous = gray; count = 1
                label.stringValue = "请缓慢向下滚动，每次停顿片刻 · 已捕获 1 帧"
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(350))
                    let image = try await service.capture(display: snapshot.display, content: content, region: region)
                    guard !Task.isCancelled else { return }
                    try await consume(image)
                }
            } catch is CancellationError { }
            catch {
                guard !completed else { return }
                label.stringValue = "捕获停止：\(error.localizedDescription)"
                // Keep the partial image available through Finish.
            }
        }
    }
    private func consume(_ image: CGImage) async throws {
        guard let previous, let current = GrayFrame(image: image), let result else { return }
        guard let pending else { self.pending = current; return }
        self.pending = current
        let match = await Task.detached(priority: .userInitiated) {
            guard ScrollMatcher.isDuplicate(pending, current) else { return ScrollMatch.unmatched }
            return ScrollMatcher.match(previous: previous, next: current)
        }.value
        guard !completed, !Task.isCancelled else { return }
        switch match {
        case .duplicate: break
        case .unmatched:
            if Date().timeIntervalSince(lastGoodFrameAt) > 2 {
                label.stringValue = "请停顿；若跳过太多，请向上滚回最后位置再慢慢向下"
            }
        case .append(let offset):
            guard let joined = await Task.detached(priority: .userInitiated, operation: {
                ImageStitcher.append(base: result, frame: image, offset: offset)
            }).value else { throw SnipError.message("已达到长图大小上限，请点击完成保存。") }
            guard !completed, !Task.isCancelled else { return }
            self.result = joined; self.previous = current; count += 1; lastGoodFrameAt = Date()
            label.stringValue = "已拼接 \(count) 帧 · \(joined.width) × \(joined.height) px · 继续向下滚动"
        }
    }
    @objc func finish() { complete(result) }
    @objc func cancel() { complete(nil) }
    private func complete(_ image: CGImage?) {
        guard !completed else { return }
        completed = true; task?.cancel(); task = nil
        window?.orderOut(nil); close()
        let callback = onComplete; onComplete = nil; callback?(image)
    }
}
