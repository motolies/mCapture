import AppKit
import MCaptureCore

/// 멈춘 화면 위에서 영역을 고르는 뷰. 선택 영역은 이미지 픽셀 좌표로 관리한다
/// 창 모드에서는 커서 아래 창을 강조하고 클릭하면 그 창을 고른다. 드래그하면 영역 모드와 같다
/// 색 모드(컬러 피커)에서는 화면을 어둡게 하지 않고, 클릭하면 확대경 가운데 픽셀 색을 고른다
final class SelectionView: FlippedView {
    /// 창 모드의 후보 창 (뷰 좌표)
    struct WindowRegion {
        let id: CGWindowID
        let rect: CGRect
    }

    var onFinish: ((SelectionPick) -> Void)?
    var onCancel: (() -> Void)?
    var onDragStart: (() -> Void)?

    private let shot: ScreenShot
    private let scale: CGFloat
    private let imageBounds: CGRect
    private let imageView = ImageLayerView()
    private let marksView = DrawingView()
    /// 앞에서 뒤 순서. 비어 있으면 영역 모드
    private let windows: [WindowRegion]
    private let pickingColor: Bool
    private var hoveredWindow: WindowRegion?
    private var drawnHighlight: CGRect?

    private var mouse: CGPoint?          // 뷰 좌표, 화면 밖이면 nil
    private var anchor: CGPoint?         // 드래그 시작점 (이미지 픽셀)
    private var current: CGPoint?        // 드래그 현재점 (이미지 픽셀)
    private var selection: CGRect?       // 이미지 픽셀
    private var dragDistance: CGFloat = 0
    private var lastDragPoint: CGPoint?
    private var movingWithSpace = false
    private var drawnRegions: [NSRect] = []

    private enum Metrics {
        static let dim = CGColor(gray: 0, alpha: 0.3)
        static let clickThreshold: CGFloat = 3
        static let highlight = CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
    }

    init(shot: ScreenShot, frame: NSRect, windows: [WindowRegion] = [], pickingColor: Bool = false) {
        self.shot = shot
        self.windows = windows
        self.pickingColor = pickingColor
        self.scale = shot.scale
        self.imageBounds = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        super.init(frame: frame)
        wantsLayer = true

        imageView.image = shot.image
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        marksView.frame = bounds
        marksView.autoresizingMask = [.width, .height]
        marksView.drawHandler = { [unowned self] ctx, dirty in drawMarks(ctx, dirty: dirty) }
        addSubview(marksView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 다른 화면에서 선택을 시작하면 이 화면의 선택을 지운다
    func resetInteraction() {
        anchor = nil
        current = nil
        selection = nil
        invalidateMarks()
    }

    // MARK: - 좌표 변환

    private func toImage(_ point: CGPoint) -> CGPoint {
        RectMath.clamp(CGPoint(x: (point.x * scale).rounded(), y: (point.y * scale).rounded()), to: imageBounds)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / scale, y: rect.minY / scale, width: rect.width / scale, height: rect.height / scale)
    }

    private func location(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    // MARK: - 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        mouse = location(event)
        updateHoveredWindow()
        invalidateMarks()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        hoveredWindow = nil
        invalidateMarks()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        mouse = location(event)
        updateHoveredWindow()
        invalidateMarks()
    }

    // 커서 아래 맨 앞 창을 찾는다. 누르고 있는 동안에는 바꾸지 않는다
    private func updateHoveredWindow() {
        guard anchor == nil else { return }
        hoveredWindow = mouse.flatMap { point in windows.first { $0.rect.contains(point) } }
    }

    /// 강조할 창 영역. 드래그로 영역을 고르기 시작하면 감춘다
    private var highlightRect: CGRect? {
        selection == nil ? hoveredWindow?.rect : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        // 색 모드: 확대경 가운데 픽셀 색으로 끝낸다 (⇧클릭은 RGB 형식)
        if pickingColor {
            if let color = ImageSampler.color(at: centerPixel(at: location(event)), in: shot.image) {
                onFinish?(.color(color, asRGB: event.modifierFlags.contains(.shift)))
            }
            return
        }
        onDragStart?()
        let point = toImage(location(event))
        anchor = point
        current = point
        selection = nil
        dragDistance = 0
        lastDragPoint = point
        invalidateMarks()
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = location(event)
        mouse = viewPoint
        let point = toImage(viewPoint)
        if let last = lastDragPoint {
            dragDistance += hypot(point.x - last.x, point.y - last.y) / scale
        }
        if movingWithSpace, let anchor, let current, let last = lastDragPoint {
            // Space를 누른 동안에는 크기를 유지한 채 선택 영역을 옮긴다
            let moved = RectMath.moved(RectMath.rect(from: anchor, to: current), dx: point.x - last.x, dy: point.y - last.y, within: imageBounds)
            let dx = moved.minX - min(anchor.x, current.x)
            let dy = moved.minY - min(anchor.y, current.y)
            self.anchor = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
            self.current = CGPoint(x: current.x + dx, y: current.y + dy)
        } else {
            current = point
        }
        lastDragPoint = point
        updateSelection(square: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil; current = nil; lastDragPoint = nil }
        guard anchor != nil else { return }
        if dragDistance < Metrics.clickThreshold {
            onFinish?(hoveredWindow.map { .window($0.id) } ?? .display)
        } else if let selection, selection.width >= 1, selection.height >= 1 {
            onFinish?(.area(selection))
        } else {
            resetInteraction()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    // MARK: - 키보드

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // Esc
            onCancel?()
        case 49:  // Space
            movingWithSpace = anchor != nil
        case 48:  // Tab: 확대경 가운데 픽셀 색 복사
            copyColorUnderMouse()
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { movingWithSpace = false }
    }

    // 확대경과 같은 위치(커서 아래 이미지 픽셀)의 색(HEX)으로 선택을 끝낸다
    private func copyColorUnderMouse() {
        guard let mouse, let color = ImageSampler.color(at: centerPixel(at: mouse), in: shot.image) else { return }
        onFinish?(.color(color, asRGB: false))
    }

    // 뷰 좌표 아래의 이미지 픽셀 (확대경 가운데 칸)
    private func centerPixel(at point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x * scale).rounded(.down), y: (point.y * scale).rounded(.down))
    }

