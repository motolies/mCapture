import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
@testable import MCaptureCore

/// 흰 배경 비트맵 컨텍스트
private func whiteCanvas(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx
}

@Suite("TextRecognizer")
struct TextRecognizerTests {
    @Test func 바코드가_있으면_바코드_내용만_쓴다() {
        let result = RecognitionResult(lines: ["주변 글자"], barcodes: ["https://a.example", "https://b.example"])
        #expect(TextRecognizer.clipboardText(result, joinLines: true) == "https://a.example\nhttps://b.example")
    }

    @Test func 줄바꿈_제거와_이중_공백_정리() {
        let result = RecognitionResult(lines: ["첫 줄입니다.  이어서", "  다음 줄 ", ""])
        #expect(TextRecognizer.clipboardText(result, joinLines: false) == "첫 줄입니다. 이어서\n다음 줄")
        #expect(TextRecognizer.clipboardText(result, joinLines: true) == "첫 줄입니다. 이어서 다음 줄")
    }

    @Test func 아무것도_없으면_nil() {
        #expect(TextRecognizer.clipboardText(RecognitionResult(), joinLines: false) == nil)
        #expect(TextRecognizer.clipboardText(RecognitionResult(lines: ["  "]), joinLines: true) == nil)
    }

    @Test func 그린_한글과_영문을_읽는다() async throws {
        let ctx = whiteCanvas(width: 900, height: 240)
        let font = CTFontCreateUIFontForLanguage(.system, 56, nil)!
        for (index, line) in ["Hello mCapture 2026", "안녕하세요 텍스트 인식"].enumerated() {
            let text = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            ctx.textPosition = CGPoint(x: 40, y: 150 - CGFloat(index) * 100)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
        }
        let result = try await TextRecognizer.recognize(SendableImage(ctx.makeImage()!))
        let text = result.lines.joined(separator: "\n")
        #expect(text.contains("mCapture"))
        #expect(text.contains("안녕하세요"))
        #expect(result.barcodes.isEmpty)
    }

    @Test func QR_코드를_읽는다() async throws {
        let message = "https://example.com/mcapture"
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(message.utf8)]))
        let code = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let qr = try #require(CIContext().createCGImage(code, from: code.extent))
        // 인식에 필요한 여백(quiet zone)을 둔다
        let ctx = whiteCanvas(width: qr.width + 120, height: qr.height + 120)
        ctx.draw(qr, in: CGRect(x: 60, y: 60, width: qr.width, height: qr.height))

        let result = try await TextRecognizer.recognize(SendableImage(ctx.makeImage()!))
        #expect(result.barcodes == [message])
        #expect(TextRecognizer.clipboardText(result, joinLines: false) == message)
    }
}
