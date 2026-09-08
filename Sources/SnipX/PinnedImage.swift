import AppKit

@MainActor
final class PinnedImageController: NSWindowController, NSWindowDelegate {
    let image: CGImage
    var onClose: (() -> Void)?
    init(image: CGImage) {
        self.image = image
        let maxSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 900, height: 700)
        let scale = min(0.6, min(maxSize.width * 0.65 / CGFloat(image.width), maxSize.height * 0.7 / CGFloat(image.height)))
        let size = CGSize(width: max(80, CGFloat(image.width) * scale), height: max(80, CGFloat(image.height) * scale))
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "SnipX · 贴图"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        panel.minSize = CGSize(width: 80, height: 80); panel.delegate = self
        let view = PinImageView()
        view.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        view.imageScaling = .scaleProportionallyUpOrDown
        let menu = NSMenu()
        for (title, selector) in [("复制图像", #selector(copyImage)), ("保存图像…", #selector(saveImage)), ("半透明 / 不透明", #selector(toggleOpacity)), ("关闭贴图", #selector(closePin))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        view.menu = menu; panel.contentView = view
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() { window?.orderFrontRegardless() }
    @objc private func copyImage() { do { try ImageOutput.copy(image) } catch { NSAlert(error: error).runModal() } }
    @objc private func saveImage() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        ImageOutput.save(image, parent: window) { result in
            if case .failure(let error) = result { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
    @objc private func toggleOpacity() { window?.alphaValue = window?.alphaValue == 1 ? 0.55 : 1 }
    @objc private func closePin() { close() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class PinImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
}