    override func flagsChanged(with event: NSEvent) {
        if anchor != nil { updateSelection(square: event.modifierFlags.contains(.shift)) }
    }

    private func updateSelection(square: Bool) {
        guard let anchor, let current else { return }
        let rect = RectMath.pixelRounded(RectMath.rect(from: anchor, to: current, square: square))
        selection = RectMath.clamp(rect, to: imageBounds)
        invalidateMarks()
    }

    // MARK: - 그리기

    /// 이전 프레임과 이번 프레임에 그린 영역만 다시 그린다
    private func invalidateMarks() {
        let regions = currentRegions()
        for rect in drawnRegions + regions {
            marksView.setNeedsDisplay(rect)
        }
        drawnRegions = regions
        // 창 강조는 영역이 커서 바뀔 때만 다시 그린다
        let highlight = highlightRect
        if highlight != drawnHighlight {
            for rect in [drawnHighlight, highlight].compactMap({ $0 }) {
                marksView.setNeedsDisplay(rect.insetBy(dx: -3, dy: -3))
            }
            drawnHighlight = highlight
        }
    }

    // 이번 프레임에 내용이 바뀌는 영역 목록
    private func currentRegions() -> [NSRect] {
        var regions: [NSRect] = []
        if let selection {
            let rect = toView(selection)
            regions.append(rect.insetBy(dx: -3, dy: -3))
            regions.append(sizeLabelRect(for: rect).insetBy(dx: -2, dy: -2))
        }
        if let mouse {
            if anchor == nil {
                regions.append(NSRect(x: mouse.x - 2, y: 0, width: 4, height: bounds.height))
                regions.append(NSRect(x: 0, y: mouse.y - 2, width: bounds.width, height: 4))
            }
            regions.append(Loupe.frame(at: mouse, info: loupeInfo(at: mouse), in: bounds).insetBy(dx: -8, dy: -8))
        }
        return regions
    }

    private func drawMarks(_ ctx: CGContext, dirty: NSRect) {
        let selectionRect = selection.map(toView)

        // 선택 영역(창 모드에서는 강조한 창) 밖을 어둡게. 색 모드는 색을 보는 기능이라 어둡게 하지 않는다
        let highlight = highlightRect
        if !pickingColor {
            let dimPath = CGMutablePath()
            dimPath.addRect(dirty)
            if let clear = selectionRect ?? highlight { dimPath.addRect(clear) }
            ctx.setFillColor(Metrics.dim)
            ctx.addPath(dimPath)
            ctx.fillPath(using: .evenOdd)
        }

        if let highlight {
            ctx.setStrokeColor(Metrics.highlight)
            ctx.setLineWidth(3)
            ctx.stroke(highlight.insetBy(dx: 1.5, dy: 1.5))
        }

        if let selectionRect {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.setLineWidth(1)
            ctx.stroke(selectionRect.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: selectionRect)
        }

        if let mouse {
            if anchor == nil { drawCrosshair(ctx, at: mouse) }
            drawLoupe(ctx, at: mouse)
        }
    }

    private func drawCrosshair(_ ctx: CGContext, at point: CGPoint) {
        let x = point.x.rounded(.down) + 0.5
        let y = point.y.rounded(.down) + 0.5
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
        ctx.strokeLineSegments(between: [CGPoint(x: x + 1, y: 0), CGPoint(x: x + 1, y: bounds.height),
                                         CGPoint(x: 0, y: y + 1), CGPoint(x: bounds.width, y: y + 1)])
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
        ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height),
                                         CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)])
    }

    // MARK: 크기 라벨

    private func sizeLabelText() -> String {
        SizeLabel.text(pixelSize: selection?.size ?? .zero, scale: scale)
    }

    private func sizeLabelRect(for rect: CGRect) -> NSRect {
        SizeLabel.frame(text: sizeLabelText(), near: rect, in: bounds)
    }

    private func drawSizeLabel(for rect: CGRect) {
        SizeLabel.draw(text: sizeLabelText(), in: sizeLabelRect(for: rect))
    }

    // MARK: 확대경

    private func drawLoupe(_ ctx: CGContext, at point: CGPoint) {
        let info = loupeInfo(at: point)
        Loupe.draw(ctx, image: shot.image, center: centerPixel(at: point), readable: imageBounds, info: info,
                   in: Loupe.frame(at: point, info: info, in: bounds))
    }

    // 확대경 정보 줄: 좌표(논리 픽셀)와 가운데 픽셀 색. 색 모드는 RGB 줄을 더한다
    private func loupeInfo(at point: CGPoint) -> [String] {
        let color = ImageSampler.color(at: centerPixel(at: point), in: shot.image)
        let first = "\(Int(point.x)), \(Int(point.y))   \(color?.hex ?? "")"
        guard pickingColor, let color else { return [first] }
        return [first, color.rgbString]
    }
}
