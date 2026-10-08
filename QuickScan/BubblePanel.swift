import AppKit

enum Timing {
    static let keyGuard: TimeInterval = 0.4
    static let bubbleIdle: TimeInterval = 15
    static let cameraIdle: TimeInterval = 30
    static let fade: TimeInterval = 0.12
}
final class KeyPanel: NSPanel {
    var keyAction: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { keyAction?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 8 { keyAction?(event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
func floatingPanel(size: NSSize, near point: NSPoint) -> KeyPanel {
    let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.hidesOnDeactivate = false; panel.hasShadow = true; panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    placeFloatingPanel(panel, size: size, near: point)
    return panel
}
func placeFloatingPanel(_ panel: NSPanel, size: NSSize, near point: NSPoint) {
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
    let origin = NSPoint(x: min(max(point.x + 12, bounds.minX), bounds.maxX - size.width), y: min(max(point.y - size.height - 12, bounds.minY), bounds.maxY - size.height))
    panel.setFrame(NSRect(origin: origin, size: size), display: false)
}
func hudView() -> NSVisualEffectView { HUDView(frame: .zero) }
func label(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    field.isSelectable = false
    return field
}

final class BubblePanel {
    private var panel: KeyPanel?
    private var timer: Timer?
    private var shownAt = ProcessInfo.processInfo.systemUptime
    private var index = 0
    private var anchor = NSPoint.zero
    private var codes: [ScanCode] = []
    private var assessment: URLAssessment?
    private var message = ""
    private var cameraHint = false
    var onDismiss: (() -> Void)?
    var onChoose: ((ScanCode, NSPoint) -> Void)?
    var onCamera: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    var onCopy: ((String) -> Void)?
    var isVisible: Bool { panel != nil }
    func show(url: URLAssessment, near point: NSPoint) {
        reset(); assessment = url; present(near: point)
    }
    func show(codes: [ScanCode], near point: NSPoint) {
        reset(); self.codes = codes; present(near: point)
    }
    func show(message: String, cameraHint: Bool = false, near point: NSPoint) {
        reset(); self.message = message; self.cameraHint = cameraHint; present(near: point)
    }
    private func reset() {
        close(notify: false); codes = []; assessment = nil; message = ""; index = 0; cameraHint = false
    }
    private func present(near point: NSPoint) {
        let size = NSSize(width: 500, height: codes.isEmpty ? 270 : 356)
        let p = floatingPanel(size: size, near: point)
        panel = p; anchor = point; redraw()
        p.keyAction = { [weak self] event in self?.key(event) }
        shownAt = ProcessInfo.processInfo.systemUptime
        p.alphaValue = 0; p.orderFrontRegardless(); p.makeKey(); p.makeFirstResponder(p)
        NSAnimationContext.runAnimationGroup { $0.duration = Timing.fade; p.animator().alphaValue = 1 }
        armTimer()
    }
    private func redraw() {
        guard let p = panel else { return }
        let view = hudView(); p.contentView = view
        UIStyle.pin(SurfaceView(fill: UIStyle.surface.withAlphaComponent(0.86), radius: 20), to: view, inset: 0)
        let stack = UIStyle.stack([], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20)])
        func add(_ child: NSView) {
            stack.addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func heading(_ title: String, symbol: String, warning: Bool = false) {
            add(UIStyle.stack([UIStyle.symbol(symbol, color: warning ? .systemRed : UIStyle.accent, size: 15), UIStyle.text(title, size: 11, weight: .semibold, color: .secondaryLabelColor)], vertical: false, spacing: 6))
        }
        func hints(_ entries: [(String, String)]) {
            add(UIStyle.divider())
            let first = UIStyle.hint(entries[0].0, entries[0].1)
            let rest = UIStyle.stack(entries.dropFirst().map { UIStyle.hint($0.0, $0.1) }, vertical: false, spacing: 18)
            add(UIStyle.row(first, rest))
        }
        if let url = assessment {
            heading(url.isWarning ? "リンクの確認が必要です" : "リンクを開く", symbol: url.isWarning ? "exclamationmark.shield" : "link", warning: url.isWarning)
            let host = UIStyle.text(url.hostDisplay, size: 23, weight: .semibold)
            host.toolTip = url.hostDisplay; host.maximumNumberOfLines = 2; host.lineBreakMode = .byTruncatingMiddle; add(host)
            let full = UIStyle.text(url.display, size: 12, color: .secondaryLabelColor)
            full.toolTip = url.display; full.maximumNumberOfLines = 3; full.lineBreakMode = .byTruncatingMiddle; add(full)
            if url.isWarning {
                let warning = UIStyle.text((url.reasons.first ?? "") + (url.reasons.count > 1 ? "（他\(url.reasons.count - 1)件）" : ""), size: 12, weight: .medium, color: .systemRed)
                warning.toolTip = url.reasons.joined(separator: "\n")
                warning.maximumNumberOfLines = 1; warning.lineBreakMode = .byTruncatingMiddle; add(warning)
            }
            hints([(url.isWarning ? "⌥Return" : "Return", "開く"), ("⌘C", "コピー"), ("esc", "閉じる")])
        } else if !codes.isEmpty {
            heading("\(codes.count)件のコード", symbol: "qrcode.viewfinder")
            add(UIStyle.text("コードを選択", size: 22, weight: .semibold))
            let start = max(0, min(index - 2, codes.count - min(5, codes.count)))
            for row in start..<min(start + 5, codes.count) {
                let selected = row == index, code = codes[row]
                let text = UIStyle.text("\(row + 1).  [\(code.format)]  \(ResultClassifier.visible(String(code.value.prefix(65))))", weight: selected ? .semibold : .regular)
                text.maximumNumberOfLines = 1; text.lineBreakMode = .byTruncatingMiddle
                let card = SurfaceView(fill: selected ? UIStyle.accent.withAlphaComponent(0.12) : .clear, radius: 8)
                UIStyle.pin(text, to: card, inset: 8); add(card)
            }
            hints([("↑↓", "選択"), ("Return", "確定"), ("esc", "閉じる")])
        } else {
            let missing = cameraHint
            heading(missing ? "コードが見つかりません" : "読み取り結果", symbol: missing ? "viewfinder" : "doc.on.clipboard")
            let field = UIStyle.text(message, size: 15, weight: .medium)
            field.maximumNumberOfLines = 7; add(field)
            hints(cameraHint ? [("C", "カメラで読む"), ("esc", "閉じる")] : [("esc", "閉じる")])
        }
        view.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height) + 40
        placeFloatingPanel(p, size: NSSize(width: 500, height: height), near: anchor)
    }
    private func armTimer() {
        timer?.invalidate(); timer = nil
        guard assessment?.isWarning != true else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Timing.bubbleIdle, repeats: false) { [weak self] _ in self?.close(fade: true) }
    }
    private func key(_ event: NSEvent) {
        guard ProcessInfo.processInfo.systemUptime - shownAt >= Timing.keyGuard else { return }
        armTimer()
        if event.keyCode == 53 { close(); return }
        if event.keyCode == 8, event.modifierFlags.contains(.command), let url = assessment {
            onCopy?(url.raw); close(); return
        }
        if cameraHint, event.keyCode == 8, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            close(); onCamera?(); return
        }
        if !codes.isEmpty {
            if event.keyCode == 125 { index = (index + 1) % codes.count; redraw() }
            if event.keyCode == 126 { index = (index + codes.count - 1) % codes.count; redraw() }
            if event.keyCode == 36 {
                let code = codes[index], point = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? NSEvent.mouseLocation
                close(); onChoose?(code, point)
            }
        } else if event.keyCode == 36, let url = assessment {
            guard !url.isWarning || event.modifierFlags.contains(.option) else { return }
            close(); onOpen?(url.url)
        }
    }
    func close(notify: Bool = true, fade: Bool = false) {
        timer?.invalidate(); timer = nil
        guard let old = panel else { return }
        panel = nil; old.keyAction = nil
        if fade {
            NSAnimationContext.runAnimationGroup({ $0.duration = Timing.fade; old.animator().alphaValue = 0 }, completionHandler: { old.close() })
        } else { old.close() }
        assessment = nil; codes = []
        if notify { onDismiss?() }
    }
    deinit { timer?.invalidate() }
}
