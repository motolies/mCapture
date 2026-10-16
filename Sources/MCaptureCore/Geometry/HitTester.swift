import CoreGraphics

/// 주석·선택 영역의 크기 조절 핸들과 화살표 끝점 핸들
public enum AnnotationHandle: Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case bottom
    case left
    case right
    case start
    case end
}

/// 이미지 픽셀 좌표에서 주석과 핸들을 찾는다
public enum HitTester {
    /// 주석의 핸들 위치. 텍스트는 그려지는 상자의 모서리라 글꼴 배치에 pointScale이 필요하다
    public static func handles(for annotation: Annotation, pointScale: CGFloat) -> [(AnnotationHandle, CGPoint)] {
        switch annotation.shape {
        case .rectangle(let rect), .oval(let rect), .highlighter(let rect), .image(let rect, _), .redact(let rect, _):
            return corners(of: rect)
        case .arrow(let start, let end), .line(let start, let end):
            return [(.start, start), (.end, end)]
        case .text:
            return corners(of: AnnotationRenderer.bounds(of: annotation, pointScale: pointScale))
        case .counter:
            // 크기는 툴바 크기 슬라이더로만 바꾼다
            return []
        }
    }

    // 모서리 핸들 4개
    private static func corners(of rect: CGRect) -> [(AnnotationHandle, CGPoint)] {
        Array(RectMath.handlePoints(of: rect).prefix(4))
    }

    /// tolerance(이미지 픽셀) 안에 있는 핸들을 찾는다
    public static func hitHandle(_ point: CGPoint, annotation: Annotation, pointScale: CGFloat, tolerance: CGFloat) -> AnnotationHandle? {
        nearestHandle(point, in: handles(for: annotation, pointScale: pointScale), tolerance: tolerance)
    }

