import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, screen, camera, bubble }
    private var state = State.idle
    private let preferences = Preferences()
    private let hotKeys = HotKey()
    private let bubble = BubblePanel()
    private var settings: Settings!
    private var camera: CameraScanner?
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenCapture.cleanup()
        settings = Settings(preferences: preferences)
        settings.bindingsChanged = { [weak self] in self?.registerKeys() ?? [] }
        settings.recordingChanged = { [weak self] active in
            guard let self else { return }
            if active { _ = self.hotKeys.register([]) }
            else { self.settings.updateErrors(self.registerKeys()) }
        }
        hotKeys.pressed = { [weak self] id in self?.begin(cameraMode: id == 1) }
        bubble.onDismiss = { [weak self] in self?.state = .idle }
        bubble.onCamera = { [weak self] in self?.begin(cameraMode: true) }
        bubble.onChoose = { [weak self] code, point in self?.handle(code, near: point) }
        bubble.onCopy = { Self.copy($0) }
        bubble.onOpen = { url in
            // Final defensive guard: scan-derived data can only open HTTP(S).
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return }
            NSWorkspace.shared.open(url)
        }
        let errors = registerKeys()
        if preferences.firstLaunch || !errors.isEmpty { settings.show() }
        preferences.markLaunched()
    }
    private func registerKeys() -> [String] { hotKeys.register([preferences.binding(0), preferences.binding(1)]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { settings.show(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { camera?.stop(); ScreenCapture.cancel() }
    private func begin(cameraMode: Bool) {
        if state == .bubble { bubble.close(); state = .idle }
        guard state == .idle else { return }
        let point = NSEvent.mouseLocation
        if cameraMode {
            state = .camera
            let scanner = CameraScanner(all: preferences.allFormats, near: point); camera = scanner
            scanner.finished = { [weak self] codes, error, anchor in
                guard let self else { return }
                camera = nil; state = .idle
                if let error { showMessage(error, near: anchor) }
                else if let codes { handle(codes, near: anchor) }
            }
            scanner.start()
        } else {
            state = .screen
            ScreenCapture.start(all: preferences.allFormats) { [weak self] result in
                guard let self else { return }; state = .idle
                switch result {
                case .success(nil): break
                case .success(let codes?):
                    if codes.isEmpty { showMessage("見つかりません。左右の余白も含めて選択してください", cameraHint: true, near: NSEvent.mouseLocation) }
                    else { handle(codes, near: NSEvent.mouseLocation) }
                case .failure(let error): showMessage(error.localizedDescription, near: NSEvent.mouseLocation)
                }
            }
        }
    }
    private func handle(_ codes: [ScanCode], near point: NSPoint) {
        if codes.count == 1 { handle(codes[0], near: point) }
        else { state = .bubble; bubble.show(codes: codes, near: point) }
    }
    private func handle(_ code: ScanCode, near point: NSPoint) {
        switch ResultClassifier.classify(code.value) {
        case .url(let url): state = .bubble; bubble.show(url: url, near: point)
        case .text(let text, let command):
            let numeric = !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
            Self.copy(numeric ? "\(code.format): \(text)" : text)
            let message = "[\(code.format)] \(ResultClassifier.visible(String(text.prefix(40))))\(text.count > 40 ? "…" : "")\nコピーしました" + (command ? "\n⚠ コマンドのように見えます。貼り付ける前に内容を確認してください" : "")
            showMessage(message, near: point)
            if preferences.notifications {
                let content = UNMutableNotificationContent(); content.title = "QuickScan — コピーしました"; content.body = message
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
    private func showMessage(_ message: String, cameraHint: Bool = false, near point: NSPoint) {
        state = .bubble; bubble.show(message: message, cameraHint: cameraHint, near: point)
    }
    private static func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
