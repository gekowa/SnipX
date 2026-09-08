import AppKit
import Carbon
import ScreenCaptureKit

@main
struct SnipXMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capture = CaptureService()
    private let overlay = SelectionOverlay()
    private let hotKey = HotKey()
    private var item: NSStatusItem!
    private var settings: NSWindow?
    private var editors: [UUID: EditorController] = [:]
    private var pins: [UUID: PinnedImageController] = [:]
    private var scrolling: ScrollingCaptureController?
    private var busy = false
    private var shortcutLabel: String { UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⇧⌘2" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnipX 截图")
        item.button?.toolTip = "SnipX · \(shortcutLabel)"
        rebuildMenu()
        hotKey.action = { [weak self] in self?.beginCapture(mode: .region) }
        do {
            let key = UserDefaults.standard.object(forKey: "shortcutKey") as? UInt32 ?? UInt32(kVK_ANSI_2)
            let mods = UserDefaults.standard.object(forKey: "shortcutModifiers") as? UInt32 ?? UInt32(cmdKey | shiftKey)
            try hotKey.register(keyCode: key, modifiers: mods)
        } catch { showError(error) }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        if CommandLine.arguments.contains("--smoke-test") {
            let report = "SnipX launched on \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            try? report.write(toFile: "/private/tmp/snipx-smoke.txt", atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
        }
    }
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 SnipX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "SnipX · 随手截，随处贴", action: nil, keyEquivalent: ""); heading.isEnabled = false; menu.addItem(heading)
        for (title, selector) in [("开始截图   \(shortcutLabel)", #selector(screenshot)), ("窗口截图", #selector(windowScreenshot)), ("全屏截图", #selector(displayScreenshot)), ("滚动长截图", #selector(scrollScreenshot))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [("关闭所有贴图", #selector(closePins)), ("设置与使用说明…", #selector(showSettings)), ("退出 SnipX", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        item.menu = menu
    }
    @objc private func screenshot() { beginCapture(mode: .region) }
    @objc private func windowScreenshot() { beginCapture(mode: .window) }
    @objc private func displayScreenshot() { beginCapture(mode: .display) }
    @objc private func scrollScreenshot() { beginCapture(mode: .scrolling) }
    private func beginCapture(mode: CaptureMode) {
        guard !busy, scrolling == nil else { NSSound.beep(); return }
        busy = true
        Task {
            do {
                // Wait for the status menu to disappear before freezing the desktop.
                try await Task.sleep(for: .milliseconds(180))
                let content = try await capture.content()
                let snapshots = try await capture.snapshots(content: content)
                overlay.show(snapshots: snapshots, content: content, mode: mode) { [weak self] result in
                    guard let self else { return }
                    self.handle(result, content: content)
                }
            } catch { busy = false; showError(error) }
        }
    }
    private func handle(_ result: SelectionResult?, content: SCShareableContent) {
        guard let result else { busy = false; return }
        Task {
            defer { busy = false }
            do {
                switch result {
                case .image(let image): openEditor(image)
                case .window(let window): openEditor(try await capture.capture(window: window))
                case .scrolling(let snapshot, let rect):
                    let controller = ScrollingCaptureController(service: capture, snapshot: snapshot, region: rect, content: content)
                    controller.onComplete = { [weak self] image in
                        self?.scrolling = nil
                        if let image { self?.openEditor(image) }
                    }
                    scrolling = controller
                    controller.start()
                }
            } catch { showError(error) }
        }
    }
    private func openEditor(_ image: CGImage) {
        let id = UUID(); let editor = EditorController(image: image)
        editor.onPin = { [weak self] in self?.pin($0) }
        editor.onScrollCapture = { [weak self] in self?.beginCapture(mode: .scrolling) }
        editor.onClose = { [weak self] in self?.editors.removeValue(forKey: id) }
        editors[id] = editor; editor.present()
    }
    private func pin(_ image: CGImage) {
        let id = UUID(); let controller = PinnedImageController(image: image)
        controller.onClose = { [weak self] in self?.pins.removeValue(forKey: id) }
        pins[id] = controller; controller.present()
    }
    @objc private func closePins() { let current = Array(pins.values); current.forEach { $0.close() }; pins.removeAll() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SnipX · 设置与使用说明"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "把屏幕上的灵感留下来。")
        title.font = .systemFont(ofSize: 26, weight: .semibold); stack.addArrangedSubview(title)
        let description = NSTextField(wrappingLabelWithString: "菜单栏截图工具 · Apple Silicon\n区域、窗口、全屏、标注、长截图、置顶贴图")
        description.textColor = .secondaryLabelColor; stack.addArrangedSubview(description)
        let label = NSTextField(labelWithString: "全局截图快捷键（点击后按新组合键）")
        stack.addArrangedSubview(label)
        let shortcut = ShortcutField(labelWithString: shortcutLabel)
        shortcut.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        shortcut.isBordered = true; shortcut.drawsBackground = true
        shortcut.onShortcut = { [weak self, weak shortcut] key, mods, label in
            guard let self else { return }
            do {
                try self.hotKey.register(keyCode: key, modifiers: mods)
                UserDefaults.standard.set(key, forKey: "shortcutKey"); UserDefaults.standard.set(mods, forKey: "shortcutModifiers"); UserDefaults.standard.set(label, forKey: "shortcutLabel")
                shortcut?.stringValue = label; self.rebuildMenu(); self.item.button?.toolTip = "SnipX · \(label)"
            } catch { shortcut?.stringValue = self.shortcutLabel; self.showError(error) }
        }
        stack.addArrangedSubview(shortcut)
        let instructions = NSTextField(wrappingLabelWithString: "1. 授予屏幕录制权限，然后按快捷键。\n2. 框选后拖动边框调整、内部移动，按 Enter 确认。\n3. 添加画笔、直线、矩形和文字，再复制、保存或置顶。\n4. 长截图时框选并确认内容区，缓慢向下滚动，再点「完成」。\n\n贴图可拖动、缩放；右键可复制、保存、调整透明度或关闭。\n所有截图仅在本机处理，不会上传。")
        instructions.font = .systemFont(ofSize: 13); stack.addArrangedSubview(instructions)
        let permission = NSButton(title: "授权屏幕录制 / 打开系统设置", target: self, action: #selector(openPermissions))
        permission.bezelStyle = .rounded; stack.addArrangedSubview(permission)
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        settings = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openPermissions() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    private func showError(_ error: Error) { NSApp.activate(ignoringOtherApps: true); NSAlert(error: error).runModal() }
    func applicationWillTerminate(_ notification: Notification) { overlay.close(); scrolling?.cancel() }
}
