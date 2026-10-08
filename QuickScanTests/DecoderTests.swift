#if !SWIFT_PACKAGE
import XCTest
import CoreImage
import Vision
final class DecoderTests: XCTestCase {
    func testQRFromImage() throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.com/test".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let generated = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let image = try XCTUnwrap(CIContext().createCGImage(generated, from: generated.extent))
        XCTAssertEqual(try Decoder.decode(image, all: false), [ScanCode(value: "https://example.com/test", format: "QR")])
    }
    func testEAN13FromImage() throws {
        // ISO EAN-13 bars for JAN 4901234567894, including quiet zones.
        let left = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
        let even = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
        let right = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
        let digits = [4,9,0,1,2,3,4,5,6,7,8,9,4]
        let parity = Array("LGLLGG") // Leading 4
        var bars = "101"
        for i in 0..<6 { bars += (parity[i] == "L" ? left : even)[digits[i+1]] }
        bars += "01010"
        for d in digits[7...] { bars += right[d] }
        bars += "101"
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 600, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        ctx.setFillColor(gray: 0, alpha: 1)
        for (i, bit) in bars.enumerated() where bit == "1" { ctx.fill(CGRect(x: 60+i*5, y: 40, width: 5, height: 220)) }
        let image = try XCTUnwrap(ctx.makeImage())
        XCTAssertEqual(try Decoder.decode(image, all: false), [ScanCode(value: "4901234567894", format: "EAN-13")])
    }
    func testUPCANormalizationAndDeduplication() {
        let code = Decoder.code("0123456789012", name: "EAN-13")
        XCTAssertEqual(code, ScanCode(value: "123456789012", format: "UPC-A"))
        XCTAssertEqual(Decoder.unique([code, code]), [code])
        XCTAssertEqual(Decoder.enabled(all: false).count, 4)
    }
}
#endif
