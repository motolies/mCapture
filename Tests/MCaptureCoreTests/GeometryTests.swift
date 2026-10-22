import CoreGraphics
import Testing
@testable import MCaptureCore

@Suite("WindowCentering")
struct WindowCenteringTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let window = CGRect(x: 10, y: 10, width: 400, height: 300)
    let big = CGRect(x: -50, y: -50, width: 1200, height: 900)
    let wide = CGRect(x: -50, y: -50, width: 1200, height: 300)

    @Test func 영역_안에_들어가면_크기를_두고_가운데() {
        #expect(WindowCentering.frame(centering: window, in: area, oversize: .shrinkToFit) == CGRect(x: 300, y: 250, width: 400, height: 300))
        // 메뉴 막대를 뺀 화면(1440×875): y 287.5 → 288 반올림
        let menuBar = CGRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(WindowCentering.frame(centering: window, in: menuBar, oversize: .shrinkToFit) == CGRect(x: 520, y: 288, width: 400, height: 300))
    }

    @Test func 크면_줄여서_영역을_채운다_축마다_따로() {
        #expect(WindowCentering.frame(centering: big, in: area, oversize: .shrinkToFit) == area)
        #expect(WindowCentering.frame(centering: wide, in: area, oversize: .shrinkToFit) == CGRect(x: 0, y: 250, width: 1000, height: 300))
        // 소수 영역이면 크기를 내림
        let fractional = CGRect(x: 0, y: 0, width: 1000.5, height: 800.5)
        #expect(WindowCentering.frame(centering: big, in: fractional, oversize: .shrinkToFit) == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func 크기를_두면_왼쪽_위에_맞춰_제목_막대가_보인다() {
        let kept = WindowCentering.frame(centering: big, in: area, oversize: .keepSize)
        #expect(kept == CGRect(x: 0, y: -100, width: 1200, height: 900))
        #expect(kept.maxY == area.maxY && kept.minX == area.minX)
        #expect(WindowCentering.frame(centering: wide, in: area, oversize: .keepSize) == CGRect(x: 0, y: 250, width: 1200, height: 300))
    }

    @Test func 이미_가운데면_그대로() {
        let once = WindowCentering.frame(centering: window, in: area, oversize: .shrinkToFit)
        #expect(WindowCentering.frame(centering: once, in: area, oversize: .shrinkToFit) == once)
    }

    @Test func 음수_원점_보조_화면에서도_가운데() {
        // 주 화면 왼쪽 위에 놓인 보조 화면
        let secondary = CGRect(x: -1920, y: -300, width: 1920, height: 1050)
        let moved = WindowCentering.frame(centering: CGRect(x: 100, y: 100, width: 800, height: 600), in: secondary, oversize: .shrinkToFit)
        #expect(moved == CGRect(x: -1360, y: -75, width: 800, height: 600))
    }
}

@Suite("RectMath")
struct RectMathTests {
    @Test func 위아래_뒤집기는_기준_높이로_바꾸고_두_번이면_원래대로() {
        // 주 화면 높이 1000에서 위쪽 100pt 아래에 있는 창 → AppKit에서는 y = 1000 - 100 - 300
        let cg = CGRect(x: 50, y: 100, width: 400, height: 300)
        #expect(RectMath.flipped(cg, height: 1000) == CGRect(x: 50, y: 600, width: 400, height: 300))
        #expect(RectMath.flipped(RectMath.flipped(cg, height: 1000), height: 1000) == cg)
        // 주 화면 위쪽에 놓인 보조 화면의 창은 음수 y
        #expect(RectMath.flipped(CGRect(x: 0, y: -500, width: 100, height: 100), height: 1000).minY == 1400)
    }