    /// tolerance 안의 핸들 중 가장 가까운 것을 고른다. 작은 사각형에서 핸들이 겹쳐도 의도한 핸들을 잡는다
    public static func nearestHandle(_ point: CGPoint, in handles: [(AnnotationHandle, CGPoint)], tolerance: CGFloat) -> AnnotationHandle? {
        handles
            .map { (handle: $0.0, distance: hypot($0.1.x - point.x, $0.1.y - point.y)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?
            .handle
    }

    /// 맨 위 레이어부터 검사해 점에 걸리는 주석 id를 돌려준다
    public static func hitTest(_ point: CGPoint, annotations: [Annotation], pointScale: CGFloat, tolerance: CGFloat) -> Annotation.ID? {
        annotations.last { contains(point, annotation: $0, pointScale: pointScale, tolerance: tolerance) }?.id
    }

    /// 사각형·타원은 테두리 근처, 화살표·선은 선분 근처, 카운터는 원 안, 텍스트·이미지·가리기·형광펜은 상자 안을 맞은 것으로 본다
    public static func contains(_ point: CGPoint, annotation: Annotation, pointScale: CGFloat, tolerance: CGFloat) -> Bool {
        let halfWidth = AnnotationRenderer.lineWidth(annotation.style, pointScale: pointScale) / 2
        switch annotation.shape {
        case .rectangle(let rect):
            let reach = halfWidth + tolerance
            guard rect.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
            // 작은 사각형은 안쪽 클릭도 허용
            if rect.width < reach * 4 || rect.height < reach * 4 { return true }
            return !rect.insetBy(dx: reach, dy: reach).contains(point)
        case .oval(let rect):
            return ovalOutlineContains(point, rect: rect, reach: halfWidth + tolerance)
        case .arrow(let start, let end), .line(let start, let end):
            return RectMath.distance(from: point, toSegment: start, end) <= max(halfWidth * 2, tolerance)
        case .counter(let center, _):
            return hypot(point.x - center.x, point.y - center.y) <= AnnotationRenderer.counterRadius(annotation.style, pointScale: pointScale) + tolerance
        case .text, .image, .redact, .highlighter:
            return AnnotationRenderer.bounds(of: annotation, pointScale: pointScale).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// rect 안에 완전히 들어간 주석 id (레이어 순서)
    /// 선 두께·화살표 머리·텍스트 여백을 뺀 도형 좌표로 판정해, 도형에 딱 맞게 감싸도 빠지지 않게 한다
    public static func annotations(inside rect: CGRect, annotations: [Annotation], pointScale: CGFloat) -> [Annotation.ID] {
        annotations.filter { rect.contains(shapeFrame(of: $0, pointScale: pointScale)) }.map(\.id)
    }

    // 범위 판정에 쓰는 도형 영역. 선·화살표는 두 끝점, 카운터는 원, 텍스트는 글자 상자
    private static func shapeFrame(of annotation: Annotation, pointScale: CGFloat) -> CGRect {
        switch annotation.shape {
        case .rectangle(let rect), .oval(let rect), .highlighter(let rect), .image(let rect, _), .redact(let rect, _):
            return rect
        case .arrow(let start, let end), .line(let start, let end):
            return RectMath.rect(from: start, to: end)
        case .counter(let center, _):
            let radius = AnnotationRenderer.counterRadius(annotation.style, pointScale: pointScale)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case .text(let origin, let string):
            return CGRect(origin: origin, size: AnnotationRenderer.textSize(string, style: annotation.style, pointScale: pointScale))
        }
    }
}

extension HitTester {
    /// 타원 둘레에서 reach 안쪽인지. 바깥 타원 안이면서 안쪽 타원 밖이면 맞는다. 작은 타원은 안쪽도 허용
    static func ovalOutlineContains(_ point: CGPoint, rect: CGRect, reach: CGFloat) -> Bool {
        let a = rect.width / 2
        let b = rect.height / 2
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        // 반지름 (rx, ry)인 타원 안쪽이면 1 이하
        func normalized(_ rx: CGFloat, _ ry: CGFloat) -> CGFloat {
            (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        }
        guard normalized(a + reach, b + reach) <= 1 else { return false }
        if a < reach * 2 || b < reach * 2 { return true }
        return normalized(a - reach, b - reach) >= 1
    }
}

public extension Annotation {
    /// 전체 이동
    func moved(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        switch shape {
        case .rectangle(let rect):
            copy.shape = .rectangle(rect.offsetBy(dx: dx, dy: dy))
        case .oval(let rect):
            copy.shape = .oval(rect.offsetBy(dx: dx, dy: dy))
        case .highlighter(let rect):
            copy.shape = .highlighter(rect.offsetBy(dx: dx, dy: dy))
        case .line(let start, let end):
            copy.shape = .line(start: CGPoint(x: start.x + dx, y: start.y + dy), end: CGPoint(x: end.x + dx, y: end.y + dy))
        case .counter(let center, let number):
            copy.shape = .counter(center: CGPoint(x: center.x + dx, y: center.y + dy), number: number)
        case .arrow(let start, let end):
            copy.shape = .arrow(start: CGPoint(x: start.x + dx, y: start.y + dy), end: CGPoint(x: end.x + dx, y: end.y + dy))
        case .text(let origin, let string):
            copy.shape = .text(origin: CGPoint(x: origin.x + dx, y: origin.y + dy), string: string)
        case .image(let rect, let image):
            copy.shape = .image(rect.offsetBy(dx: dx, dy: dy), image)
        case .redact(let rect, let mode):
            copy.shape = .redact(rect.offsetBy(dx: dx, dy: dy), mode)
        }
        return copy
    }

    /// 핸들을 point로 옮긴다. constrain이면 사각형·타원은 정사각형·원, 화살표·선은 45° 단위로 고정
    /// 이미지는 항상 원래 가로세로 비율을 유지하고, 텍스트는 글자 크기 배율을 바꾼다
    func draggingHandle(_ handle: AnnotationHandle, to point: CGPoint, constrain: Bool, pointScale: CGFloat) -> Annotation {
        var copy = self
        switch (shape, handle) {
        case (.rectangle(let rect), _):
            copy.shape = .rectangle(RectMath.resized(rect, handle: handle, to: point, square: constrain))
        case (.oval(let rect), _):
            copy.shape = .oval(RectMath.resized(rect, handle: handle, to: point, square: constrain))
        case (.highlighter(let rect), _):
            copy.shape = .highlighter(RectMath.resized(rect, handle: handle, to: point, square: constrain))
        case (.line(_, let end), .start):
            copy.shape = .line(start: constrain ? RectMath.snapAngle(from: end, to: point) : point, end: end)
        case (.line(let start, _), _):
            copy.shape = .line(start: start, end: constrain ? RectMath.snapAngle(from: start, to: point) : point)
        case (.counter, _):
            break
        case (.arrow(_, let end), .start):
            copy.shape = .arrow(start: constrain ? RectMath.snapAngle(from: end, to: point) : point, end: end)
        case (.arrow(let start, _), _):
            copy.shape = .arrow(start: start, end: constrain ? RectMath.snapAngle(from: start, to: point) : point)
        case (.image(let rect, let image), _):
            copy.shape = .image(RectMath.resizedKeepingAspect(rect, handle: handle, to: point), image)
        case (.redact(let rect, let mode), _):
            copy.shape = .redact(RectMath.resized(rect, handle: handle, to: point, square: constrain), mode)
        case (.text(let origin, let string), _):
            copy = scalingText(origin: origin, string: string, handle: handle, to: point, pointScale: pointScale)
        }
        return copy
    }

    /// 반대쪽 모서리를 고정한 채 텍스트 상자를 비율대로 키우거나 줄인다. 글자 크기 배율은 0.25~8배로 제한한다
    /// 여백·글자 폭이 모두 글자 크기에 비례하므로 원점도 고정점 기준으로 같은 비율만큼 옮긴다
    private func scalingText(origin: CGPoint, string: String, handle: AnnotationHandle, to point: CGPoint, pointScale: CGFloat) -> Annotation {
        let box = AnnotationRenderer.bounds(of: self, pointScale: pointScale)
        guard let anchor = RectMath.oppositeCorner(of: box, handle: handle), box.width > 0 else { return self }
        let target = RectMath.resizedKeepingAspect(box, handle: handle, to: point)
        let fontScale = min(max(style.fontScale * target.width / box.width, 0.25), 8)
        let ratio = fontScale / style.fontScale

        var copy = self
        copy.style.fontScale = fontScale
        copy.shape = .text(
            origin: CGPoint(x: anchor.x + (origin.x - anchor.x) * ratio, y: anchor.y + (origin.y - anchor.y) * ratio),
            string: string
        )
        return copy
    }
}
