import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import MCaptureCore

/// 단색 테스트 이미지를 만든다
private func solidImage(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// 이미지 픽셀 좌표(왼쪽 위 원점)의 RGB 값을 읽는다
private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // 1×1 컨텍스트에 원하는 픽셀이 오도록 이미지를 옮겨 그린다 (CG는 왼쪽 아래 원점)
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

/// 열마다 빨강 값이 다른 가로 그라디언트 이미지 (x열의 빨강 = x × 3)
private func gradientImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    for x in 0..<width {
        ctx.setFillColor(CGColor(srgbRed: CGFloat(x * 3) / 255, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return ctx.makeImage()!
}

@Suite("DocumentRenderer")
struct DocumentRendererTests {
    let red = AnnotationStyle(color: RGBAColor(red: 1, green: 0, blue: 0), size: .medium)

    @Test func 크롭_영역_크기로_렌더링한다() throws {
        let image = solidImage(width: 200, height: 100)
        let state = EditState(crop: CGRect(x: 10, y: 20, width: 50, height: 30))
        let output = try #require(DocumentRenderer.render(image: image, state: state, scale: 2))
        #expect(output.width == 50)
        #expect(output.height == 30)
    }

    @Test func 원본_이미지가_뒤집히지_않는다() throws {
        // 위쪽 절반만 파란색인 이미지 (CG 좌표에서 위쪽 = y가 큰 쪽)
        let ctx = CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        let image = ctx.makeImage()!

        let output = try #require(DocumentRenderer.render(image: image, state: EditState(), scale: 1))
        #expect(pixel(output, x: 5, y: 1).b == 255 && pixel(output, x: 5, y: 1).r == 0)
        #expect(pixel(output, x: 5, y: 8).r == 255)
    }

    @Test func 사각형_주석이_크롭_좌표로_옮겨져_그려진다() throws {
        let image = solidImage(width: 200, height: 200)
        let rect = Annotation(shape: .rectangle(CGRect(x: 60, y: 60, width: 40, height: 40)), style: red)
        let state = EditState(crop: CGRect(x: 50, y: 50, width: 100, height: 100), annotations: [rect])
        let output = try #require(DocumentRenderer.render(image: image, state: state, scale: 1))

        let edge = pixel(output, x: 10, y: 30)     // 이미지 (60, 80): 왼쪽 테두리
        #expect(edge.r == 255 && edge.g < 30)
        let inside = pixel(output, x: 30, y: 30)   // 사각형 안쪽은 원본 그대로
        #expect(inside.r == 255 && inside.g == 255)
    }

    @Test func 화살표와_텍스트가_그려진다() throws {
        let image = solidImage(width: 300, height: 120)
        let arrow = Annotation(shape: .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 200, y: 20)), style: red)
        let text = Annotation(shape: .text(origin: CGPoint(x: 10, y: 50), string: "Hi\n한글"), style: red)
        let output = try #require(DocumentRenderer.render(image: image, state: EditState(annotations: [arrow, text]), scale: 1))

        let shaft = pixel(output, x: 150, y: 20)
        #expect(shaft.r > 200 && shaft.g < 80)

        let size = AnnotationRenderer.textSize("Hi\n한글", style: red, pointScale: 1)
        #expect(size.height > 40)  // 두 줄
        var colored = 0
        for y in 50..<(50 + Int(size.height)) {
            for x in 10..<(10 + Int(size.width)) where pixel(output, x: x, y: y).g < 80 {
                colored += 1
            }
        }
        #expect(colored > 50)
    }

    @Test func 이미지_주석은_지정한_영역에_늘려_그려진다() throws {
        let base = solidImage(width: 100, height: 100)
        let blue = solidImage(width: 4, height: 4, red: 0, green: 0, blue: 1)
        let overlay = Annotation(shape: .image(CGRect(x: 20, y: 30, width: 40, height: 20), SendableImage(blue)), style: red)
        let output = try #require(DocumentRenderer.render(image: base, state: EditState(annotations: [overlay]), scale: 1))
        #expect(pixel(output, x: 40, y: 40) == (0, 0, 255))
        #expect(pixel(output, x: 10, y: 40) == (255, 255, 255))
        #expect(pixel(output, x: 40, y: 55) == (255, 255, 255))
    }

    @Test func 타원_선_카운터가_그려진다() throws {
        let image = solidImage(width: 200, height: 200)
        let oval = Annotation(shape: .oval(CGRect(x: 20, y: 20, width: 100, height: 60)), style: red)
        let line = Annotation(shape: .line(start: CGPoint(x: 10, y: 150), end: CGPoint(x: 190, y: 150)), style: red)
        let counter = Annotation(shape: .counter(center: CGPoint(x: 160, y: 50), number: 7), style: red)
        let output = try #require(DocumentRenderer.render(image: image, state: EditState(annotations: [oval, line, counter]), scale: 1))

        let rim = pixel(output, x: 70, y: 20)        // 타원 위쪽 둘레
        #expect(rim.r > 200 && rim.g < 80)
        #expect(pixel(output, x: 70, y: 50) == (255, 255, 255))  // 타원 안쪽은 원본
        let stroke = pixel(output, x: 100, y: 150)
        #expect(stroke.r > 200 && stroke.g < 80)
        let disc = pixel(output, x: 160 - 11, y: 50)  // 반지름 15 원의 숫자 왼쪽
        #expect(disc.r > 200 && disc.g < 80)
        #expect(pixel(output, x: 160 + 20, y: 50) == (255, 255, 255))
    }

    @Test func 형광펜은_원본이_비치게_반투명으로_덮는다() throws {
        let image = solidImage(width: 100, height: 40)
        let yellow = AnnotationStyle(color: RGBAColor(red: 1, green: 0.8, blue: 0), size: .medium)
        let marker = Annotation(shape: .highlighter(CGRect(x: 10, y: 10, width: 50, height: 20)), style: yellow)
        let output = try #require(DocumentRenderer.render(image: image, state: EditState(annotations: [marker]), scale: 1))
        let marked = pixel(output, x: 30, y: 20)
        #expect(marked.r == 255 && marked.b > 100 && marked.b < 200)  // 흰 바탕이 비쳐 연한 노랑
        #expect(pixel(output, x: 80, y: 20) == (255, 255, 255))
    }

    @Test func 픽셀화는_영역_왼쪽_위부터_블록을_한_색으로_채운다() throws {
        let base = gradientImage(width: 64, height: 32)
        // 중간 크기 블록 10px, 폭 35px이면 마지막 블록은 5px만 보인다
        let mosaic = Annotation(shape: .redact(CGRect(x: 8, y: 8, width: 35, height: 16), .pixelate), style: red)
        let output = try #require(DocumentRenderer.render(image: base, state: EditState(annotations: [mosaic]), scale: 1))

        #expect(pixel(output, x: 8, y: 8) == pixel(output, x: 17, y: 17))     // 첫 블록 안은 같은 색
        #expect(pixel(output, x: 17, y: 10).r != pixel(output, x: 18, y: 10).r)  // 블록 경계
        #expect(pixel(output, x: 38, y: 10) == pixel(output, x: 42, y: 10))   // 걸친 마지막 블록
        #expect(pixel(output, x: 4, y: 10).r == 12)                           // 영역 밖은 원본
        #expect(pixel(output, x: 50, y: 10).r == 150)
    }

    @Test func 픽셀화_블록은_크기_단계와_배율을_따른다() throws {
        let base = gradientImage(width: 64, height: 32)
        let style = AnnotationStyle(color: red.color, size: .small)  // 6pt × 배율 2 = 12px
        let mosaic = Annotation(shape: .redact(CGRect(x: 0, y: 0, width: 48, height: 24), .pixelate), style: style)
        let output = try #require(DocumentRenderer.render(image: base, state: EditState(annotations: [mosaic]), scale: 2))
        #expect(pixel(output, x: 0, y: 5) == pixel(output, x: 11, y: 5))
        #expect(pixel(output, x: 11, y: 5).r != pixel(output, x: 12, y: 5).r)
    }

    @Test func 블러는_영역_안만_흐리고_밖은_그대로_둔다() throws {
        // 왼쪽 절반 검정, 오른쪽 절반 흰색
        let ctx = CGContext(
            data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 40))
        let base = ctx.makeImage()!

        let blur = Annotation(shape: .redact(CGRect(x: 30, y: 10, width: 40, height: 20), .blur), style: red)
        let output = try #require(DocumentRenderer.render(image: base, state: EditState(annotations: [blur]), scale: 1))
        let edge = pixel(output, x: 50, y: 20)
        #expect(edge.r > 40 && edge.r < 215)        // 경계가 회색으로 흐려짐
        #expect(pixel(output, x: 25, y: 20).r == 0)  // 영역 밖은 원본
        #expect(pixel(output, x: 75, y: 20).r == 255)
        #expect(pixel(output, x: 50, y: 5).r == 255)
    }

    @Test func 배경_텍스트는_주석_색_상자에_대비색_글자로_그린다() throws {
        let image = solidImage(width: 300, height: 120)
        let style = AnnotationStyle(color: RGBAColor(red: 0, green: 0, blue: 1), size: .medium, textBackground: true)
        let text = Annotation(shape: .text(origin: CGPoint(x: 40, y: 40), string: "Hi"), style: style)
        let output = try #require(DocumentRenderer.render(image: image, state: EditState(annotations: [text]), scale: 1))
        let box = AnnotationRenderer.bounds(of: text, pointScale: 1)

        // 글자 왼쪽 여백 안쪽은 배경(파랑), 상자 밖은 원본(흰색)
        #expect(pixel(output, x: Int(box.minX) + 4, y: Int(box.midY)) == (0, 0, 255))
        #expect(pixel(output, x: Int(box.minX) - 4, y: Int(box.midY)) == (255, 255, 255))
        // 글자는 흰색 (상자 안에서 흰 픽셀이 보임)
        var white = 0
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) where pixel(output, x: x, y: y) == (255, 255, 255) {
                white += 1
            }
        }
        #expect(white > 20)
    }

    @Test func 글꼴은_지정한_글꼴을_쓰고_배율만큼_커진다() {
        for font in TextFont.allCases {
            guard let name = font.postScriptName else { continue }
            #expect(CTFontCopyPostScriptName(AnnotationRenderer.font(font, size: 20)) as String == name)
        }
        let normal = AnnotationRenderer.textSize("Hello 안녕", style: red, pointScale: 1)
        var scaled = red
        scaled.fontScale = 2
        let doubled = AnnotationRenderer.textSize("Hello 안녕", style: scaled, pointScale: 1)
        #expect(abs(doubled.width / normal.width - 2) < 0.1)
        #expect(abs(doubled.height / normal.height - 2) < 0.1)
    }

    @Test func PNG는_배율에_맞는_DPI를_기록한다() throws {
        let data = try #require(ImageEncoder.pngData(solidImage(width: 4, height: 4), scale: 2))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyDPIWidth] as? Double) == 144)
    }
}

