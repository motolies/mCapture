import AppKit

/// 부모가 넘겨준 클로저로 그리는 투명 뷰. 이미지 레이어 위에 벡터를 겹쳐 그릴 때 쓴다
final class DrawingView: FlippedView {
    var drawHandler: ((CGContext, NSRect) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawHandler?(ctx, dirtyRect)
    }

    // 이벤트는 부모 뷰가 처리한다
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