    @Test func 배율_조절은_기준점을_고정한다() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let anchor = CGPoint(x: 150, y: 125)  // 왼쪽에서 1/4, 위에서 1/4 지점
        let doubled = RectMath.scaled(rect, by: 2, around: anchor)
        #expect(doubled == CGRect(x: 50, y: 75, width: 400, height: 200))
        // 기준점은 새 사각형에서도 같은 비율 위치에 있다
        #expect((anchor.x - doubled.minX) / doubled.width == 0.25)
        #expect((anchor.y - doubled.minY) / doubled.height == 0.25)
        #expect(RectMath.scaled(doubled, by: 0.5, around: anchor) == rect)
    }

    @Test func 두_점으로_정규화된_사각형을_만든다() {
        let rect = RectMath.rect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 100))
        #expect(rect == CGRect(x: 10, y: 40, width: 40, height: 60))
    }

    @Test func 정사각형은_긴_변_기준으로_드래그_방향에_만든다() {
        let rect = RectMath.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 70, y: 150), square: true)
        #expect(rect == CGRect(x: 50, y: 100, width: 50, height: 50))
    }

    @Test func 픽셀_정렬은_바깥쪽으로_넓힌다() {
        let rect = RectMath.pixelAligned(CGRect(x: 1.4, y: 2.6, width: 3.2, height: 1.1))
        #expect(rect == CGRect(x: 1, y: 2, width: 4, height: 2))
    }

    @Test func 경계_밖_사각형은_nil() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(RectMath.clamp(CGRect(x: 200, y: 200, width: 10, height: 10), to: bounds) == nil)
        #expect(RectMath.clamp(CGRect(x: 90, y: -5, width: 20, height: 20), to: bounds) == CGRect(x: 90, y: 0, width: 10, height: 15))
    }

    @Test func 계단식_배치는_빈자리면_그대로_두고_차_있으면_오른쪽_아래로_비킨다() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let frame = CGRect(x: 300, y: 300, width: 400, height: 400)
        let step: CGFloat = 28
        #expect(RectMath.cascaded(frame, avoiding: [], within: bounds, step: step) == frame)
        // 같은 자리에 창이 있으면 한 칸(오른쪽 +28, 아래 -28)
        let first = frame.offsetBy(dx: 28, dy: -28)
        #expect(RectMath.cascaded(frame, avoiding: [frame], within: bounds, step: step) == first)
        // 0·1칸이 차 있으면 2칸, 크기가 달라도 왼쪽 위 꼭짓점이 step/2 안쪽이면 같은 자리로 본다
        let nearFirst = CGRect(x: first.minX + 5, y: first.minY - 100, width: 300, height: first.height + 95)
        #expect(RectMath.cascaded(frame, avoiding: [frame, nearFirst], within: bounds, step: step) == frame.offsetBy(dx: 56, dy: -56))
        // 앞 칸을 닫아 비면 그 칸을 다시 쓴다
        #expect(RectMath.cascaded(frame, avoiding: [first], within: bounds, step: step) == frame)
    }

    @Test func 계단식_배치는_오른쪽_아래가_막히면_왼쪽_위로_가고_다_차면_그대로() {
        // 화면을 거의 채운 창: 오른쪽 아래·왼쪽 위로 한 칸씩만 들어간다
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let frame = CGRect(x: 30, y: 30, width: 940, height: 940)
        let step: CGFloat = 28
        let downRight = frame.offsetBy(dx: 28, dy: -28)
        let upLeft = frame.offsetBy(dx: -28, dy: 28)
        #expect(RectMath.cascaded(frame, avoiding: [frame, downRight], within: bounds, step: step) == upLeft)
        #expect(bounds.contains(upLeft))
        #expect(RectMath.cascaded(frame, avoiding: [frame, downRight, upLeft], within: bounds, step: step) == frame)
    }

    @Test func 이동은_경계를_넘지_않는다() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let moved = RectMath.moved(CGRect(x: 80, y: 10, width: 15, height: 10), dx: 20, dy: -30, within: bounds)
        #expect(moved == CGRect(x: 85, y: 0, width: 15, height: 10))
    }

    @Test func 크기_조절은_최소_1픽셀이고_경계를_넘지_않는다() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect = CGRect(x: 90, y: 10, width: 5, height: 5)
        #expect(RectMath.resized(rect, dw: 20, dh: -10, within: bounds) == CGRect(x: 90, y: 10, width: 10, height: 1))
    }

    @Test func 변_핸들은_그_변만_움직인다() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(RectMath.resized(rect, handle: .right, to: CGPoint(x: 150, y: 999)) == CGRect(x: 10, y: 20, width: 140, height: 50))
        #expect(RectMath.resized(rect, handle: .top, to: CGPoint(x: -5, y: 0)) == CGRect(x: 10, y: 0, width: 100, height: 70))
    }

    @Test func 모서리_핸들은_반대_모서리를_고정한다() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(RectMath.resized(rect, handle: .bottomLeft, to: CGPoint(x: 0, y: 100)) == CGRect(x: 0, y: 20, width: 110, height: 80))
        // 고정점 (10, 70)에서 (60, 30)까지: 긴 변 50 기준 정사각형
        #expect(RectMath.resized(rect, handle: .topRight, to: CGPoint(x: 60, y: 30), square: true) == CGRect(x: 10, y: 20, width: 50, height: 50))
    }

    @Test func 반대편을_넘어가면_뒤집힌다() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(RectMath.resized(rect, handle: .left, to: CGPoint(x: 150, y: 0)) == CGRect(x: 110, y: 20, width: 40, height: 50))
        #expect(RectMath.resized(rect, handle: .bottom, to: CGPoint(x: 0, y: 0)) == CGRect(x: 10, y: 0, width: 100, height: 20))
    }

    @Test func 핸들은_8개이고_가까운_핸들이_잡힌다() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let handles = RectMath.handlePoints(of: rect)
        #expect(handles.count == 8)
        // (5, 1)은 top(5, 0)과 topLeft(0, 0) 모두 허용 범위 안이지만 top이 더 가깝다
        #expect(HitTester.nearestHandle(CGPoint(x: 5, y: 1), in: handles, tolerance: 6) == .top)
        #expect(HitTester.nearestHandle(CGPoint(x: 30, y: 30), in: handles, tolerance: 6) == nil)
    }

    @Test func 경계에_닿은_변만_바깥으로_늘린다() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let inner = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(RectMath.extendingEdges(of: inner, touching: bounds) == inner)
        // 왼쪽·위만 닿음
        let corner = RectMath.extendingEdges(of: CGRect(x: 0, y: 0, width: 50, height: 50), touching: bounds)
        #expect(corner.maxX == 50 && corner.maxY == 50)
        #expect(corner.minX < -1000 && corner.minY < -1000)
        // 전체 선택이면 사방으로 늘어난다
        let all = RectMath.extendingEdges(of: bounds, touching: bounds)
        #expect(all.contains(CGRect(x: -500, y: -500, width: 1100, height: 1100)))
    }

    @Test func 화살표_각도는_45도_단위로_고정된다() {
        let snapped = RectMath.snapAngle(from: .zero, to: CGPoint(x: 100, y: 10))
        #expect(abs(snapped.y) < 0.0001)
        #expect(abs(snapped.x - (100 * 100 + 10 * 10 as CGFloat).squareRoot()) < 0.0001)
    }

    @Test func 점과_선분_거리() {
        #expect(RectMath.distance(from: CGPoint(x: 5, y: 3), toSegment: .zero, CGPoint(x: 10, y: 0)) == 3)
        #expect(RectMath.distance(from: CGPoint(x: 13, y: 4), toSegment: .zero, CGPoint(x: 10, y: 0)) == 5)
    }
}

