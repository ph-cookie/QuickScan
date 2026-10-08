import AppKit
import AVFoundation

final class CameraScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let queue = DispatchQueue(label: "org.quickscan.camera", qos: .userInitiated, autoreleaseFrequency: .workItem)
    // Session/output/devices live only for this scanner's active lifetime.
    private var session: AVCaptureSession?
    private var output: AVCaptureMetadataOutput?
    private var devices: [AVCaptureDevice] = []
    private var deviceIndex = 0
    private var stopping = false
    private var panel: KeyPanel?
    private var preview: AVCaptureVideoPreviewLayer?
    private var timer: Timer?
    private let all: Bool
    private let anchor: NSPoint
    var finished: (([ScanCode]?, String?, NSPoint) -> Void)?
    init(all: Bool, near anchor: NSPoint) { self.all = all; self.anchor = anchor; super.init() }
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { guard let self, self.panel != nil else { return }; allowed ? self.configure() : self.permissionPanel() }
            }
            loadingPanel("カメラの許可を待っています…")
        default: permissionPanel()
        }
    }
    private func loadingPanel(_ message: String) {
        if panel == nil {
            let p = floatingPanel(size: NSSize(width: 380, height: 280), near: anchor)
            panel = p; p.keyAction = { [weak self] event in
                if event.keyCode == 53 { self?.stop() }
                else { self?.armTimer(); if event.keyCode == 48 { self?.switchCamera() } }
            }
            p.orderFrontRegardless(); p.makeKey(); p.makeFirstResponder(p)
        }
        let view = hudView(); panel?.contentView = view
        let field = label(message, size: 15)
        field.frame = NSRect(x: 18, y: 160, width: 344, height: 90); view.addSubview(field)
        armTimer()
    }
    private func permissionPanel() {
        loadingPanel("カメラを許可してください。\nシステム設定 → プライバシーとセキュリティ → カメラ\nEsc: 閉じる")
        let button = NSButton(title: "システム設定を開く", target: self, action: #selector(openPermission))
        button.frame = NSRect(x: 18, y: 95, width: 240, height: 32); panel?.contentView?.addSubview(button)
    }
    @objc private func openPermission() { Settings.openPrivacy(camera: true) }
    private func configure() {
        loadingPanel("カメラを起動しています…")
        queue.async { [self] in
            guard !stopping else { return }
            let types: [AVCaptureDevice.DeviceType]
            if #available(macOS 14.0, *) { types = [.builtInWideAngleCamera, .external, .continuityCamera] }
            else { types = [.builtInWideAngleCamera, .externalUnknown] }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
            if let preferred = AVCaptureDevice.default(for: .video), let idx = devices.firstIndex(where: { $0.uniqueID == preferred.uniqueID }) { deviceIndex = idx }
            guard !devices.isEmpty else { finishOnQueue(codes: nil, error: "カメラが見つかりません"); return }
            do {
                let s = AVCaptureSession(); s.beginConfiguration()
                s.sessionPreset = .medium
                let input = try AVCaptureDeviceInput(device: devices[deviceIndex])
                guard s.canAddInput(input) else { throw CameraError.unavailable }; s.addInput(input)
                let o = AVCaptureMetadataOutput()
                guard s.canAddOutput(o) else { throw CameraError.unavailable }; s.addOutput(o)
                o.setMetadataObjectsDelegate(self, queue: queue)
                o.metadataObjectTypes = Decoder.enabled(all: all).map(\.camera).filter { o.availableMetadataObjectTypes.contains($0) }
                s.commitConfiguration(); session = s; output = o
                s.startRunning()
                guard s.isRunning else { throw CameraError.unavailable }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let p = self.panel else { return }
                    let view = hudView(); p.contentView = view
                    let layer = AVCaptureVideoPreviewLayer(session: s)
                    layer.videoGravity = .resizeAspect; layer.frame = NSRect(x: 0, y: 40, width: 380, height: 240)
                    if let connection = layer.connection, connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
                    }
                    view.layer?.addSublayer(layer); self.preview = layer
                    let field = label("Tab: カメラ切替   Esc: 閉じる   30秒で終了", size: 12)
                    field.frame = NSRect(x: 14, y: 10, width: 355, height: 25); view.addSubview(field)
                    self.armTimer()
                }
            } catch { finishOnQueue(codes: nil, error: "カメラを開始できませんでした: \(error.localizedDescription)") }
        }
    }
    private func switchCamera() {
        queue.async { [self] in
            guard !stopping, devices.count > 1, let s = session else { return }
            do {
                let next = (deviceIndex + 1) % devices.count
                let input = try AVCaptureDeviceInput(device: devices[next])
                s.beginConfiguration()
                let previous = s.inputs
                previous.forEach { s.removeInput($0) }
                if s.canAddInput(input) { s.addInput(input); deviceIndex = next }
                else { previous.forEach { if s.canAddInput($0) { s.addInput($0) } } }
                if let o = output { o.metadataObjectTypes = Decoder.enabled(all: all).map(\.camera).filter { o.availableMetadataObjectTypes.contains($0) } }
                s.commitConfiguration()
                DispatchQueue.main.async { [weak self] in
                    if let c = self?.preview?.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = false }
                }
            } catch { finishOnQueue(codes: nil, error: "カメラを切り替えられませんでした") }
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let codes = Decoder.unique(metadataObjects.compactMap { object -> ScanCode? in
            guard let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue else { return nil }
            return Decoder.code(value, name: Decoder.formats.first { $0.camera == code.type }?.name ?? code.type.rawValue)
        })
        if !codes.isEmpty { finishOnQueue(codes: codes, error: nil) }
    }
    private func armTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Timing.cameraIdle, repeats: false) { [weak self] _ in self?.stop() }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        preview?.session = nil; preview?.removeFromSuperlayer(); preview = nil
        queue.async { [self] in finishOnQueue(codes: nil, error: nil) }
    }
    private func finishOnQueue(codes: [ScanCode]?, error: String?) {
        guard !stopping else { return }; stopping = true
        output?.setMetadataObjectsDelegate(nil, queue: nil)
        session?.stopRunning()
        session?.inputs.forEach { session?.removeInput($0) }
        session?.outputs.forEach { session?.removeOutput($0) }
        output = nil; session = nil; devices = []
        DispatchQueue.main.async { [self] in
            timer?.invalidate(); timer = nil
            let point = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? anchor
            preview?.session = nil; preview?.removeFromSuperlayer(); preview = nil
            panel?.keyAction = nil; panel?.close(); panel = nil
            let callback = finished; finished = nil; callback?(codes, error, point)
        }
    }
    enum CameraError: Error { case unavailable }
}
