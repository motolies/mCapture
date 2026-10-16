import AppKit

/// CGImage를 Core Animation 레이어 내용으로 표시한다. GPU가 확대·축소하므로 6K 이미지도 가볍다
final class ImageLayerView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    /// 확대 시 픽셀을 선명하게 (nearest neighbor)
    var showsPixels = false {
        didSet { if oldValue != showsPixels { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = showsPixels ? .nearest : .linear
        layer.minificationFilter = .trilinear
    }

    // 이벤트는 부모 뷰가 처리한다
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 왼쪽 위 원점 좌표계를 쓰는 컨테이너
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