@Suite("CanvasTransform")
struct CanvasTransformTests {
    let visible = CGRect(x: 100, y: 50, width: 400, height: 200)

    @Test func 뷰와_이미지_좌표_왕복() {
        let transform = CanvasTransform(zoom: 2.5, origin: CGPoint(x: 30, y: 40), visibleRect: visible)
        let point = CGPoint(x: 321, y: 123)
        let roundTrip = transform.toImage(transform.toView(point))
        #expect(abs(roundTrip.x - point.x) < 0.0001)
        #expect(abs(roundTrip.y - point.y) < 0.0001)
        #expect(transform.toView(CGPoint(x: 100, y: 50)) == CGPoint(x: 30, y: 40))
    }

    @Test func 맞춤은_가운데_정렬되고_최대_배율을_넘지_않는다() {
        let fit = CanvasTransform.fitting(visible, in: CGSize(width: 1000, height: 1000), maxZoom: 1)
        #expect(fit.zoom == 1)
        #expect(fit.contentFrame == CGRect(x: 300, y: 400, width: 400, height: 200))

        let small = CanvasTransform.fitting(visible, in: CGSize(width: 200, height: 200), maxZoom: 1)
        #expect(small.zoom == 0.5)
    }

    @Test func 커서_기준_줌은_커서_아래_픽셀을_고정한다() {
        let transform = CanvasTransform(zoom: 1, origin: CGPoint(x: 10, y: 10), visibleRect: visible)
        let anchor = CGPoint(x: 210, y: 110)
        let before = transform.toImage(anchor)
        let after = transform.zoomed(to: 4, around: anchor).toImage(anchor)
        #expect(abs(before.x - after.x) < 0.0001)
        #expect(abs(before.y - after.y) < 0.0001)
    }

