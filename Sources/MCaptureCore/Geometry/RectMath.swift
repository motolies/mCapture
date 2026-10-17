import CoreGraphics

/// 이미지 픽셀 좌표에서 쓰는 사각형 계산 모음
public enum RectMath {
    /// 두 점으로 정규화된 사각형을 만든다. square면 긴 변 기준 정사각형을 드래그 방향으로 만든다
    public static func rect(from a: CGPoint, to b: CGPoint, square: Bool = false) -> CGRect {
        var dx = b.x - a.x
        var dy = b.y - a.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
    }

    /// 픽셀 경계에 맞춘다. 시작점은 내림, 끝점은 올림
    public static func pixelAligned(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(.down)
        let minY = rect.minY.rounded(.down)
        let maxX = rect.maxX.rounded(.up)
        let maxY = rect.maxY.rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 픽셀 경계에 반올림해 맞춘다. 드래그로 만든 선택 영역에 사용
    public static func pixelRounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded()
        let maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 경계 안으로 자른다. 겹치지 않으면 nil
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect? {
        let result = rect.intersection(bounds)
        return result.isNull || result.isEmpty ? nil : result
    }

    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// y축을 뒤집는다. 왼쪽 위 원점 좌표(CG 창 목록)와 왼쪽 아래 원점 좌표(AppKit 화면)를 서로 바꾼다
    /// height는 기준 높이(주 화면 높이)이고, 두 번 적용하면 원래 값이 된다
    public static func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// anchor를 고정한 채 factor배로 키우거나 줄인다 (핀 창 크기 조절). 좌표계 방향과 무관하다
    public static func scaled(_ rect: CGRect, by factor: CGFloat, around anchor: CGPoint) -> CGRect {
        CGRect(
            x: anchor.x + (rect.minX - anchor.x) * factor,
            y: anchor.y + (rect.minY - anchor.y) * factor,
            width: rect.width * factor,
            height: rect.height * factor
        )
    }

    /// 여러 창이 한자리에 겹치지 않게 step만큼 계단식으로 비켜 놓는다 (AppKit 화면 좌표: 왼쪽 아래 원점, 위쪽이 maxY)
    /// 다른 창과 왼쪽 위 꼭짓점이 step/2 안쪽으로 겹치지 않는 첫 칸을 고른다. 오른쪽 아래로 먼저, 공간이 없으면 왼쪽 위로
    /// bounds 안에 들어가는 칸이 모두 차 있으면 frame을 그대로 돌려준다
    public static func cascaded(_ frame: CGRect, avoiding others: [CGRect], within bounds: CGRect, step: CGFloat) -> CGRect {
        guard step > 0 else { return frame }
        let down = Int(max(0, min(bounds.maxX - frame.maxX, frame.minY - bounds.minY)) / step)
        let up = Int(max(0, min(frame.minX - bounds.minX, bounds.maxY - frame.maxY)) / step)
        for n in Array(0...down) + (1..<(up + 1)).map({ -$0 }) {
            let candidate = frame.offsetBy(dx: CGFloat(n) * step, dy: -CGFloat(n) * step)
            let taken = others.contains { abs($0.minX - candidate.minX) < step / 2 && abs($0.maxY - candidate.maxY) < step / 2 }
            if !taken { return candidate }
        }
        return frame
    }

    /// 크기를 유지한 채 이동한다. 경계를 넘지 않도록 원점을 제한한다
    public static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
        var result = rect.offsetBy(dx: dx, dy: dy)
        result.origin.x = min(max(result.minX, bounds.minX), max(bounds.maxX - result.width, bounds.minX))
        result.origin.y = min(max(result.minY, bounds.minY), max(bounds.maxY - result.height, bounds.minY))
        return result
    }

    /// 오른쪽·아래 변을 움직여 크기를 바꾼다. 최소 1픽셀, 경계를 넘지 않는다
    public static func resized(_ rect: CGRect, dw: CGFloat, dh: CGFloat, within bounds: CGRect) -> CGRect {
        let width = min(max(rect.width + dw, 1), bounds.maxX - rect.minX)
        let height = min(max(rect.height + dh, 1), bounds.maxY - rect.minY)
        return CGRect(x: rect.minX, y: rect.minY, width: width, height: height)
    }

    /// 사각형의 크기 조절 핸들 8개 위치 (모서리 4개, 변 가운데 4개)
    public static func handlePoints(of rect: CGRect) -> [(AnnotationHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
        ]
    }

    /// 핸들을 point로 끌어 크기를 바꾼다. 반대쪽 꼭짓점·변은 고정되고, 넘어가면 뒤집힌다
    /// square는 모서리 핸들에만 적용한다 (긴 변 기준 정사각형)
    public static func resized(_ rect: CGRect, handle: AnnotationHandle, to point: CGPoint, square: Bool = false) -> CGRect {
        switch handle {
        case .topLeft: Self.rect(from: CGPoint(x: rect.maxX, y: rect.maxY), to: point, square: square)
        case .topRight: Self.rect(from: CGPoint(x: rect.minX, y: rect.maxY), to: point, square: square)
        case .bottomLeft: Self.rect(from: CGPoint(x: rect.maxX, y: rect.minY), to: point, square: square)
        case .bottomRight: Self.rect(from: CGPoint(x: rect.minX, y: rect.minY), to: point, square: square)
        case .top: Self.rect(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: point.y))
        case .bottom: Self.rect(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: point.y))
        case .left: Self.rect(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: point.x, y: rect.maxY))
        case .right: Self.rect(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: point.x, y: rect.maxY))
        case .start, .end: rect
        }
    }

    /// 모서리 핸들을 끌 때 고정되는 반대쪽 모서리. 모서리 핸들이 아니면 nil
    public static func oppositeCorner(of rect: CGRect, handle: AnnotationHandle) -> CGPoint? {
        switch handle {
        case .topLeft: CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.minX, y: rect.minY)
        default: nil
        }
    }

    /// 모서리 핸들로 크기를 바꾸되 가로세로 비율을 유지한다. 반대쪽 모서리는 고정되고 짧은 변은 1픽셀 이상
    /// 변 핸들은 비율 없이 resized와 같다
    public static func resizedKeepingAspect(_ rect: CGRect, handle: AnnotationHandle, to point: CGPoint) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        guard let anchor = oppositeCorner(of: rect, handle: handle) else { return resized(rect, handle: handle, to: point) }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        // 가로·세로 중 더 많이 끈 쪽을 따른다
        let scale = max(abs(dx) / rect.width, abs(dy) / rect.height, 1 / min(rect.width, rect.height))
        let width = rect.width * scale
        let height = rect.height * scale
        return CGRect(x: dx < 0 ? anchor.x - width : anchor.x, y: dy < 0 ? anchor.y - height : anchor.y, width: width, height: height)
    }

    /// bounds의 변에 닿은(또는 넘은) 변을 바깥으로 아주 멀리 늘린다
    /// 보이는 영역 전체를 고른 선택 영역이 가장자리에 걸친 주석까지 담게 할 때 쓴다
    public static func extendingEdges(of rect: CGRect, touching bounds: CGRect) -> CGRect {
        let far: CGFloat = 1_000_000_000
        let minX = rect.minX <= bounds.minX ? -far : rect.minX
        let minY = rect.minY <= bounds.minY ? -far : rect.minY
        let maxX = rect.maxX >= bounds.maxX ? far : rect.maxX
        let maxY = rect.maxY >= bounds.maxY ? far : rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 시작점 기준 45° 단위로 끝점을 고정한다 (화살표 Shift 드래그)
    public static func snapAngle(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// 점과 선분 사이의 최단 거리
    public static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}
