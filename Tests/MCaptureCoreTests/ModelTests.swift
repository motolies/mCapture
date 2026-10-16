import CoreGraphics
import Testing
@testable import MCaptureCore

/// 단색 1×1 이미지
private func tinyImage() -> CGImage {
    let ctx = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    return ctx.makeImage()!
}

@Suite("EditState")
struct EditStateTests {
    let style = AnnotationStyle(color: RGBAColor.palette[0], size: .medium)

    private func rect() -> Annotation {
        Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: style)
    }

    private func image() -> Annotation {
        Annotation(shape: .image(CGRect(x: 0, y: 0, width: 10, height: 10), SendableImage(tinyImage())), style: style)
    }

    @Test func 베이스_레이어는_일반_주석_아래에_쌓인다() {
        var state = EditState()
        let r1 = rect(), i1 = image(), r2 = rect(), i2 = image()
        [r1, i1, r2, i2].forEach { state.add($0) }
        #expect(state.annotations.map(\.id) == [i1.id, i2.id, r1.id, r2.id])
    }

    @Test func 맨_위로_올리기는_같은_그룹_안에서만() {
        var state = EditState()
        let i1 = image(), i2 = image(), r1 = rect(), r2 = rect()
        [i1, i2, r1, r2].forEach { state.add($0) }
        state.bringToFront(id: i1.id)
        state.bringToFront(id: r1.id)
        #expect(state.annotations.map(\.id) == [i2.id, i1.id, r2.id, r1.id])
    }

    @Test func 카운터_번호는_가장_큰_번호_다음이다() {
        var state = EditState()
        #expect(state.nextCounterNumber == 1)
        let counters = [1, 2, 5].map { Annotation(shape: .counter(center: .zero, number: $0), style: style) }
        counters.forEach { state.add($0) }
        #expect(state.nextCounterNumber == 6)
        state.remove(id: counters[2].id)
        #expect(state.nextCounterNumber == 3)
    }

    @Test func 여러_주석을_한꺼번에_지운다() {
        var state = EditState()
        let r1 = rect(), r2 = rect(), r3 = rect()
        [r1, r2, r3].forEach { state.add($0) }
        state.remove(ids: [r1.id, r3.id])
        #expect(state.annotations.map(\.id) == [r2.id])
    }

    @Test func 형광펜은_베이스_레이어로_쌓인다() {
        var state = EditState()
        let r1 = rect()
        let marker = Annotation(shape: .highlighter(CGRect(x: 0, y: 0, width: 10, height: 10)), style: style)
        state.add(r1)
        state.add(marker)
        #expect(state.annotations.map(\.id) == [marker.id, r1.id])
    }

    @Test func 이미지_비교는_같은_객체인지로_한다() {
        let a = tinyImage()
        #expect(SendableImage(a) == SendableImage(a))
        #expect(SendableImage(a) != SendableImage(tinyImage()))
    }
}

@Suite("AnnotationSize")
struct AnnotationSizeTests {
    private let steps: [AnnotationSize] = [.small, .medium, .large]

    @Test func 예전_S_M_L_값을_그대로_만든다() {
        #expect(steps.map(\.value) == [2, 4, 7])
        #expect(steps.map(\.lineWidth) == [2, 4, 7])
        #expect(steps.map(\.fontSize) == [16, 24, 36])
        #expect(steps.map(\.counterDiameter) == [22, 30, 42])
        #expect(steps.map(\.pixelateBlock) == [6, 10, 16])
        #expect(steps.map(\.blurRadius) == [4, 8, 14])
    }

    @Test func 범위를_벗어나면_끝값으로_맞춘다() {
        #expect(AnnotationSize(0).value == 1)
        #expect(AnnotationSize(99).value == 20)
        #expect(AnnotationSize(11).lineWidth == 11)
    }

    @Test func 가리기_강도는_하한_아래로_내려가지_않는다() {
        // 크기 1에서도 픽셀화 블록 6pt, 블러 반경 4pt를 유지해 글자가 읽히지 않게 한다
        #expect(AnnotationSize(1).pixelateBlock == 6)
        #expect(AnnotationSize(1).blurRadius == 4)
        #expect(AnnotationSize(20).blurRadius == 40)
    }
}
