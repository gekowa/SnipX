import AppKit
import Carbon

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { owner.action?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(keyCode: UInt32, modifiers: UInt32) throws {
        var candidate: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x534E5058, id: 1), GetApplicationEventTarget(), 0, &candidate)
        guard result == noErr else { throw SnipError.message("快捷键不可用（错误 \(result)），请尝试其他组合。") }
        if let reference { UnregisterEventHotKey(reference) }
        reference = candidate
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ShortcutField: NSTextField {
    var onShortcut: ((UInt32, UInt32, String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); stringValue = "请按新的组合键…" }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            stringValue = "请包含 ⌘、⌃ 或 ⌥ 修饰键"; return
        }
        var modifiers: UInt32 = 0; var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        label += characters.uppercased()
        onShortcut?(UInt32(event.keyCode), modifiers, label)
        window?.makeFirstResponder(nil)
    }
}