    @Test func 선택_영역으로_확대하면_가운데에_꽉_찬다() {
        let transform = CanvasTransform(zoom: 1, origin: .zero, visibleRect: visible)
        let target = CGRect(x: 200, y: 100, width: 50, height: 25)
        let focused = transform.focused(on: target, in: CGSize(width: 500, height: 500))
        #expect(focused.zoom == 10)
        let frame = focused.toView(target)
        #expect(abs(frame.midX - 250) < 0.0001 && abs(frame.midY - 250) < 0.0001)
    }

    @Test func 작은_콘텐츠는_가운데로_큰_콘텐츠는_여백_제한() {
        let viewSize = CGSize(width: 800, height: 600)
        let small = CanvasTransform(zoom: 1, origin: CGPoint(x: -500, y: 900), visibleRect: visible).clamped(to: viewSize)
        #expect(small.origin == CGPoint(x: 200, y: 200))

        let big = CanvasTransform(zoom: 4, origin: CGPoint(x: 500, y: -5000), visibleRect: visible).clamped(to: viewSize, margin: 40)
        #expect(big.origin.x == 40)
        let expectedY: CGFloat = 600 - 800 - 40
        #expect(big.origin.y == expectedY)
    }
}

@Suite("HitTester")
struct HitTesterTests {
    let style = AnnotationStyle(color: RGBAColor.palette[0], size: .medium)

