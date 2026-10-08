import Vision
import AVFoundation

struct ScanCode: Equatable {
    let value: String
    let format: String
}
struct BarcodeFormat {
    let name: String
    let vision: VNBarcodeSymbology
    let camera: AVMetadataObject.ObjectType
    let standard: Bool
}
enum Decoder {
    // UPC-A is exposed as EAN-13 (leading zero) by both Apple APIs.
    static let formats: [BarcodeFormat] = [
        .init(name: "QR", vision: .qr, camera: .qr, standard: true),
        .init(name: "EAN-13", vision: .ean13, camera: .ean13, standard: true),
        .init(name: "EAN-8", vision: .ean8, camera: .ean8, standard: true),
        .init(name: "UPC-E", vision: .upce, camera: .upce, standard: true),
        .init(name: "Code 128", vision: .code128, camera: .code128, standard: false),
        .init(name: "Code 39", vision: .code39, camera: .code39, standard: false),
        .init(name: "Code 39 Mod 43", vision: .code39Checksum, camera: .code39Mod43, standard: false),
        .init(name: "Code 93", vision: .code93, camera: .code93, standard: false),
        .init(name: "ITF", vision: .i2of5, camera: .interleaved2of5, standard: false),
        .init(name: "ITF-14", vision: .itf14, camera: .itf14, standard: false),
        .init(name: "DataMatrix", vision: .dataMatrix, camera: .dataMatrix, standard: false),
        .init(name: "PDF417", vision: .pdf417, camera: .pdf417, standard: false),
        .init(name: "Aztec", vision: .aztec, camera: .aztec, standard: false)
    ]
    static func enabled(all: Bool) -> [BarcodeFormat] { formats.filter { all || $0.standard } }
    static func code(_ value: String, name: String) -> ScanCode {
        if name == "EAN-13", value.count == 13, value.first == "0" { return ScanCode(value: String(value.dropFirst()), format: "UPC-A") }
        return ScanCode(value: value, format: name)
    }
    static func unique(_ codes: [ScanCode]) -> [ScanCode] {
        codes.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
    static func decode(_ image: CGImage, all: Bool) throws -> [ScanCode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = enabled(all: all).map(\.vision)
        try VNImageRequestHandler(cgImage: image).perform([request])
        return unique((request.results ?? []).compactMap { result in
            guard let text = result.payloadStringValue else { return nil }
            return code(text, name: formats.first { $0.vision == result.symbology }?.name ?? result.symbology.rawValue)
        })
    }
}
