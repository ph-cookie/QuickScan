import AppKit
import Carbon

struct KeyBinding: Equatable {
    var code: UInt32
    var modifiers: UInt32
    static let screen = KeyBinding(code: 12, modifiers: UInt32(optionKey | cmdKey))
    static let camera = KeyBinding(code: 12, modifiers: UInt32(optionKey | cmdKey | shiftKey))
    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0, count = 0, chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 8, &count, &chars)
            if status == noErr, count > 0 { return s + String(utf16CodeUnits: chars, count: count).uppercased() }
        }
        return s + "Key \(code)"
    }
}
final class HotKey {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    var pressed: ((Int) -> Void)?
    init() {
        let callback: EventHandlerUPP = { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            guard id.signature == 0x5153434e else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(pointer).takeUnretainedValue().pressed?(Int(id.id))
            return noErr
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ bindings: [KeyBinding]) -> [String] {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        guard handlerStatus == noErr else { return ["ホットキーイベントを設定できません（エラー \(handlerStatus)）"] }
        var errors: [String] = []
        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x5153434e, id: UInt32(index))
            let status = RegisterEventHotKey(binding.code, binding.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { errors.append("\(index == 0 ? "画面" : "カメラ"): \(binding.label) を登録できません（競合など、エラー \(status)）") }
        }
        return errors
    }
    deinit { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
}