@Suite("ImageSampler")
struct ImageSamplerTests {
    @Test func 보이는_영역은_투명하지_않은_픽셀을_모두_담는다() throws {
        let ctx = CGContext(
            data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: 60, height: 40))
        #expect(ImageSampler.visibleBounds(of: ctx.makeImage()!) == nil)
        // CG는 왼쪽 아래 원점: y 27~34에 채우면 이미지 좌표로는 위에서 5~12
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.1))
        ctx.fill(CGRect(x: 10, y: 27, width: 20, height: 8))
        let bounds = try #require(ImageSampler.visibleBounds(of: ctx.makeImage()!))
        #expect(bounds == CGRect(x: 10, y: 5, width: 20, height: 8))
    }

    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    /// 이미지 픽셀 좌표(왼쪽 위 원점)로 사각형을 칠한 테스트 이미지. background가 nil이면 투명 바탕
    private func painted(width: Int, height: Int, background: CGColor?, fills: [(CGRect, CGColor)]) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        for (rect, color) in fills {
            ctx.setFillColor(color)
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }

    @Test func 픽셀_색을_HEX와_RGB로_읽는다() throws {
        let image = solidImage(width: 4, height: 4, red: 1, green: 59.0 / 255, blue: 48.0 / 255)
        let color = try #require(ImageSampler.color(at: CGPoint(x: 2, y: 1), in: image))
        #expect(color.hex == "#FF3B30")
        #expect(color.rgbString == "rgb(255, 59, 48)")
    }

    @Test func 위쪽_픽셀을_위에서_읽고_소수_좌표는_내림한다() {
        let image = painted(width: 10, height: 10, background: white, fills: [(CGRect(x: 0, y: 0, width: 10, height: 5), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))])
        #expect(ImageSampler.color(at: CGPoint(x: 5, y: 1), in: image)?.hex == "#0000FF")
        #expect(ImageSampler.color(at: CGPoint(x: 5, y: 8), in: image)?.hex == "#FFFFFF")
        #expect(ImageSampler.color(at: CGPoint(x: 5.9, y: 4.9), in: image)?.hex == "#0000FF")
    }

    @Test func 이미지_밖이면_색이_없다() {
        let image = solidImage(width: 10, height: 10)
        #expect(ImageSampler.color(at: CGPoint(x: -1, y: 0), in: image) == nil)
        #expect(ImageSampler.color(at: CGPoint(x: 10, y: 0), in: image) == nil)
        #expect(ImageSampler.color(at: CGPoint(x: 0, y: 10), in: image) == nil)
    }

    @Test func 반투명_픽셀은_원래_색과_알파를_돌려준다() throws {
        let image = painted(width: 10, height: 10, background: nil, fills: [(CGRect(x: 0, y: 0, width: 5, height: 10), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))])
        let color = try #require(ImageSampler.color(at: CGPoint(x: 2, y: 2), in: image))
        #expect(abs(color.red - 1) < 0.01)
        #expect(abs(color.alpha - 0.5) < 0.01)
        #expect(color.hex == "#FF000080")
        #expect(ImageSampler.color(at: CGPoint(x: 8, y: 2), in: image)?.alpha == 0)
    }

    @Test func 단색이면_간격은_보이는_영역_전체다() {
        let image = solidImage(width: 40, height: 30)
        let span = ImageSampler.span(at: CGPoint(x: 5, y: 5), in: image, within: CGRect(x: 0, y: 0, width: 40, height: 30))
        #expect(span == ImageSampler.Span(horizontal: 0..<40, vertical: 0..<30))
    }

    @Test func 요소_안쪽은_요소_크기이고_사이는_간격이다() {
        // 왼쪽 요소 x 0..<20, 오른쪽 요소 x 35..<60 (둘 다 y 10..<20), 사이 15px
        let image = painted(width: 60, height: 40, background: white, fills: [
            (CGRect(x: 0, y: 10, width: 20, height: 10), black),
            (CGRect(x: 35, y: 10, width: 25, height: 10), black),
        ])
        let bounds = CGRect(x: 0, y: 0, width: 60, height: 40)
        #expect(ImageSampler.span(at: CGPoint(x: 40, y: 12), in: image, within: bounds) == ImageSampler.Span(horizontal: 35..<60, vertical: 10..<20))
        #expect(ImageSampler.span(at: CGPoint(x: 25, y: 15), in: image, within: bounds)?.horizontal == 20..<35)
    }

    @Test func 한_픽셀_선_위에서는_세로_간격이_1이다() {
        let gray = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let image = painted(width: 50, height: 30, background: white, fills: [(CGRect(x: 0, y: 12, width: 50, height: 1), gray)])
        let bounds = CGRect(x: 0, y: 0, width: 50, height: 30)
        #expect(ImageSampler.span(at: CGPoint(x: 10, y: 12), in: image, within: bounds) == ImageSampler.Span(horizontal: 0..<50, vertical: 12..<13))
        #expect(ImageSampler.span(at: CGPoint(x: 10, y: 11), in: image, within: bounds)?.vertical == 0..<12)
    }

    @Test func 간격은_보이는_영역에서_멈추고_밖이면_없다() {
        let image = solidImage(width: 100, height: 50)
        let crop = CGRect(x: 20, y: 10, width: 30, height: 20)
        #expect(ImageSampler.span(at: CGPoint(x: 25, y: 15), in: image, within: crop) == ImageSampler.Span(horizontal: 20..<50, vertical: 10..<30))
        #expect(ImageSampler.span(at: CGPoint(x: 5, y: 5), in: image, within: crop) == nil)
    }

    @Test func 간격은_이웃이_아니라_시작_색과_비교한다() {
        // x열 빨강 = x × 3이라 이웃끼리는 3씩 다르다
        let image = gradientImage(width: 40, height: 4)
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 4)
        #expect(ImageSampler.span(at: CGPoint(x: 10, y: 1), in: image, within: bounds)?.horizontal == 10..<11)
        #expect(ImageSampler.span(at: CGPoint(x: 10, y: 1), in: image, within: bounds, tolerance: 3)?.horizontal == 9..<12)
    }

    @Test func 투명_바탕의_간격은_불투명_요소_앞에서_멈춘다() {
        let image = painted(width: 30, height: 30, background: nil, fills: [(CGRect(x: 10, y: 10, width: 10, height: 10), black)])
        let span = ImageSampler.span(at: CGPoint(x: 2, y: 15), in: image, within: CGRect(x: 0, y: 0, width: 30, height: 30))
        #expect(span == ImageSampler.Span(horizontal: 0..<10, vertical: 0..<30))
    }
}
