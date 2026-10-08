import Foundation
import Darwin

struct URLAssessment: Equatable {
    let url: URL
    let raw: String
    let hostDisplay: String
    let display: String
    let reasons: [String]
    var isWarning: Bool { !reasons.isEmpty }
}
enum ClassifiedResult: Equatable {
    case url(URLAssessment)
    case text(String, commandLike: Bool)
}

/// Pure, offline policy. An optional future reputation service must be explicitly
/// opted into outside this function; it must never bypass the confirmation panel.
enum ResultClassifier {
    static let shorteners = ["bit.ly", "t.co", "tinyurl.com", "goo.gl", "ow.ly", "is.gd", "buff.ly", "rebrand.ly", "cutt.ly"]
    static func classify(_ raw: String) -> ClassifiedResult {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty else {
            let lower = raw.lowercased()
            let commands = ["curl", "wget", "sudo", "bash", "sh -c", "| sh"]
            return .text(raw, commandLike: raw.contains("\n") || raw.contains("\r") || commands.contains { lower.contains($0) })
        }
        let asciiHost = asciiHostname(host)
        let unicodeHost = decodeIDN(asciiHost)
        var reasons: [String] = []
        if url.user != nil || url.password != nil { reasons.append("ユーザー情報を含むURLです") }
        if asciiHost.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) || host.unicodeScalars.contains(where: { $0.value > 127 }) { reasons.append("国際化ドメインです（Punycodeを確認）") }
        if mixedScripts(unicodeHost) { reasons.append("見た目が似た別文字が混ざっています") }
        if isIP(asciiHost) { reasons.append("生のIPアドレスです") }
        if let port = url.port, port != 80 && port != 443 { reasons.append("非標準ポートを使用しています") }
        if scheme == "http" { reasons.append("暗号化されていないHTTPです") }
        let normalized = asciiHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if shorteners.contains(where: { normalized == $0 || normalized.hasSuffix("." + $0) }) { reasons.append("短縮URLです（行き先は未確認）") }
        if raw.count > 500 { reasons.append("URLが500文字を超えています") }
        let encoded = raw.utf8.filter { $0 == 37 }.count * 3
        if Double(encoded) / Double(max(raw.utf8.count, 1)) > 0.30 { reasons.append("パーセントエンコードが多すぎます") }
        if visible(raw) != raw || raw.removingPercentEncoding.map({ visible($0) != $0 }) == true { reasons.append("不可視文字・制御文字を含んでいます") }
        let shownHost = unicodeHost == asciiHost ? visible(asciiHost) : "\(visible(asciiHost))  /  \(visible(unicodeHost))"
        return .url(URLAssessment(url: url, raw: raw, hostDisplay: shownHost, display: visible(raw), reasons: reasons))
    }
    static func visible(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            let v = scalar.value
            let hidden = CharacterSet.controlCharacters.contains(scalar) || CharacterSet(charactersIn: "\u{00ad}\u{034f}\u{061c}\u{180e}\u{200b}\u{200c}\u{200d}\u{200e}\u{200f}\u{2028}\u{2029}\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2060}\u{2061}\u{2062}\u{2063}\u{2064}\u{2066}\u{2067}\u{2068}\u{2069}\u{feff}").contains(scalar)
            return hidden ? String(format: "\\u{%04X}", v) : String(scalar)
        }.joined()
    }
    static func isIP(_ host: String) -> Bool {
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[].")).split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var ipv6 = in6_addr()
        if value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 { return true }
        // inet_aton accepts IPv4 dotted, shortened, decimal, octal and hexadecimal forms.
        var ipv4 = in_addr()
        return value.withCString { inet_aton($0, &ipv4) } != 0
    }
    static func mixedScripts(_ host: String) -> Bool {
        // ICU Unicode script properties handle extended letters as well as base blocks.
        let names = ["Latin", "Cyrillic", "Greek", "Han", "Hiragana", "Katakana", "Hangul", "Arabic", "Hebrew", "Armenian", "Georgian", "Devanagari", "Bengali", "Thai", "Tamil", "Telugu", "Ethiopic", "Cherokee"]
        let range = NSRange(host.startIndex..<host.endIndex, in: host)
        var scripts = Set<String>()
        for name in names {
            if let expression = try? NSRegularExpression(pattern: "\\p{script=\(name)}"), expression.firstMatch(in: host, range: range) != nil {
                scripts.insert(["Han", "Hiragana", "Katakana"].contains(name) ? "Japanese" : name)
            }
        }
        return scripts.count > 1
    }
    static func asciiHostname(_ parsedHost: String) -> String {
        let host = (parsedHost.removingPercentEncoding ?? parsedHost).lowercased().precomposedStringWithCanonicalMapping
        return host.split(separator: ".", omittingEmptySubsequences: false).map { label in
            let value = String(label)
            guard value.unicodeScalars.contains(where: { $0.value > 127 }) else { return value }
            return encodePunycode(value).map { "xn--" + $0 } ?? value
        }.joined(separator: ".")
    }
    // Fallback for Foundation versions exposing Unicode instead of an ASCII host.
    static func encodePunycode(_ value: String) -> String? {
        let input = value.unicodeScalars.map { Int($0.value) }
        guard input.count <= 1024 else { return nil }
        var result = String(value.unicodeScalars.filter { $0.value < 128 }.map(Character.init))
        let basic = result.utf8.count
        var handled = basic, n = 128, delta = 0, bias = 72
        if basic > 0 { result += "-" }
        func digit(_ d: Int) -> String { String(UnicodeScalar(d < 26 ? d + 97 : d - 26 + 48)!) }
        while handled < input.count {
            guard let next = input.filter({ $0 >= n }).min() else { return nil }
            delta += (next - n) * (handled + 1); n = next
            for scalar in input {
                if scalar < n { delta += 1 }
                if scalar == n {
                    var q = delta, k = 36
                    while true {
                        let t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                        if q < t { break }
                        result += digit(t + (q - t) % (36 - t)); q = (q - t) / (36 - t); k += 36
                    }
                    result += digit(q)
                    var d = delta / (handled == basic ? 700 : 2)
                    d += d / (handled + 1)
                    var shift = 0
                    while d > 455 { d /= 35; shift += 36 }
                    bias = shift + 36 * d / (d + 38)
                    delta = 0; handled += 1
                }
            }
            delta += 1; n += 1
        }
        return result
    }
    static func decodeIDN(_ host: String) -> String {
        host.split(separator: ".", omittingEmptySubsequences: false).map { label in
            let s = String(label)
            return s.hasPrefix("xn--") ? (decodePunycode(String(s.dropFirst(4))) ?? s) : s
        }.joined(separator: ".")
    }
    /// RFC 3492 decode with explicit bounds; malformed labels remain in ASCII.
    static func decodePunycode(_ input: String) -> String? {
        let bytes = Array(input.utf8)
        var out: [UInt32] = [], cursor = 0, n = 128, i = 0, bias = 72
        if let dash = bytes.lastIndex(of: 45) {
            guard bytes[..<dash].allSatisfy({ $0 < 128 }) else { return nil }
            out = bytes[..<dash].map(UInt32.init); cursor = dash + 1
        }
        while cursor < bytes.count {
            let old = i
            var weight = 1, k = 36
            while true {
                guard cursor < bytes.count else { return nil }
                let b = bytes[cursor]; cursor += 1
                let digit: Int
                switch b { case 48...57: digit = Int(b - 22); case 65...90: digit = Int(b - 65); case 97...122: digit = Int(b - 97); default: return nil }
                guard digit <= (Int.max - i) / weight else { return nil }
                i += digit * weight
                let t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                if digit < t { break }
                guard weight <= Int.max / (36 - t), k < 10000 else { return nil }
                weight *= 36 - t; k += 36
            }
            let count = out.count + 1
            var delta = (i - old) / (old == 0 ? 700 : 2)
            delta += delta / count
            var shift = 0
            while delta > 455 { delta /= 35; shift += 36 }
            bias = shift + 36 * delta / (delta + 38)
            guard i / count <= 0x10ffff - n else { return nil }
            n += i / count; i %= count
            guard let scalar = UnicodeScalar(n) else { return nil }
            out.insert(scalar.value, at: i); i += 1
        }
        return String(String.UnicodeScalarView(out.compactMap(UnicodeScalar.init)))
    }
}
