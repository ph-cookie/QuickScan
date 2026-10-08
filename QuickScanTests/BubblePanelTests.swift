#if !SWIFT_PACKAGE
import XCTest
import AppKit
final class BubblePanelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NSApplication.shared.setActivationPolicy(.accessory)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(Timing.keyGuard + 0.05)) }
    private func send(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws {
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? KeyPanel }.first { $0.isVisible })
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        if flags.contains(.command) { XCTAssertTrue(panel.performKeyEquivalent(with: event)) }
        else { panel.sendEvent(event) }
    }
    private func assessment(_ text: String) throws -> URLAssessment {
        guard case .url(let result) = ResultClassifier.classify(text) else { throw NSError(domain: "fixture", code: 1) }; return result
    }
    func testNormalURLAndInitialGuard() throws {
        let bubble = BubblePanel(); defer { bubble.close() }
        var opened = false; bubble.onOpen = { _ in opened = true }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        bubble.show(url: try assessment("https://example.com"), near: NSEvent.mouseLocation)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        try send(36); XCTAssertFalse(opened); XCTAssertTrue(bubble.isVisible)
        try send(53); XCTAssertTrue(bubble.isVisible)
        settle(); try send(36); XCTAssertTrue(opened); XCTAssertFalse(bubble.isVisible)
    }
    func testWarningRequiresOptionReturn() throws {
        let bubble = BubblePanel(); defer { bubble.close() }
        var opened = false; bubble.onOpen = { _ in opened = true }
        bubble.show(url: try assessment("https://127.0.0.1"), near: NSEvent.mouseLocation)
        settle(); try send(36); XCTAssertFalse(opened); XCTAssertTrue(bubble.isVisible)
        try send(36, flags: .option); XCTAssertTrue(opened); XCTAssertFalse(bubble.isVisible)
    }
    func testCopyPreservesRawAndCloses() throws {
        let bubble = BubblePanel(); defer { bubble.close() }
        let raw = "https://bücher.de/path"; var copied = ""
        bubble.onCopy = { copied = $0 }
        bubble.show(url: try assessment(raw), near: NSEvent.mouseLocation)
        settle(); try send(8, flags: .command); XCTAssertEqual(copied, raw); XCTAssertFalse(bubble.isVisible)
    }
    func testMultipleSelectionAndCameraHint() throws {
        let bubble = BubblePanel(); defer { bubble.close() }
        let codes = [ScanCode(value: "a", format: "QR"), ScanCode(value: "b", format: "QR")]
        var selected: ScanCode?; bubble.onChoose = { code, _ in selected = code }
        bubble.show(codes: codes, near: NSEvent.mouseLocation)
        settle(); try send(125); try send(36); XCTAssertEqual(selected, codes[1])
        var camera = false; bubble.onCamera = { camera = true }
        bubble.show(message: "見つかりません", cameraHint: true, near: NSEvent.mouseLocation)
        settle(); try send(8); XCTAssertTrue(camera); XCTAssertFalse(bubble.isVisible)
    }
    func testPanelClampsToScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let p = floatingPanel(size: NSSize(width: 480, height: 230), near: NSPoint(x: screen.visibleFrame.maxX - 1, y: screen.visibleFrame.minY + 1))
        defer { p.close() }
        XCTAssertTrue(screen.visibleFrame.contains(p.frame))
    }
}
#endif
