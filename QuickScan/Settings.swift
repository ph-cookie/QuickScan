import AppKit
import Carbon
import AVFoundation
import ServiceManagement
import UserNotifications

final class Preferences {
    private let defaults = UserDefaults.standard
    var allFormats: Bool { get { defaults.bool(forKey: "allFormats") } set { defaults.set(newValue, forKey: "allFormats") } }
    var notifications: Bool { get { defaults.bool(forKey: "notifications") } set { defaults.set(newValue, forKey: "notifications") } }
    var firstLaunch: Bool { !defaults.bool(forKey: "launched") }
    func markLaunched() { defaults.set(true, forKey: "launched") }
    func binding(_ index: Int) -> KeyBinding {
        let fallback = index == 0 ? KeyBinding.screen : .camera
        guard defaults.object(forKey: "key\(index)") != nil else { return fallback }
        return KeyBinding(code: UInt32(defaults.integer(forKey: "key\(index)")), modifiers: UInt32(defaults.integer(forKey: "mods\(index)")))
    }
    func setBinding(_ binding: KeyBinding, index: Int) {
        defaults.set(Int(binding.code), forKey: "key\(index)"); defaults.set(Int(binding.modifiers), forKey: "mods\(index)")
    }
}
final class KeyRecorder: NSButton {
    var binding = KeyBinding.screen { didSet { title = binding.label } }
    var changed: ((KeyBinding) -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    private var recording = false { didSet { if oldValue != recording { recordingChanged?(recording) } } }
    override var acceptsFirstResponder: Bool { true }
    init() { super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(record) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func record() { recording = true; title = "キー入力中…（Escで取消）"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool { recording = false; title = binding.label; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = binding.label; return }
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { title = "⌘ / ⌃ / ⌥ を含める"; return }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        binding = KeyBinding(code: UInt32(event.keyCode), modifiers: mods); recording = false; changed?(binding)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
}
final class Settings: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let preferences: Preferences
    private var screenStatus: NSTextField?
    private var cameraStatus: NSTextField?
    private var errorField: NSTextField?
    private var notificationToggle: NSSwitch?
    var bindingsChanged: (() -> [String])?
    var recordingChanged: ((Bool) -> Void)?
    init(preferences: Preferences) { self.preferences = preferences }
    func show() {
        if window == nil { build() }
        updatePermissions(); updateErrors(bindingsChanged?() ?? [])
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func updateErrors(_ errors: [String]) { errorField?.stringValue = errors.joined(separator: "\n"); errorField?.isHidden = errors.isEmpty }
    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 750), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "QuickScan 設定"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
        w.backgroundColor = UIStyle.canvas; w.isReleasedWhenClosed = false; w.delegate = self; w.center(); window = w
        let canvas = SurfaceView(fill: UIStyle.canvas, radius: 0); w.contentView = canvas
        let stack = UIStyle.stack([], spacing: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 20)])
        func add(_ child: NSView) { stack.addArrangedSubview(child); child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        func row(_ title: String, detail: String, control: NSView) -> NSView {
            let copy = UIStyle.stack([UIStyle.text(title, weight: .medium), UIStyle.text(detail, size: 11, color: .secondaryLabelColor)], spacing: 3)
            copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .horizontal)
            let row = UIStyle.row(copy, control)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return row
        }
        func section(_ title: String, rows: [NSView]) {
            let card = SurfaceView(fill: UIStyle.surface, border: UIStyle.stroke)
            let body = UIStyle.stack([], spacing: 0)
            for (i, row) in rows.enumerated() {
                if i > 0 { let line = UIStyle.divider(); body.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
                body.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }
            UIStyle.pin(body, to: card, inset: 15)
            let group = UIStyle.stack([UIStyle.text(title, size: 11, weight: .semibold, color: .secondaryLabelColor), card], spacing: 8)
            card.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true; add(group)
        }
        let icon = NSImageView(image: Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true; icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        add(UIStyle.stack([icon, UIStyle.stack([UIStyle.text("QuickScan", size: 26, weight: .semibold), UIStyle.text("画面とカメラから、コードをすばやく読み取る。", size: 12, color: .secondaryLabelColor)], spacing: 4)], vertical: false, spacing: 12))
        let errors = UIStyle.text("", size: 12, color: .systemRed)
        errors.maximumNumberOfLines = 3; errors.isHidden = true; errorField = errors; add(errors)
        var scanRows: [NSView] = []
        for index in 0..<2 {
            let recorder = KeyRecorder(); recorder.binding = preferences.binding(index)
            recorder.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            recorder.toolTip = "クリックして変更。⌘ / ⌃ / ⌥ を含めてください。Escで取消。"
            recorder.recordingChanged = { [weak self] active in self?.recordingChanged?(active) }
            recorder.widthAnchor.constraint(equalToConstant: 180).isActive = true
            recorder.changed = { [weak self] binding in
                guard let self else { return }
                preferences.setBinding(binding, index: index); updateErrors(bindingsChanged?() ?? [])
            }
            scanRows.append(row(index == 0 ? "画面モード" : "カメラモード", detail: index == 0 ? "範囲を選んで読み取る" : "カメラをかざして読み取る", control: recorder))
        }
        let formats = NSPopUpButton(); formats.addItems(withTitles: ["標準: QR+JAN/UPC", "すべての対応形式"])
        formats.selectItem(at: preferences.allFormats ? 1 : 0); formats.target = self; formats.action = #selector(changeFormats(_:))
        scanRows.append(row("読み取る形式", detail: "JAN・UPCは商品検索せずコピー", control: formats)); section("読み取り", rows: scanRows)
        func toggle(_ title: String, detail: String, enabled: Bool, action: Selector) -> NSSwitch {
            let toggle = NSSwitch(); toggle.state = enabled ? .on : .off; toggle.target = self; toggle.action = action
            toggle.setAccessibilityLabel(title); return toggle
        }
        let login = toggle("ログイン時に起動", detail: "", enabled: SMAppService.mainApp.status == .enabled, action: #selector(changeLogin(_:)))
        let notifications = toggle("コピー時の通知", detail: "", enabled: preferences.notifications, action: #selector(changeNotifications(_:)))
        notificationToggle = notifications
        section("動作", rows: [row("ログイン時に起動", detail: "サインイン後にバックグラウンドで待機", control: login), row("コピー時にシステム通知", detail: "ONにすると通知の許可を求めます", control: notifications)])
        let screen = NSButton(title: "設定を開く", target: self, action: #selector(screenPrivacy)); screen.bezelStyle = .rounded
        let camera = NSButton(title: "設定を開く", target: self, action: #selector(cameraPrivacy)); camera.bezelStyle = .rounded
        let screenLabel = UIStyle.text(""); screenStatus = screenLabel
        let cameraLabel = UIStyle.text(""); cameraStatus = cameraLabel
        let screenRow = UIStyle.row(UIStyle.stack([UIStyle.symbol("rectangle.dashed", size: 15), screenLabel], vertical: false, spacing: 10), screen)
        let cameraRow = UIStyle.row(UIStyle.stack([UIStyle.symbol("camera", size: 15), cameraLabel], vertical: false, spacing: 10), camera)
        for field in [screenLabel, cameraLabel] { field.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        for row in [screenRow, cameraRow] { row.heightAnchor.constraint(equalToConstant: 40).isActive = true }
        let note = UIStyle.text("画面収録は最初の読み取り時に許可してください。\n権限の変更後は、再起動が必要な場合があります。", size: 11, color: .secondaryLabelColor)
        let refresh = NSButton(title: "更新", target: self, action: #selector(updatePermissions)); refresh.bezelStyle = .rounded; refresh.controlSize = .small
        section("アクセス許可", rows: [screenRow, cameraRow, UIStyle.row(note, refresh, spacing: 12)])
        let quit = NSButton(title: "QuickScanを終了", target: self, action: #selector(quit)); quit.bezelStyle = .rounded
        let footnote = UIStyle.text("設定は、アプリをもう一度開くと表示されます。", size: 11, color: .secondaryLabelColor)
        footnote.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add(UIStyle.row(footnote, quit, spacing: 12))
    }
    @objc private func changeFormats(_ sender: NSPopUpButton) { preferences.allFormats = sender.indexOfSelectedItem == 1 }
    @objc private func changeLogin(_ sender: NSSwitch) {
        do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { updateErrors(["ログイン起動を変更できません: \(error.localizedDescription)"]) }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { updateErrors(["システム設定 → 一般 → ログイン項目で許可してください"]) }
    }
    @objc private func changeNotifications(_ sender: NSSwitch) {
        preferences.notifications = sender.state == .on
        guard preferences.notifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if !granted { self.preferences.notifications = false; self.notificationToggle?.state = .off; self.updateErrors([error?.localizedDescription ?? "通知が許可されていません。システム設定の通知で変更できます"]) }
            }
        }
    }
    @objc private func updatePermissions() {
        let camera: String
        switch AVCaptureDevice.authorizationStatus(for: .video) { case .authorized: camera = "許可済み"; case .notDetermined: camera = "未確認"; default: camera = "未許可" }
        screenStatus?.stringValue = "画面収録  ·  \(CGPreflightScreenCaptureAccess() ? "許可済み" : "未許可")"
        cameraStatus?.stringValue = "カメラ  ·  \(camera)"
    }
    func windowWillClose(_ notification: Notification) { recordingChanged?(false); window = nil; screenStatus = nil; cameraStatus = nil; errorField = nil; notificationToggle = nil }
    func windowDidBecomeKey(_ notification: Notification) { updatePermissions() }
    @objc private func screenPrivacy() { Self.openPrivacy(camera: false) }
    @objc private func cameraPrivacy() { Self.openPrivacy(camera: true) }
    static func openPrivacy(camera: Bool) {
        // Trusted constant used only for Settings; scan payloads never reach this path.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(camera ? "Privacy_Camera" : "Privacy_ScreenCapture")") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
