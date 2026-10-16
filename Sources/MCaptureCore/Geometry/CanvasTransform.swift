import CoreGraphics

/// 이미지 픽셀 좌표 ↔ 캔버스 뷰 좌표(왼쪽 위 원점, 포인트) 변환
public struct CanvasTransform: Equatable, Sendable {
    public static let minZoom: CGFloat = 0.02
    public static let maxZoom: CGFloat = 64

    /// 이미지 1픽셀이 차지하는 뷰 포인트 수
    public var zoom: CGFloat
    /// 보이는 영역의 왼쪽 위가 놓이는 뷰 좌표
    public var origin: CGPoint
    /// 표시 중인 이미지 영역 (크롭 또는 이미지 전체, 픽셀)
    public var visibleRect: CGRect

    public init(zoom: CGFloat, origin: CGPoint, visibleRect: CGRect) {
        self.zoom = zoom
        self.origin = origin
        self.visibleRect = visibleRect
    }

    public func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - visibleRect.minX) * zoom + origin.x,
            y: (point.y - visibleRect.minY) * zoom + origin.y
        )
    }

    public func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - origin.x) / zoom + visibleRect.minX,
            y: (point.y - origin.y) / zoom + visibleRect.minY
        )
    }

    public func toView(_ rect: CGRect) -> CGRect {
        let topLeft = toView(rect.origin)
        return CGRect(x: topLeft.x, y: topLeft.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    public func toImage(_ rect: CGRect) -> CGRect {
        let topLeft = toImage(rect.origin)
        return CGRect(x: topLeft.x, y: topLeft.y, width: rect.width / zoom, height: rect.height / zoom)
    }

    /// 뷰 좌표에서 보이는 영역이 차지하는 사각형
    public var contentFrame: CGRect {
        toView(visibleRect)
    }

    /// 뷰 안에 영역 전체가 들어가도록 맞춘다. 확대는 maxZoom까지만 (작은 이미지가 과하게 커지지 않게)
    public static func fitting(_ visibleRect: CGRect, in viewSize: CGSize, padding: CGFloat = 0, maxZoom: CGFloat) -> CanvasTransform {
        let availableWidth = max(viewSize.width - padding * 2, 1)
        let availableHeight = max(viewSize.height - padding * 2, 1)
        let fit = min(availableWidth / max(visibleRect.width, 1), availableHeight / max(visibleRect.height, 1))
        let zoom = min(max(min(fit, maxZoom), minZoom), CanvasTransform.maxZoom)
        return CanvasTransform(zoom: zoom, origin: .zero, visibleRect: visibleRect).centered(in: viewSize)
    }

    /// 지정한 배율로 가운데 정렬한다
    public static func centered(_ visibleRect: CGRect, zoom: CGFloat, in viewSize: CGSize) -> CanvasTransform {
        CanvasTransform(zoom: zoom, origin: .zero, visibleRect: visibleRect).centered(in: viewSize)
    }

    public func centered(in viewSize: CGSize) -> CanvasTransform {
        var result = self
        result.origin = CGPoint(
            x: ((viewSize.width - visibleRect.width * zoom) / 2).rounded(),
            y: ((viewSize.height - visibleRect.height * zoom) / 2).rounded()
        )
        return result
    }

    /// 뷰 좌표 anchor 아래의 이미지 픽셀이 고정되도록 확대·축소한다
    public func zoomed(to newZoom: CGFloat, around anchor: CGPoint) -> CanvasTransform {
        let clampedZoom = min(max(newZoom, Self.minZoom), Self.maxZoom)
        let imagePoint = toImage(anchor)
        var result = self
        result.zoom = clampedZoom
        result.origin = CGPoint(
            x: anchor.x - (imagePoint.x - visibleRect.minX) * clampedZoom,
            y: anchor.y - (imagePoint.y - visibleRect.minY) * clampedZoom
        )
        return result
    }

    /// 이미지 영역 rect가 뷰 가운데에 꽉 차도록 확대한다 (선택 영역으로 확대)
    public func focused(on rect: CGRect, in viewSize: CGSize, padding: CGFloat = 0) -> CanvasTransform {
        let fit = min(
            max(viewSize.width - padding * 2, 1) / max(rect.width, 1),
            max(viewSize.height - padding * 2, 1) / max(rect.height, 1)
        )
        var result = self
        result.zoom = min(max(fit, Self.minZoom), Self.maxZoom)
        result.origin = CGPoint(
            x: viewSize.width / 2 - (rect.midX - visibleRect.minX) * result.zoom,
            y: viewSize.height / 2 - (rect.midY - visibleRect.minY) * result.zoom
        )
        return result
    }

    public func panned(dx: CGFloat, dy: CGFloat) -> CanvasTransform {
        var result = self
        result.origin.x += dx
        result.origin.y += dy
        return result
    }

    /// 콘텐츠가 뷰보다 작은 축은 가운데 정렬, 큰 축은 빈 공간이 margin을 넘지 않게 제한한다
    public func clamped(to viewSize: CGSize, margin: CGFloat = 40) -> CanvasTransform {
        var result = self
        let contentWidth = visibleRect.width * zoom
        let contentHeight = visibleRect.height * zoom
        result.origin.x = Self.clampAxis(origin.x, content: contentWidth, view: viewSize.width, margin: margin)
        result.origin.y = Self.clampAxis(origin.y, content: contentHeight, view: viewSize.height, margin: margin)
        return result
    }

    // 한 축의 원점을 제한한다
    private static func clampAxis(_ value: CGFloat, content: CGFloat, view: CGFloat, margin: CGFloat) -> CGFloat {
        if content + margin * 2 <= view {
            return ((view - content) / 2).rounded()
        }
        return min(max(value, view - content - margin), margin)
    }
}
