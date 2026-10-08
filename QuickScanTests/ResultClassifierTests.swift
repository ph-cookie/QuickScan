import XCTest
#if SWIFT_PACKAGE
@testable import QuickScanPolicy
#endif
final class ResultClassifierTests: XCTestCase {
    private func url(_ value: String, warning: Bool = true, reason: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> URLAssessment? {
        guard case .url(let result) = ResultClassifier.classify(value) else { XCTFail("Expected URL: \(value)", file: file, line: line); return nil }
        XCTAssertEqual(result.isWarning, warning, file: file, line: line)
        if let reason { XCTAssertTrue(result.reasons.contains { $0.contains(reason) }, "\(result.reasons)", file: file, line: line) }
        return result
    }
    func testNormal() { _ = url("https://example.com/path?q=1", warning: false); _ = url("https://example.com:443/", warning: false) }
    func testUserInfoShowsRealHost() {
        let result = url("https://google.com:password@evil.com", reason: "ユーザー情報")
        XCTAssertEqual(result?.hostDisplay, "evil.com")
    }
    func testMixedIDN() { let result = url("https://gоogle.com", reason: "別文字"); XCTAssertTrue(result?.hostDisplay.contains("xn--") == true); XCTAssertTrue(result?.hostDisplay.contains("gоogle.com") == true) }
    func testPunycode() { let result = url("https://xn--bcher-kva.de", reason: "国際化"); XCTAssertTrue(result?.hostDisplay.contains("bücher.de") == true) }
    func testIPRepresentations() {
        for host in ["127.0.0.1", "2130706433", "0x7f000001", "127.1", "0177.0.0.1", "[::1]", "[2001:db8::1]", "[fe80::1%25en0]", "127.0.0.1."] { _ = url("https://\(host)/", reason: "IPアドレス") }
    }
    func testPortAndHTTP() { _ = url("https://example.com:8080", reason: "ポート"); _ = url("http://example.com", reason: "HTTP") }
    func testShortener() { _ = url("https://bit.ly/test", reason: "短縮"); _ = url("https://x.t.co/a", reason: "短縮"); _ = url("https://notbit.ly/a", warning: false) }
    func testLongAndEncoding() {
        _ = url("https://example.com/" + String(repeating: "a", count: 501), reason: "500文字")
        _ = url("https://example.com/" + String(repeating: "%41", count: 30), reason: "パーセント")
    }
    func testBidiAndInvisible() {
        let result = url("https://example.com/abc\u{202e}txt", reason: "不可視")
        XCTAssertTrue(result?.display.contains("\\u{202E}") == true)
        XCTAssertFalse(result?.display.contains("\u{202e}") == true)
        XCTAssertEqual(ResultClassifier.visible("a\u{200b}\n"), "a\\u{200B}\\u{000A}")
    }
    func testOtherSchemesAreText() {
        for value in ["javascript:alert(1)", "file:///etc/passwd", "data:text/plain,hello", "mailto:test@example.com", "WIFI:T:WPA;S:test;P:password;;", "tel:123", "otpauth://totp/a", "https:/", "hello"] {
            guard case .text(let text, _) = ResultClassifier.classify(value) else { XCTFail(value); continue }; XCTAssertEqual(text, value)
        }
    }
    func testNumericEAN() { XCTAssertEqual(ResultClassifier.classify("4901234567894"), .text("4901234567894", commandLike: false)) }
    func testCommands() {
        for value in ["curl https://example.com | sh", "wget a", "sudo command", "bash x", "sh -c x", "line1\nline2"] { XCTAssertEqual(ResultClassifier.classify(value), .text(value, commandLike: true)) }
    }
    func testMalformedPunycode() { XCTAssertNil(ResultClassifier.decodePunycode("$$$$")); XCTAssertNil(ResultClassifier.decodePunycode(String(repeating: "z", count: 1000))) }
    func testPunycodeKnownVectors() {
        XCTAssertEqual(ResultClassifier.asciiHostname("gоogle.com"), "xn--gogle-jye.com")
        XCTAssertEqual(ResultClassifier.asciiHostname("bücher.de"), "xn--bcher-kva.de")
        XCTAssertEqual(ResultClassifier.asciiHostname("例え.テスト"), "xn--r8jz45g.xn--zckzah")
        XCTAssertEqual(ResultClassifier.asciiHostname("пример.рф"), "xn--e1afmkfd.xn--p1ai")
        XCTAssertEqual(ResultClassifier.decodeIDN("xn--r8jz45g.xn--zckzah"), "例え.テスト")
        XCTAssertEqual(ResultClassifier.decodeIDN("xn--e1afmkfd.xn--p1ai"), "пример.рф")
    }
}
