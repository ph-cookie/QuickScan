import AppKit

/// Small AppKit building blocks; no animation loops or third-party fonts.
enum UIStyle {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let canvas = adaptive(0xE4E0D7, 0x151515)
    static let surface = adaptive(0xFAF9F6, 0x222222)
    static let stroke = adaptive(0xCEC9BE, 0x3B3B38)
    static let accent = adaptive(0x427A0B, 0x9BEE32)
    static func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = label(value, size: size)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
        return field
    }
    static func symbol(_ name: String, color: NSColor = accent, size: CGFloat = 18) -> NSImageView {
        let image = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: size, weight: .medium)
        image.contentTintColor = color
        image.widthAnchor.constraint(equalToConstant: size + 8).isActive = true
        image.heightAnchor.constraint(equalToConstant: size + 8).isActive = true
        return image
    }
    static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY; stack.spacing = spacing
        return stack
    }
    static func row(_ leading: NSView, _ trailing: NSView, spacing: CGFloat = 18) -> NSStackView {
        let row = stack([], vertical: false, spacing: spacing)
        row.addView(leading, in: .leading); row.addView(trailing, in: .trailing)
        return row
    }
    static func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 18) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    static func divider() -> NSView {
        let line = SurfaceView(fill: stroke, radius: 0)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
    static func hint(_ key: String, _ action: String) -> NSView {
        let capsule = SurfaceView(fill: surface, radius: 5, border: stroke)
        let keyLabel = text(key, size: 11, weight: .medium)
        keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        pin(keyLabel, to: capsule, inset: 5)
        capsule.widthAnchor.constraint(equalToConstant: keyLabel.intrinsicContentSize.width + 10).isActive = true
        return stack([capsule, text(action, size: 11, color: .secondaryLabelColor)], vertical: false, spacing: 5)
    }
}
final class SurfaceView: NSView {
    private let fill: NSColor
    private let radius: CGFloat
    private let border: NSColor?
    init(fill: NSColor, radius: CGFloat = 16, border: NSColor? = nil) {
        self.fill = fill; self.radius = radius; self.border = border
        super.init(frame: .zero); wantsLayer = true; refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor; layer?.cornerRadius = radius
            layer?.borderWidth = border == nil ? 0 : 1; layer?.borderColor = border?.cgColor
        }
    }
}
final class HUDView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 20; layer?.masksToBounds = true; layer?.borderWidth = 1
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    private func refresh() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = UIStyle.stroke.withAlphaComponent(0.7).cgColor } }
}