    @Test func 사각형은_테두리만_맞는다() {
        let rect = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100)), style: style)
        #expect(HitTester.contains(CGPoint(x: 101, y: 150), annotation: rect, pointScale: 1, tolerance: 4))
        #expect(!HitTester.contains(CGPoint(x: 200, y: 150), annotation: rect, pointScale: 1, tolerance: 4))
        #expect(!HitTester.contains(CGPoint(x: 50, y: 150), annotation: rect, pointScale: 1, tolerance: 4))
    }

    @Test func 화살표는_선분_근처가_맞는다() {
        let arrow = Annotation(shape: .arrow(start: .zero, end: CGPoint(x: 100, y: 0)), style: style)
        #expect(HitTester.contains(CGPoint(x: 50, y: 3), annotation: arrow, pointScale: 1, tolerance: 4))
        #expect(!HitTester.contains(CGPoint(x: 50, y: 30), annotation: arrow, pointScale: 1, tolerance: 4))
    }

    @Test func 맨_위_레이어가_먼저_맞는다() {
        let bottom = Annotation(shape: .arrow(start: .zero, end: CGPoint(x: 100, y: 0)), style: style)
        let top = Annotation(shape: .arrow(start: CGPoint(x: 0, y: 2), end: CGPoint(x: 100, y: 2)), style: style)
        #expect(HitTester.hitTest(CGPoint(x: 50, y: 1), annotations: [bottom, top], pointScale: 1, tolerance: 4) == top.id)
    }

    @Test func 이미지는_안쪽을_눌러도_맞고_비율을_유지해_커진다() {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let image = Annotation(shape: .image(CGRect(x: 0, y: 0, width: 100, height: 50), SendableImage(ctx.makeImage()!)), style: style)
        #expect(HitTester.contains(CGPoint(x: 50, y: 25), annotation: image, pointScale: 1, tolerance: 4))
        // 가로로 3배, 세로로 1.2배 끌면 더 많이 끈 가로를 따라 3배
        let dragged = image.draggingHandle(.bottomRight, to: CGPoint(x: 300, y: 60), constrain: false, pointScale: 1)
        guard case .image(let rect, _) = dragged.shape else { Issue.record("이미지가 아님"); return }
        #expect(rect == CGRect(x: 0, y: 0, width: 300, height: 150))
    }

    @Test func 비율_유지_크기_조절은_반대_모서리_고정_뒤집힘_최소_크기를_지킨다() {
        let rect = CGRect(x: 100, y: 100, width: 40, height: 20)
        // topLeft를 (60, 90)으로: 고정점 (140, 120) 기준 가로 80/40=2배 → 80×40
        #expect(RectMath.resizedKeepingAspect(rect, handle: .topLeft, to: CGPoint(x: 60, y: 90)) == CGRect(x: 60, y: 80, width: 80, height: 40))
        // 고정점 너머로 끌면 뒤집힌다
        #expect(RectMath.resizedKeepingAspect(rect, handle: .topLeft, to: CGPoint(x: 180, y: 130)) == CGRect(x: 140, y: 120, width: 40, height: 20))
        // 고정점에 붙이면 짧은 변 1픽셀
        #expect(RectMath.resizedKeepingAspect(rect, handle: .bottomRight, to: CGPoint(x: 100, y: 100)) == CGRect(x: 100, y: 100, width: 2, height: 1))
    }

    @Test func 텍스트_모서리_핸들은_반대_모서리를_고정하고_글자_배율을_바꾼다() throws {
        let text = Annotation(shape: .text(origin: CGPoint(x: 100, y: 100), string: "Hello"), style: style)
        let box = AnnotationRenderer.bounds(of: text, pointScale: 1)
        #expect(HitTester.handles(for: text, pointScale: 1).count == 4)

        // 오른쪽 아래 모서리를 가로 두 배 위치로 끈다 → 배율 2, 왼쪽 위 고정
        let dragged = text.draggingHandle(.bottomRight, to: CGPoint(x: box.minX + box.width * 2, y: box.maxY), constrain: false, pointScale: 1)
        #expect(abs(dragged.style.fontScale - 2) < 0.0001)
        let newBox = AnnotationRenderer.bounds(of: dragged, pointScale: 1)
        #expect(abs(newBox.minX - box.minX) < 0.5 && abs(newBox.minY - box.minY) < 0.5)
        #expect(abs(newBox.width / box.width - 2) < 0.05)
    }

    @Test func 텍스트_배율은_범위를_넘지_않는다() {
        let text = Annotation(shape: .text(origin: .zero, string: "Hi"), style: style)
        let box = AnnotationRenderer.bounds(of: text, pointScale: 1)
        let huge = text.draggingHandle(.bottomRight, to: CGPoint(x: box.minX + box.width * 100, y: box.maxY), constrain: false, pointScale: 1)
        #expect(huge.style.fontScale == 8)
        let tiny = text.draggingHandle(.bottomRight, to: CGPoint(x: box.minX + 1, y: box.minY + 1), constrain: false, pointScale: 1)
        #expect(tiny.style.fontScale == 0.25)
    }

    @Test func 타원은_둘레_띠만_맞고_작은_타원은_안쪽도_맞는다() {
        let oval = Annotation(shape: .oval(CGRect(x: 0, y: 0, width: 200, height: 100)), style: style)
        #expect(HitTester.contains(CGPoint(x: 100, y: 1), annotation: oval, pointScale: 1, tolerance: 4))    // 위쪽 둘레
        #expect(HitTester.contains(CGPoint(x: 199, y: 50), annotation: oval, pointScale: 1, tolerance: 4))   // 오른쪽 둘레
        #expect(!HitTester.contains(CGPoint(x: 100, y: 50), annotation: oval, pointScale: 1, tolerance: 4))  // 가운데
        #expect(!HitTester.contains(CGPoint(x: 5, y: 5), annotation: oval, pointScale: 1, tolerance: 4))     // 상자 모서리는 타원 밖
        let small = Annotation(shape: .oval(CGRect(x: 0, y: 0, width: 16, height: 16)), style: style)
        #expect(HitTester.contains(CGPoint(x: 8, y: 8), annotation: small, pointScale: 1, tolerance: 4))
    }

    @Test func 선은_선분_근처가_맞고_끝점_핸들은_45도로_고정된다() {
        let line = Annotation(shape: .line(start: .zero, end: CGPoint(x: 100, y: 0)), style: style)
        #expect(HitTester.contains(CGPoint(x: 50, y: 3), annotation: line, pointScale: 1, tolerance: 4))
        #expect(!HitTester.contains(CGPoint(x: 50, y: 30), annotation: line, pointScale: 1, tolerance: 4))
        #expect(HitTester.handles(for: line, pointScale: 1).map(\.0) == [.start, .end])
        let snapped = line.draggingHandle(.end, to: CGPoint(x: 100, y: 90), constrain: true, pointScale: 1)
        guard case .line(_, let end) = snapped.shape else { Issue.record("선이 아님"); return }
        #expect(abs(end.x - end.y) < 0.001)
    }

    @Test func 카운터는_원_안이_맞고_핸들이_없다() {
        // 중간 크기 지름 30pt → 배율 2에서 반지름 30px
        let counter = Annotation(shape: .counter(center: CGPoint(x: 100, y: 100), number: 1), style: style)
        #expect(HitTester.contains(CGPoint(x: 125, y: 100), annotation: counter, pointScale: 2, tolerance: 2))
        #expect(!HitTester.contains(CGPoint(x: 140, y: 100), annotation: counter, pointScale: 2, tolerance: 2))
        #expect(HitTester.handles(for: counter, pointScale: 2).isEmpty)
        #expect(counter.moved(dx: 5, dy: -5).shape == .counter(center: CGPoint(x: 105, y: 95), number: 1))
    }

    @Test func 형광펜은_상자_안이_맞고_정사각형으로_조절된다() {
        let marker = Annotation(shape: .highlighter(CGRect(x: 0, y: 0, width: 100, height: 20)), style: style)
        #expect(HitTester.contains(CGPoint(x: 50, y: 10), annotation: marker, pointScale: 1, tolerance: 4))
        let squared = marker.draggingHandle(.bottomRight, to: CGPoint(x: 60, y: 30), constrain: true, pointScale: 1)
        #expect(squared.shape == .highlighter(CGRect(x: 0, y: 0, width: 60, height: 60)))
    }

    @Test func 범위_안에_완전히_들어간_주석만_고른다() {
        let inside = Annotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 30, height: 30)), style: style)
        let crossing = Annotation(shape: .rectangle(CGRect(x: 80, y: 80, width: 40, height: 40)), style: style)
        let line = Annotation(shape: .line(start: CGPoint(x: 10, y: 60), end: CGPoint(x: 90, y: 60)), style: style)
        let ids = HitTester.annotations(inside: CGRect(x: 0, y: 0, width: 100, height: 100), annotations: [inside, crossing, line], pointScale: 1)
        #expect(ids == [inside.id, line.id])
    }

    @Test func 화살표와_텍스트는_도형에_딱_맞게_감싸도_고른다() {
        // 화살표 머리·텍스트 여백은 판정에 넣지 않는다
        let arrow = Annotation(shape: .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 10)), style: style)
        #expect(HitTester.annotations(inside: CGRect(x: 10, y: 10, width: 80, height: 1), annotations: [arrow], pointScale: 1) == [arrow.id])

        let text = Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "Hello"), style: style)
        let size = AnnotationRenderer.textSize("Hello", style: style, pointScale: 1)
        let tight = CGRect(origin: CGPoint(x: 10, y: 10), size: size)
        #expect(HitTester.annotations(inside: tight, annotations: [text], pointScale: 1) == [text.id])
        #expect(HitTester.annotations(inside: tight.insetBy(dx: 2, dy: 0), annotations: [text], pointScale: 1).isEmpty)
    }

    @Test func 핸들_드래그는_반대쪽_모서리를_고정한다() {
        let rect = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), style: style)
        #expect(HitTester.hitHandle(CGPoint(x: 59, y: 61), annotation: rect, pointScale: 1, tolerance: 3) == .bottomRight)
        let dragged = rect.draggingHandle(.topLeft, to: CGPoint(x: 0, y: 30), constrain: false, pointScale: 1)
        #expect(dragged.shape == .rectangle(CGRect(x: 0, y: 30, width: 60, height: 30)))
    }
}
