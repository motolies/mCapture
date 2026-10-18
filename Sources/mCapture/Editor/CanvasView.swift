import AppKit
import MCaptureCore
import UniformTypeIdentifiers

/// 에디터 캔버스. 원본은 이미지 레이어로, 주석·선택 영역은 오버레이 뷰에 그린다
/// 모든 모델 좌표는 이미지 픽셀이고 뷰 좌표 변환은 CanvasTransform으로만 한다
final class CanvasView: FlippedView, NSTextViewDelegate, NSMenuItemValidation {
    private enum Drag {
        case none
        case selecting(origin: CGPoint)
        case movingSelection(start: CGPoint, original: CGRect)
        case resizingSelection(handle: AnnotationHandle, original: CGRect)
        case creating(id: UUID, origin: CGPoint)
        case movingAnnotation(start: CGPoint, original: Annotation)
        case resizingAnnotation(handle: AnnotationHandle, original: Annotation)
        case panning(start: CGPoint, origin: CGPoint)
        case measuring(origin: CGPoint)
    }

    private struct TextEditing {
        let id: UUID
        let view: NSTextView
    }

    /// 픽셀 자로 끈 두 점 (이미지 픽셀 경계). 화면에만 그리고 내보내거나 실행 취소에 남기지 않는다
    private struct Measurement: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    /// 뷰 좌표 선분 (픽셀 자 측정선·간격 선)
    private struct Segment {
        var start: CGPoint
        var end: CGPoint
    }

    /// 측정 표시(컬러 피커 확대경, 픽셀 자 간격·측정선)를 그릴 위치 (뷰 좌표). 그리기와 부분 무효화가 같은 값을 쓴다
    private struct InspectionLayout {
        var loupe: (pixel: CGPoint, info: [String], frame: NSRect)?
        var segments: [Segment] = []
        var label: (text: String, frame: NSRect)?

        /// 다시 그려야 하는 영역. 선은 끝 눈금과 흰 바탕 두께만큼 넓힌다
        var regions: [NSRect] {
            var rects = segments.map { segment in
                NSRect(
                    x: min(segment.start.x, segment.end.x), y: min(segment.start.y, segment.end.y),
                    width: abs(segment.end.x - segment.start.x), height: abs(segment.end.y - segment.start.y)
                ).insetBy(dx: -(Metrics.tick + 3), dy: -(Metrics.tick + 3))
            }
            if let label { rects.append(label.frame.insetBy(dx: -2, dy: -2)) }
            if let loupe { rects.append(loupe.frame.insetBy(dx: -8, dy: -8)) }
            return rects
        }
    }

    /// 점 아래에서 찾은 핸들 (선택한 주석 또는 선택 영역)
    private enum HandleHit {
        case annotation(AnnotationHandle, Annotation)
        case selection(AnnotationHandle, CGRect)

        var handle: AnnotationHandle {
            switch self {
            case .annotation(let handle, _), .selection(let handle, _): handle
            }
        }
    }

    private enum Metrics {
        static let padding: CGFloat = 24
        static let hitTolerance: CGFloat = 6
        static let handleSize: CGFloat = 8
        static let zoomStep: CGFloat = 1.25
        static let background = NSColor(white: 0.13, alpha: 1)
        static let accent = CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
        /// 픽셀 자 선 색. 선택 표시(파랑)와 구분한다
        static let ruler = CGColor(srgbRed: 1, green: 0.18, blue: 0.57, alpha: 1)
        /// 픽셀 자 끝 눈금 길이 (한쪽, pt)
        static let tick: CGFloat = 4
        /// 자동 간격에서 같은 색으로 보는 채널별 차이. 반투명 재질의 ±1~3 디더링은 넘기고 테두리는 잡는다
        static let spanTolerance = 6
    }

    var onRequestClose: (() -> Void)?
    var onDocumentChange: (() -> Void)?
    var onOpenFiles: (([URL]) -> Void)?
    var onRequestPin: ((CaptureDocument) -> Void)?

    private(set) var document: CaptureDocument
    private let state: EditorState
    private let preferences: Preferences
    private let exporter: Exporter
    /// 픽셀화·블러 결과 캐시. 원본은 바뀌지 않으므로 문서마다 하나를 계속 쓴다
    private let redactions: RedactionCache

    private var history = History<EditState>()
    private var changeStart: EditState?
    /// 크기 슬라이더를 끄는 동안 연 변경. endChange에서 항상 닫는다
    private var sizeChangeOpen = false
    private var transform: CanvasTransform
    private var fitMode = true

    private let clipView = FlippedView()
    private let imageView = ImageLayerView()
    private let overlayView = DrawingView()

    private var selection: CGRect?
    private var selectedID: UUID?
    private var drag: Drag = .none
    private var spaceHeld = false
    private var textEditing: TextEditing?
    /// 끌어놓기 손잡이에 마우스를 올렸을 때 미리 만든 결과. 그 사이 편집 상태가 바뀌면 쓰지 않는다
    private var preparedDrag: (state: EditState, payload: DragPayload)?
    private var dragPreparation: Task<Void, Never>?
    /// 측정 도구에서 커서 위치 (뷰 좌표). 캔버스 밖이거나 창이 키를 잃으면 nil
    private var hoverPoint: CGPoint?
    private var measurement: Measurement?
    /// 마지막 자동 간격 결과. 커서가 같은 픽셀에 있으면 다시 읽지 않는다
    private var spanCache: (pixel: CGPoint, visible: CGRect, span: ImageSampler.Span?)?
    /// 지난번에 측정 표시를 그린 영역. 다음 부분 무효화 때 함께 지워 자국이 남지 않게 한다
    private var drawnInspection: [NSRect] = []

    init(document: CaptureDocument, state: EditorState, preferences: Preferences, exporter: Exporter) {
        self.document = document
        self.state = state
        self.preferences = preferences
        self.exporter = exporter
        self.redactions = RedactionCache(source: document.image)
        self.transform = CanvasTransform(zoom: 1, origin: .zero, visibleRect: document.visibleRect)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        wantsLayer = true
        layer?.backgroundColor = Metrics.background.cgColor

        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        imageView.image = document.image
        clipView.addSubview(imageView)
        addSubview(clipView)

        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.drawHandler = { [unowned self] ctx, dirty in drawOverlay(ctx, dirty: dirty) }
        addSubview(overlayView)

        state.canvas = self
        registerForDraggedTypes([.fileURL])
        updateToolbarInfo()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    /// 비활성 창의 첫 클릭도 캔버스가 받는다. 컬러 피커는 확대경을 보기 전에 클립보드를 덮어쓰지 않도록 창만 활성화한다
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { state.tool != .colorPicker }

    /// 캡처 직후 자동 저장한 파일을 기억한다. 이미 저장 경로가 있으면 유지한다
    func documentSaved(at url: URL) {
        if document.savedURL == nil { document.savedURL = url }
    }

    // MARK: - 배치

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        transform = fitMode ? fitTransform() : transform.clamped(to: bounds.size)
        applyTransform()
    }

    private func fitTransform() -> CanvasTransform {
        CanvasTransform.fitting(document.visibleRect, in: bounds.size, padding: Metrics.padding, maxZoom: 1 / document.scale)
    }

    /// 변환에 맞춰 이미지 레이어 위치와 크기를 갱신한다
    private func applyTransform() {
        let content = transform.contentFrame
        clipView.frame = content
        imageView.frame = transform.toView(document.imageBounds).offsetBy(dx: -content.minX, dy: -content.minY)
        imageView.showsPixels = transform.zoom * (window?.backingScaleFactor ?? 2) >= 1.5
        if let textEditing, let annotation = document.state.annotation(id: textEditing.id) {
            applyTextStyle(textEditing.view, style: annotation.style)
            layoutTextEditor()
        }
        redraw()
    }

    /// 크롭이 바뀌면 보이는 영역을 다시 맞춘다. 영역 밖에 남을 수 있는 측정은 지운다
    private func syncVisibleRect() {
        measurement = nil
        transform.visibleRect = document.visibleRect
        fitMode = true
        transform = fitTransform()
        applyTransform()
        onDocumentChange?()
    }

    private func setZoom(_ zoom: CGFloat, around anchor: CGPoint) {
        fitMode = false
        transform = transform.zoomed(to: zoom, around: anchor).clamped(to: bounds.size)
        applyTransform()
    }

    /// 커서가 캔버스 안에 있으면 커서 기준, 아니면 가운데 기준
    private var zoomAnchor: CGPoint {
        guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point) ? point : CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func redraw() {
        overlayView.needsDisplay = true
        drawnInspection = inspectionLayout()?.regions ?? []
        updateToolbarInfo()
    }

    private func updateToolbarInfo() {
        let rect = selection ?? document.visibleRect
        let sizeText = SizeLabel.text(pixelSize: rect.size, scale: document.scale)
        let zoomText = "\(Int((transform.zoom * document.scale * 100).rounded()))%"
        if state.sizeText != sizeText { state.sizeText = sizeText }
        if state.zoomText != zoomText { state.zoomText = zoomText }
        if state.canUndo != history.canUndo { state.canUndo = history.canUndo }
        if state.canRedo != history.canRedo { state.canRedo = history.canRedo }

        // 고르거나 편집 중인 주석의 크기, 텍스트면 글꼴·배경, 가리기면 방식을 툴바에 보인다
        let target = (textEditing?.id ?? selectedID).flatMap { document.state.annotation(id: $0) }
        let text = target.flatMap { $0.isText ? $0 : nil }
        let redactMode = target.flatMap(\.redactMode)
        let options: EditorState.ToolOptions = if state.tool == .text || text != nil {
            .text
        } else if state.tool == .redact || redactMode != nil {
            .redact
        } else {
            .none
        }
        if state.toolOptions != options { state.toolOptions = options }
        if let style = text?.style {
            if state.textFont != style.textFont { state.textFont = style.textFont }
            if state.textBackground != style.textBackground { state.textBackground = style.textBackground }
        }
        if let size = target?.style.size, state.size != size { state.size = size }
        if let redactMode, state.redactMode != redactMode { state.redactMode = redactMode }
    }

    // MARK: - 그리기

    private func drawOverlay(_ ctx: CGContext, dirty: NSRect) {
        let content = transform.contentFrame

        // 주석 (이미지 좌표계로 변환해 공용 렌더러로 그림)
        ctx.saveGState()
        ctx.clip(to: content)
        ctx.translateBy(x: transform.origin.x, y: transform.origin.y)
        ctx.scaleBy(x: transform.zoom, y: transform.zoom)
        ctx.translateBy(x: -transform.visibleRect.minX, y: -transform.visibleRect.minY)
        for annotation in document.state.annotations {
            if annotation.id == textEditing?.id {
                // 편집 중인 텍스트의 글자는 편집 뷰가 그리므로 배경 상자만 그린다
                AnnotationRenderer.drawTextBackground(annotation, pointScale: document.scale, in: ctx)
            } else {
                AnnotationRenderer.draw(annotation, in: ctx, pointScale: document.scale, redactions: redactions)
            }
        }
        ctx.restoreGState()

        if let selection {
            drawSelection(ctx, rect: transform.toView(selection), content: content, handles: showsSelectionHandles)
        }
        if let selectedID, let annotation = document.state.annotation(id: selectedID) {
            drawSelectionMarks(ctx, for: annotation)
        } else {
            // Delete로 지워질 주석을 미리 보인다
            for id in annotationIDsInSelection {
                guard let annotation = document.state.annotation(id: id) else { continue }
                drawDashedFrame(ctx, transform.toView(AnnotationRenderer.bounds(of: annotation, pointScale: document.scale)))
            }
        }
        drawInspection(ctx)
    }

    // 크롭 선택 영역: 바깥을 어둡게 하고 테두리·크기 조절 핸들·크기를 표시
    private func drawSelection(_ ctx: CGContext, rect: CGRect, content: CGRect, handles: Bool) {
        let dim = CGMutablePath()
        dim.addRect(content)
        dim.addRect(rect)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.4))
        ctx.addPath(dim)
        ctx.fillPath(using: .evenOdd)

        let border = rect.insetBy(dx: -0.5, dy: -0.5)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.stroke(border)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.8))
        ctx.stroke(border)
        ctx.setLineDash(phase: 0, lengths: [])

        if handles {
            for (_, point) in RectMath.handlePoints(of: rect) {
                drawHandle(ctx, at: point)
            }
        }

        let text = SizeLabel.text(pixelSize: selection?.size ?? .zero, scale: document.scale)
        SizeLabel.draw(text: text, in: SizeLabel.frame(text: text, near: rect, in: bounds))
    }

    // 선택한 주석: 핸들을 그리고, 텍스트는 상자 범위를 점선으로 함께 보인다
    private func drawSelectionMarks(_ ctx: CGContext, for annotation: Annotation) {
        if annotation.isText {
            drawDashedFrame(ctx, transform.toView(AnnotationRenderer.bounds(of: annotation, pointScale: document.scale)))
        }
        for (_, point) in HitTester.handles(for: annotation, pointScale: document.scale) {
            drawHandle(ctx, at: transform.toView(point))
        }
    }

    // 뷰 좌표 frame에 강조색 점선 테두리를 그린다
    private func drawDashedFrame(_ ctx: CGContext, _ frame: CGRect) {
        ctx.setLineWidth(1)
        ctx.setStrokeColor(Metrics.accent)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.stroke(frame)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    // 뷰 좌표 center에 흰 사각 핸들을 그린다
    private func drawHandle(_ ctx: CGContext, at center: CGPoint) {
        let size = Metrics.handleSize
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.setStrokeColor(Metrics.accent)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)
    }

    // MARK: - 마우스

    private func location(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        if textEditing != nil {
            commitTextEditing()
            return
        }
        window?.makeFirstResponder(self)
        let viewPoint = location(event)
        if spaceHeld {
            drag = .panning(start: viewPoint, origin: transform.origin)
            NSCursor.closedHand.set()
            return
        }
        // 측정 도구는 주석 판정보다 먼저 처리해 주석 위를 눌러도 주석을 고르거나 옮기지 않는다
        if state.tool.isInspection {
            beginInspection(at: viewPoint, shift: event.modifierFlags.contains(.shift))
            return
        }

        let point = transform.toImage(viewPoint)
        let tolerance = Metrics.hitTolerance / transform.zoom
        let hitID = HitTester.hitTest(point, annotations: hitTestCandidates, pointScale: document.scale, tolerance: tolerance)
        let hit = hitID.flatMap { document.state.annotation(id: $0) }

        // 핸들: 선택한 주석 또는 선택 영역의 크기 조절 (텍스트 모서리 핸들이 편집보다 먼저)
        switch handleHit(at: point) {
        case .annotation(let handle, let selected):
            beginChange()
            drag = .resizingAnnotation(handle: handle, original: selected)
            return
        case .selection(let handle, let original):
            selectedID = nil
            drag = .resizingSelection(handle: handle, original: original)
            redraw()
            return
        case nil:
            break
        }
        // 텍스트 더블클릭 또는 텍스트 도구로 클릭하면 편집
        if let hit, hit.isText, event.clickCount == 2 || state.tool == .text {
            beginTextEditing(id: hit.id)
            return
        }
        // 주석 본문: 선택하고 이동
        if let hit {
            beginChange()
            document.state.bringToFront(id: hit.id)
            selectedID = hit.id
            drag = .movingAnnotation(start: point, original: hit)
            redraw()
            return
        }

        selectedID = nil
        let visible = document.visibleRect
        switch state.tool {
        case .select:
            if let selection, selection.contains(point) {
                drag = .movingSelection(start: point, original: selection)
            } else {
                selection = nil
                drag = .selecting(origin: RectMath.clamp(CGPoint(x: point.x.rounded(), y: point.y.rounded()), to: visible))
            }
        case .rectangle, .oval, .line, .arrow, .highlighter, .redact:
            beginChange()
            let empty = CGRect(origin: point, size: .zero)
            let shape: AnnotationShape = switch state.tool {
            case .oval: .oval(empty)
            case .line: .line(start: point, end: point)
            case .arrow: .arrow(start: point, end: point)
            case .highlighter: .highlighter(empty)
            case .redact: .redact(empty, state.redactMode)
            default: .rectangle(empty)
            }
            let annotation = Annotation(shape: shape, style: state.style)
            document.state.add(annotation)
            selectedID = annotation.id
            drag = .creating(id: annotation.id, origin: point)
        case .counter:
            // 누른 자리에 바로 놓고, 끌면 위치를 옮긴다
            beginChange()
            let annotation = Annotation(shape: .counter(center: point, number: document.state.nextCounterNumber), style: state.style)
            document.state.add(annotation)
            selectedID = annotation.id
            drag = .movingAnnotation(start: point, original: annotation)
        case .text:
            beginChange()
            let style = state.style
            let lineHeight = AnnotationRenderer.layout("", font: style.textFont, fontSize: AnnotationRenderer.fontSize(style, pointScale: document.scale)).lineHeight
            let annotation = Annotation(shape: .text(origin: CGPoint(x: point.x, y: point.y - lineHeight / 2), string: ""), style: state.style)
            document.state.add(annotation)
            beginTextEditing(id: annotation.id)
        case .colorPicker, .ruler:
            break  // 위에서 먼저 처리해 여기까지 오지 않는다
        }
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = location(event)
        let point = transform.toImage(viewPoint)
        let shift = event.modifierFlags.contains(.shift)
        let visible = document.visibleRect

        switch drag {
        case .none:
            // 누른 채 움직이면 mouseMoved가 오지 않으므로 컬러 피커 확대경을 여기서 따라가게 한다
            if state.tool.isInspection {
                hoverPoint = viewPoint
                invalidateInspection()
            }
            return
        case .selecting(let origin):
            let rect = RectMath.rect(from: origin, to: RectMath.clamp(point, to: visible), square: shift)
            selection = RectMath.clamp(RectMath.pixelRounded(rect), to: visible)
        case .movingSelection(let start, let original):
            selection = RectMath.moved(original, dx: (point.x - start.x).rounded(), dy: (point.y - start.y).rounded(), within: visible)
        case .resizingSelection(let handle, let original):
            // 넓이가 0이 되는 순간은 건너뛰어 선택 영역이 사라지지 않게 한다
            let rect = RectMath.resized(original, handle: handle, to: RectMath.clamp(point, to: visible), square: shift)
            if let resized = RectMath.clamp(RectMath.pixelRounded(rect), to: visible) { selection = resized }
        case .creating(let id, let origin):
            guard var annotation = document.state.annotation(id: id) else { return }
            let rect = RectMath.rect(from: origin, to: point, square: shift)
            let end = shift ? RectMath.snapAngle(from: origin, to: point) : point
            switch annotation.shape {
            case .rectangle: annotation.shape = .rectangle(rect)
            case .oval: annotation.shape = .oval(rect)
            case .highlighter: annotation.shape = .highlighter(rect)
            case .redact(_, let mode): annotation.shape = .redact(rect, mode)
            case .line: annotation.shape = .line(start: origin, end: end)
            case .arrow: annotation.shape = .arrow(start: origin, end: end)
            case .text, .image, .counter: break
            }
            document.state.replace(annotation)
        case .movingAnnotation(let start, let original):
            document.state.replace(original.moved(dx: point.x - start.x, dy: point.y - start.y))
        case .resizingAnnotation(let handle, let original):
            document.state.replace(original.draggingHandle(handle, to: point, constrain: shift, pointScale: document.scale))
        case .panning(let start, let origin):
            fitMode = false
            transform.origin = CGPoint(x: origin.x + viewPoint.x - start.x, y: origin.y + viewPoint.y - start.y)
            transform = transform.clamped(to: bounds.size)
            applyTransform()
            return
        case .measuring(let origin):
            // ⇧는 가로·세로·45°로 고정한다. 끝점은 보이는 영역 안의 픽셀 경계
            hoverPoint = viewPoint
            measurement = Measurement(start: origin, end: rulerPoint(shift ? RectMath.snapAngle(from: origin, to: point) : point))
            invalidateInspection()
            return
        }
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .creating(let id, _):
            // 클릭만 하고 끝난 도형은 버린다
            if let annotation = document.state.annotation(id: id), isTooSmall(annotation) {
                document.state.remove(id: id)
                selectedID = nil
            }
        case .selecting:
            if let selection, selection.width < 1 || selection.height < 1 { self.selection = nil }
        case .measuring:
            // 클릭만 하면 측정을 지우고 자동 간격 표시로 돌아간다
            if let measurement, measurement.start == measurement.end { self.measurement = nil }
        default:
            break
        }
        drag = .none
        endChange()
        redraw()
        updateCursor()
    }

    private func isTooSmall(_ annotation: Annotation) -> Bool {
        let minimum = 3 * document.scale
        switch annotation.shape {
        case .rectangle(let rect), .oval(let rect), .highlighter(let rect), .redact(let rect, _):
            return rect.width < minimum || rect.height < minimum
        case .arrow(let start, let end), .line(let start, let end):
            return hypot(end.x - start.x, end.y - start.y) < minimum
        case .text, .image, .counter:
            return false
        }
    }

    /// 클릭으로 고를 수 있는 주석. 그리기 도구에서는 베이스 레이어(이미지 등)를 건너뛰어 그 위에 바로 그릴 수 있게 한다
    private var hitTestCandidates: [Annotation] {
        state.tool == .select ? document.state.annotations : document.state.annotations.filter { !$0.isBaseLayer }
    }

    override func rightMouseDown(with event: NSEvent) {
        drag = .panning(start: location(event), origin: transform.origin)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        drag = .none
        updateCursor()
        invalidateInspection()
    }

    override func otherMouseDown(with event: NSEvent) {
        rightMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        drag = .none
        updateCursor()
        invalidateInspection()
    }

    /// 트랙패드 스크롤은 이동, 마우스 휠과 ⌘+스크롤은 확대·축소
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            fitMode = false
            transform = transform.panned(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY).clamped(to: bounds.size)
            applyTransform()
        } else {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 40 : event.scrollingDeltaY
            setZoom(transform.zoom * pow(1.15, delta), around: location(event))
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(transform.zoom * (1 + event.magnification), around: location(event))
    }

    // MARK: - 파일 드롭 (새 에디터로 열기)

    /// 다른 앱에서 끌어온 이미지 파일만 받는다. 툴바 손잡이로 끈 결과(같은 앱, draggingSource가 있음)는 받지 않는다
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource == nil && !ImageLoader.imageFileURLs(from: sender.draggingPasteboard).isEmpty ? .copy : []
    }

    /// 드래그가 끝난 뒤에 새 창을 열도록 다음 런루프로 미룬다
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = ImageLoader.imageFileURLs(from: sender.draggingPasteboard)
        guard sender.draggingSource == nil, !urls.isEmpty else { return false }
        Task { [weak self] in self?.onOpenFiles?(urls) }
        return true
    }

    // MARK: - 핸들·커서

    /// 선택 영역 핸들은 선택 도구에서만 보이고 동작한다
    private var showsSelectionHandles: Bool {
        state.tool == .select && textEditing == nil
    }

    /// 이미지 좌표 point 아래의 핸들을 찾는다. 선택한 주석의 핸들이 선택 영역 핸들보다 먼저다
    private func handleHit(at point: CGPoint) -> HandleHit? {
        let tolerance = Metrics.handleSize / transform.zoom
        if let selectedID, let selected = document.state.annotation(id: selectedID),
           let handle = HitTester.hitHandle(point, annotation: selected, pointScale: document.scale, tolerance: tolerance) {
            return .annotation(handle, selected)
        }
        if showsSelectionHandles, let selection,
           let handle = HitTester.nearestHandle(point, in: RectMath.handlePoints(of: selection), tolerance: tolerance) {
            return .selection(handle, selection)
        }
        return nil
    }

    // 커서 모양은 cursor rect 대신 tracking area로 직접 정한다 (핸들 영역이 겹쳐도 결과가 정해지도록)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    /// 측정 도구면 커서를 따라 확대경·간격 표시를 옮긴다 (그 부분만 다시 그린다)
    override func mouseMoved(with event: NSEvent) {
        updateCursor()
        guard state.tool.isInspection else { return }
        hoverPoint = location(event)
        invalidateInspection()
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    /// 커서가 캔버스를 벗어나거나 창이 키를 잃으면 확대경·간격 표시를 지운다
    func clearHover() {
        guard hoverPoint != nil else { return }
        hoverPoint = nil
        invalidateInspection()
    }

    /// 현재 마우스 위치에 맞게 커서를 바꾼다. 드래그 중이거나 텍스트 편집 상자 위면 그대로 둔다
    private func updateCursor() {
        guard let window, case .none = drag else { return }
        let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(viewPoint), textEditing?.view.frame.contains(viewPoint) != true else { return }
        cursor(at: viewPoint).set()
    }

    // Space 이동 → 측정 도구 → 핸들 크기 조절 → 도구별 기본 커서 순으로 정한다
    private func cursor(at viewPoint: CGPoint) -> NSCursor {
        if spaceHeld { return .openHand }
        // 측정 도구는 핸들을 다루지 않는다
        if state.tool.isInspection { return .crosshair }
        if let hit = handleHit(at: transform.toImage(viewPoint)) {
            guard let position = hit.handle.cursorPosition else { return .crosshair }
            return .frameResize(position: position, directions: .all)
        }
        switch state.tool {
        case .select: return .arrow
        case .text: return .iBeam
        case .rectangle, .oval, .line, .arrow, .highlighter, .counter, .redact, .colorPicker, .ruler: return .crosshair
        }
    }

    // MARK: - 측정 도구 (컬러 피커·픽셀 자)

    // 컬러 피커는 확대경 가운데 픽셀 색을 복사하고, 픽셀 자는 지난 측정을 지우고 새로 끌기 시작한다
    private func beginInspection(at viewPoint: CGPoint, shift: Bool) {
        hoverPoint = viewPoint
        if state.tool == .colorPicker {
            pickColor(at: viewPoint, asRGB: shift)
        } else {
            let origin = rulerPoint(transform.toImage(viewPoint))
            measurement = Measurement(start: origin, end: origin)
            drag = .measuring(origin: origin)
        }
        invalidateInspection()
    }

    /// 확대경 가운데 픽셀(원본, 주석 무시)의 색을 HEX 또는 RGB로 복사한다
    private func pickColor(at viewPoint: CGPoint, asRGB: Bool) {
        guard let pixel = inspectedPixel(at: viewPoint), let color = ImageSampler.color(at: pixel, in: document.image) else { return }
        exporter.copy(color: color, asRGB: asRGB, screen: window?.screen)
    }

    /// 뷰 좌표 아래의 이미지 픽셀 (내림). 보이는 영역 밖이면 nil. 확대경 가운데 칸·복사·자동 간격이 모두 이 픽셀을 쓴다
    private func inspectedPixel(at viewPoint: CGPoint) -> CGPoint? {
        let point = transform.toImage(viewPoint)
        let pixel = CGPoint(x: point.x.rounded(.down), y: point.y.rounded(.down))
        return document.visibleRect.contains(pixel) ? pixel : nil
    }

    // 측정 끝점: 보이는 영역 안의 가장 가까운 픽셀 경계
    private func rulerPoint(_ point: CGPoint) -> CGPoint {
        RectMath.clamp(CGPoint(x: point.x.rounded(), y: point.y.rounded()), to: document.visibleRect)
    }

    /// 측정 표시만 다시 그린다. 지난번에 그린 영역과 이번에 그릴 영역만 무효화해 마우스를 움직일 때 주석 전체를 다시 그리지 않는다
    private func invalidateInspection() {
        let regions = inspectionLayout()?.regions ?? []
        for rect in drawnInspection + regions {
            overlayView.setNeedsDisplay(rect)
        }
        drawnInspection = regions
    }

    /// 지금 그릴 측정 표시. 측정 도구가 아니거나 Space 이동·다른 드래그 중이면 nil
    /// 컬러 피커는 확대경, 픽셀 자는 측정선이 있으면 측정선을, 없으면 커서 아래 자동 간격을 보인다
    private func inspectionLayout() -> InspectionLayout? {
        guard state.tool.isInspection, !spaceHeld else { return nil }
        switch drag {
        case .none, .measuring: break
        default: return nil
        }

        var layout = InspectionLayout()
        if state.tool == .colorPicker {
            guard let hoverPoint, let pixel = inspectedPixel(at: hoverPoint) else { return nil }
            let info = loupeInfo(pixel: pixel)
            layout.loupe = (pixel, info, Loupe.frame(at: hoverPoint, info: info, in: bounds))
        } else if let measurement {
            // 누르고 아직 끌지 않았으면 그리지 않는다
            guard measurement.start != measurement.end else { return nil }
            let end = transform.toView(measurement.end)
            layout.segments = [Segment(start: transform.toView(measurement.start), end: end)]
            let text = measurementText(measurement)
            layout.label = (text, SizeLabel.frame(text: text, beside: end, in: bounds))
        } else {
            guard let hoverPoint, let pixel = inspectedPixel(at: hoverPoint), let span = span(at: pixel) else { return nil }
            layout.segments = spanSegments(pixel: pixel, span: span)
            let text = SizeLabel.text(pixelSize: CGSize(width: span.horizontal.count, height: span.vertical.count), scale: document.scale)
            layout.label = (text, SizeLabel.frame(text: text, beside: hoverPoint, in: bounds))
        }
        return layout
    }

    private func drawInspection(_ ctx: CGContext) {
        guard let layout = inspectionLayout() else { return }
        if let loupe = layout.loupe {
            Loupe.draw(ctx, image: document.image, center: loupe.pixel, readable: document.visibleRect, info: loupe.info, in: loupe.frame)
        }
        layout.segments.forEach { drawRulerLine(ctx, $0) }
        if let label = layout.label {
            SizeLabel.draw(text: label.text, in: label.frame)
        }
    }

    // 확대경 정보 줄: 보이는 영역 왼쪽 위 기준 좌표(논리 픽셀)와 HEX, 다음 줄에 RGB
    private func loupeInfo(pixel: CGPoint) -> [String] {
        let visible = document.visibleRect
        let position = "\(Int((pixel.x - visible.minX) / document.scale)), \(Int((pixel.y - visible.minY) / document.scale))"
        guard let color = ImageSampler.color(at: pixel, in: document.image) else { return [position] }
        return ["\(position)   \(color.hex)", color.rgbString]
    }

    // 자동 간격 (원본 이미지, 보이는 영역 안). 커서가 같은 픽셀에 있으면 지난 결과를 쓴다
    private func span(at pixel: CGPoint) -> ImageSampler.Span? {
        let visible = document.visibleRect
        if let spanCache, spanCache.pixel == pixel, spanCache.visible == visible { return spanCache.span }
        let span = ImageSampler.span(at: pixel, in: document.image, within: visible, tolerance: Metrics.spanTolerance)
        spanCache = (pixel, visible, span)
        return span
    }

    // 간격 선 두 개 (뷰 좌표). 가로선은 커서 픽셀 행의 가운데, 세로선은 열의 가운데를 지나고 1pt 선이 선명하게 +0.5에 맞춘다
    private func spanSegments(pixel: CGPoint, span: ImageSampler.Span) -> [Segment] {
        let row = transform.toView(CGPoint(x: 0, y: pixel.y + 0.5)).y.rounded(.down) + 0.5
        let column = transform.toView(CGPoint(x: pixel.x + 0.5, y: 0)).x.rounded(.down) + 0.5
        let left = transform.toView(CGPoint(x: CGFloat(span.horizontal.lowerBound), y: 0)).x
        let right = transform.toView(CGPoint(x: CGFloat(span.horizontal.upperBound), y: 0)).x
        let top = transform.toView(CGPoint(x: 0, y: CGFloat(span.vertical.lowerBound))).y
        let bottom = transform.toView(CGPoint(x: 0, y: CGFloat(span.vertical.upperBound))).y
        return [
            Segment(start: CGPoint(x: left, y: row), end: CGPoint(x: right, y: row)),
            Segment(start: CGPoint(x: column, y: top), end: CGPoint(x: column, y: bottom)),
        ]
    }

    // "W × H · 길이" (논리 픽셀)
    private func measurementText(_ measurement: Measurement) -> String {
        let dx = abs(measurement.end.x - measurement.start.x)
        let dy = abs(measurement.end.y - measurement.start.y)
        let size = SizeLabel.text(pixelSize: CGSize(width: dx, height: dy), scale: document.scale)
        return "\(size) · \(SizeLabel.format(hypot(dx, dy) / document.scale))"
    }

    // 어떤 배경에서도 보이도록 흰 바탕 위에 강조색 선을 긋고 양 끝에 직각 눈금을 단다
    private func drawRulerLine(_ ctx: CGContext, _ segment: Segment) {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let normal = CGPoint(x: -dy / length * Metrics.tick, y: dx / length * Metrics.tick)
        var points = [segment.start, segment.end]
        for end in [segment.start, segment.end] {
            points += [CGPoint(x: end.x - normal.x, y: end.y - normal.y), CGPoint(x: end.x + normal.x, y: end.y + normal.y)]
        }
        ctx.saveGState()
        ctx.setLineWidth(3)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        ctx.strokeLineSegments(between: points)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(Metrics.ruler)
        ctx.strokeLineSegments(between: points)
        ctx.restoreGState()
    }

    // MARK: - 키보드

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let step = (flags.contains(.shift) ? 10 : 1) * document.scale
        let resize = flags.contains(.command)

        switch event.keyCode {
        case 53: handleEscape()
        case 36, 76: cropToSelection(nil)
        case 51, 117: delete(nil)
        case 123: nudge(dx: -step, dy: 0, resize: resize)
        case 124: nudge(dx: step, dy: 0, resize: resize)
        case 125: nudge(dx: 0, dy: step, resize: resize)
        case 126: nudge(dx: 0, dy: -step, resize: resize)
        case 49:
            if !event.isARepeat {
                spaceHeld = true
                updateCursor()
                invalidateInspection()
            }
        default:
            if flags.isDisjoint(with: [.command, .control, .option]), let tool = EditorState.Tool(keyCode: event.keyCode) {
                selectTool(tool)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            updateCursor()
            invalidateInspection()
        } else {
            super.keyUp(with: event)
        }
    }

    /// Esc는 단계적으로: 측정 지우기 → 측정 도구면 선택 도구로 → 주석 선택 해제 → 선택 영역 해제 → 설정된 동작 후 창 닫기
    /// 측정 도구 단계는 색을 복사한 직후 Esc로 창이 닫히며 클립보드가 이미지로 바뀌지 않게 한 번 멈춘다
    private func handleEscape() {
        if measurement != nil {
            measurement = nil
            invalidateInspection()
        } else if state.tool.isInspection {
            selectTool(.select)
        } else if selectedID != nil {
            selectedID = nil
            redraw()
        } else if selection != nil {
            selection = nil
            redraw()
        } else {
            switch preferences.escAction {
            case .copy: exportOutput(copy: true, save: false)
            case .save: exportOutput(copy: false, save: true)
            case .copySave: exportOutput(copy: true, save: true)
            case .none: break
            }
            onRequestClose?()
        }
    }

    // 선택한 주석을 옮기거나, 선택 영역을 옮기거나 크기를 바꾼다
    private func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        if let selectedID, let annotation = document.state.annotation(id: selectedID) {
            applyChange { $0.replace(annotation.moved(dx: dx, dy: dy)) }
        } else if let selection {
            self.selection = resize
                ? RectMath.resized(selection, dw: dx, dh: dy, within: document.visibleRect)
                : RectMath.moved(selection, dx: dx, dy: dy, within: document.visibleRect)
            redraw()
        }
    }

    // MARK: - 도구·스타일 (툴바에서 호출)

    func selectTool(_ tool: EditorState.Tool) {
        commitTextEditing()
        state.tool = tool
        measurement = nil
        // 측정 도구는 주석을 다루지 않으므로 선택을 풀고, 키로 바꿔 커서가 캔버스 안에 있으면 바로 확대경·간격을 보인다
        if tool.isInspection {
            selectedID = nil
            hoverPoint = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }.flatMap { bounds.contains($0) ? $0 : nil }
        } else {
            hoverPoint = nil
        }
        window?.makeFirstResponder(self)
        redraw()
        updateCursor()
    }

    func applyColor(_ color: RGBAColor) {
        state.color = color
        preferences.annotationColor = color
        updateSelectedStyle { $0.color = color }
        window?.makeFirstResponder(textEditing?.view ?? self)
    }

    /// 크기를 바꾼다. 텍스트는 핸들로 조절한 배율을 유지해 슬라이더를 끄는 동안 크기가 튀지 않는다
    func applySize(_ size: AnnotationSize) {
        guard size != state.size else { return }
        state.size = size
        preferences.annotationSize = size
        updateSelectedStyle { $0.size = size }
    }

    /// 슬라이더를 끌기 시작하면 변경을 하나로 묶는다. 텍스트 편집처럼 진행 중인 변경이 있으면 그 안에 합친다
    func beginSizeEditing() {
        guard changeStart == nil else { return }
        beginChange()
        sizeChangeOpen = true
    }

    /// 슬라이더를 놓으면 묶은 변경을 끝내고 키 입력을 캔버스(또는 편집 중인 텍스트)로 돌린다
    func endSizeEditing() {
        if sizeChangeOpen { endChange() }
        window?.makeFirstResponder(textEditing?.view ?? self)
    }

    func applyTextFont(_ font: TextFont) {
        state.textFont = font
        preferences.annotationTextFont = font
        updateSelectedStyle { $0.textFont = font }
        window?.makeFirstResponder(textEditing?.view ?? self)
    }

    func applyTextBackground(_ enabled: Bool) {
        state.textBackground = enabled
        preferences.annotationTextBackground = enabled
        updateSelectedStyle { $0.textBackground = enabled }
        window?.makeFirstResponder(textEditing?.view ?? self)
    }

    /// 가리기 방식을 바꾼다. 가리기 주석을 골랐으면 그 주석도 바꾼다
    func applyRedactMode(_ mode: RedactMode) {
        state.redactMode = mode
        preferences.annotationRedactMode = mode
        if let selectedID, var annotation = document.state.annotation(id: selectedID),
           case .redact(let rect, _) = annotation.shape {
            annotation.shape = .redact(rect, mode)
            applyChange { $0.replace(annotation) }
        }
        window?.makeFirstResponder(self)
    }

    // 편집 중인 텍스트 또는 선택한 주석에 스타일 변경을 적용한다
    private func updateSelectedStyle(_ change: (inout AnnotationStyle) -> Void) {
        guard let id = textEditing?.id ?? selectedID, var annotation = document.state.annotation(id: id) else { return }
        change(&annotation.style)
        applyChange { $0.replace(annotation) }
        if let textEditing {
            applyTextStyle(textEditing.view, style: annotation.style)
            layoutTextEditor()
        }
    }

    // MARK: - 실행 취소

    private func beginChange() {
        if changeStart == nil { changeStart = document.state }
    }

    /// 변경이 실제로 있었을 때만 실행 취소 기록을 남긴다
    private func endChange() {
        sizeChangeOpen = false
        guard let start = changeStart else { return }
        changeStart = nil
        if start != document.state { history.record(start) }
        updateToolbarInfo()
    }

    // 즉시 적용하는 변경. 진행 중인 변경(텍스트 편집 등)이 있으면 그 안에 합친다
    private func applyChange(_ body: (inout EditState) -> Void) {
        let ownsChange = changeStart == nil
        beginChange()
        body(&document.state)
        if ownsChange { endChange() }
        redraw()
    }

    private func restore(_ newState: EditState) {
        let cropChanged = newState.crop != document.state.crop
        document.state = newState
        if let selectedID, newState.annotation(id: selectedID) == nil { self.selectedID = nil }
        if cropChanged {
            selection = nil
            syncVisibleRect()
        }
        redraw()
    }

    @objc func undo(_ sender: Any?) {
        if let textEditing {
            textEditing.view.undoManager?.undo()
            return
        }
        if let previous = history.undo(current: document.state) { restore(previous) }
    }

    @objc func redo(_ sender: Any?) {
        if let textEditing {
            textEditing.view.undoManager?.redo()
            return
        }
        if let next = history.redo(current: document.state) { restore(next) }
    }

    // MARK: - 편집 명령 (메뉴)

    /// 선택한 주석을 지운다. 주석 선택 없이 선택 영역만 있으면 그 안에 들어간 주석을 모두 지운다 (배경은 그대로)
    @objc func delete(_ sender: Any?) {
        if let selectedID {
            applyChange { $0.remove(id: selectedID) }
            self.selectedID = nil
        } else {
            let ids = Set(annotationIDsInSelection)
            guard !ids.isEmpty else { return }
            applyChange { $0.remove(ids: ids) }
        }
    }

    /// 선택 영역 안에 들어간 주석 id. 보이는 영역 가장자리에 닿은 변은 바깥으로 늘려 가장자리에 걸친 주석도 담는다
    /// 크롭으로 보이지 않는 주석은 넣지 않는다
    private var annotationIDsInSelection: [UUID] {
        guard let selection else { return [] }
        let visible = document.visibleRect
        let range = RectMath.extendingEdges(of: selection, touching: visible)
        let shown = document.state.annotations.filter {
            AnnotationRenderer.bounds(of: $0, pointScale: document.scale).intersects(visible)
        }
        return HitTester.annotations(inside: range, annotations: shown, pointScale: document.scale)
    }

    /// 클립보드 이미지를 지금 보이는 곳 가운데에 겹쳐 놓는다
    /// 원래 논리 크기로 넣되 보이는 영역의 90%를 넘으면 비율을 유지해 줄인다
    @objc func paste(_ sender: Any?) {
        guard let loaded = ImageLoader.load(from: .general) else { return }
        let visible = document.visibleRect
        let ratio = document.scale / loaded.scale
        var size = CGSize(width: CGFloat(loaded.image.width) * ratio, height: CGFloat(loaded.image.height) * ratio)
        let fit = min(1, visible.width * 0.9 / size.width, visible.height * 0.9 / size.height)
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())

        let center = RectMath.clamp(transform.toImage(CGPoint(x: bounds.midX, y: bounds.midY)), to: visible)
        let origin = CGPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        let rect = RectMath.moved(CGRect(origin: origin, size: size), dx: 0, dy: 0, within: visible)
        let annotation = Annotation(shape: .image(rect, SendableImage(loaded.image)), style: state.style)

        if state.tool != .select { selectTool(.select) }
        applyChange { $0.add(annotation) }
        selectedID = annotation.id
        redraw()
    }

    @objc override func selectAll(_ sender: Any?) {
        selectedID = nil
        selection = document.visibleRect
        redraw()
    }

    @objc func cropToSelection(_ sender: Any?) {
        guard let selection else { return }
        applyChange { $0.crop = selection }
        self.selection = nil
        syncVisibleRect()
    }

    @objc func resetCrop(_ sender: Any?) {
        guard document.state.crop != nil else { return }
        applyChange { $0.crop = nil }
        selection = nil
        syncVisibleRect()
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(transform.zoom * Metrics.zoomStep, around: zoomAnchor)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(transform.zoom / Metrics.zoomStep, around: zoomAnchor)
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        setZoom(1 / document.scale, around: zoomAnchor)
    }

    @objc func zoomToFit(_ sender: Any?) {
        fitMode = true
        transform = fitTransform()
        applyTransform()
    }

    @objc func zoomToSelection(_ sender: Any?) {
        guard let selection else { return }
        fitMode = false
        transform = transform.focused(on: selection, in: bounds.size, padding: Metrics.padding * 2).clamped(to: bounds.size)
        applyTransform()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): textEditing != nil || history.canUndo
        case #selector(redo(_:)): textEditing != nil || history.canRedo
        case #selector(cropToSelection(_:)), #selector(zoomToSelection(_:)): selection != nil
        case #selector(resetCrop(_:)): document.state.crop != nil
        case #selector(delete(_:)): selectedID != nil || !annotationIDsInSelection.isEmpty
        case #selector(paste(_:)): ImageLoader.canLoad(from: .general)
        default: true
        }
    }

    // MARK: - 내보내기

    private func renderOutput(region: CGRect? = nil) -> CGImage? {
        DocumentRenderer.render(image: document.image, state: document.state, scale: document.scale, region: region)
    }

    /// 선택 영역이 있으면 그 부분만 복사한다
    @objc func copy(_ sender: Any?) {
        guard let image = renderOutput(region: selection) else { return }
        let scale = document.scale
        let screen = window?.screen
        Task { [exporter] in
            await exporter.export(image, scale: scale, copy: true, save: false, overwriting: nil, screen: screen)
        }
    }

    /// 끌어놓기 결과를 백그라운드에서 미리 인코딩한다 (6K PNG는 약 0.6초가 걸려 드래그 시작이 끊기지 않게)
    func prepareDragPayload() {
        guard textEditing == nil, dragPreparation == nil, preparedDrag?.state != document.state, let image = renderOutput() else { return }
        let state = document.state
        let scale = document.scale
        dragPreparation = Task { [weak self, exporter] in
            let png = await exporter.encodePNG(image, scale: scale)
            guard let self else { return }
            dragPreparation = nil
            if let png { preparedDrag = (state, makeDragPayload(image: image, png: png)) }
        }
    }

    /// 끌어놓기로 내보낼 결과 이미지. 미리 준비한 결과가 지금 상태와 같으면 쓰고, 아니면 바로 렌더링·인코딩한다
    func dragPayload() -> DragPayload? {
        commitTextEditing()
        if let prepared = preparedDrag, prepared.state == document.state { return prepared.payload }
        let started = ContinuousClock.now
        guard let image = renderOutput(), let png = ImageEncoder.pngData(image, scale: document.scale) else { return nil }
        Log.editor.info("끌어놓기 바로 인코딩 \(image.width)×\(image.height): \((ContinuousClock.now - started).milliseconds, format: .fixed(precision: 1))ms")
        return makeDragPayload(image: image, png: png)
    }

    // 미리보기는 논리 크기를 160pt 안으로 줄인다
    private func makeDragPayload(image: CGImage, png: Data) -> DragPayload {
        let logical = CGSize(width: CGFloat(image.width) / document.scale, height: CGFloat(image.height) / document.scale)
        let fit = min(1, 160 / max(logical.width, logical.height))
        let preview = NSImage(cgImage: image, size: NSSize(width: logical.width * fit, height: logical.height * fit))
        let fileName = document.savedURL?.lastPathComponent ?? exporter.suggestedFileName(appName: document.sourceAppName)
        return DragPayload(png: png, fileName: fileName, preview: preview)
    }

    /// 편집 중인 텍스트를 확정하고 지금 문서를 화면에 고정한다 (에디터는 닫힌다)
    @objc func pinToScreen(_ sender: Any?) {
        commitTextEditing()
        onRequestPin?(document)
    }

    @objc func saveDocument(_ sender: Any?) {
        exportOutput(copy: false, save: true)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = document.savedURL?.lastPathComponent ?? exporter.suggestedFileName(appName: document.sourceAppName)
        panel.directoryURL = document.savedURL?.deletingLastPathComponent() ?? preferences.saveFolder
        // 다른 이름으로 저장한 뒤에는 ⌘S도 이 파일에 덮어쓴다
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.exportOutput(copy: false, save: true, target: url) }
        }
    }

    /// 같은 캡처는 같은 파일에 덮어쓴다. target이 없으면 자동 저장 파일 또는 마지막 저장 파일
    private func exportOutput(copy: Bool, save: Bool, target: URL? = nil) {
        guard copy || save, let image = renderOutput() else { return }
        let scale = document.scale
        let existing = target ?? document.savedURL
        let appName = document.sourceAppName
        let screen = window?.screen
        Task { [weak self, exporter] in
            if let url = await exporter.export(image, scale: scale, copy: copy, save: save, overwriting: existing, appName: appName, screen: screen) {
                self?.document.savedURL = url
            }
        }
    }

    #if DEBUG
    /// 개발용: 좌표 변환 확인을 위해 이미지 기준 위치에 샘플 주석과 선택 영역을 넣는다
    func debugAddSamples() {
        let bounds = document.visibleRect
        let style = state.style
        // applyChange가 document.state를 inout으로 잡는 동안 document를 다시 읽으면 배타적 접근 위반이라 미리 자른다
        let source = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 3, height: bounds.height / 3)
        let piece = document.image.cropping(to: source)
        applyChange { edit in
            edit.annotations.append(Annotation(shape: .rectangle(CGRect(x: bounds.minX + 40, y: bounds.minY + 40, width: bounds.width / 2 - 80, height: bounds.height / 2 - 80)), style: style))
            edit.annotations.append(Annotation(shape: .arrow(start: CGPoint(x: bounds.maxX - 60, y: bounds.maxY - 60), end: CGPoint(x: bounds.midX + 20, y: bounds.midY + 20)), style: style))
            edit.annotations.append(Annotation(shape: .text(origin: CGPoint(x: bounds.minX + 40, y: bounds.midY + 40), string: "주석 Text\n두 번째 줄"), style: AnnotationStyle(color: RGBAColor.palette[7], size: .large)))
            // 배경 상자 텍스트: 둥근 글꼴, 핸들로 1.5배 키운 상태
            let label = AnnotationStyle(color: RGBAColor.palette[4], size: .medium, textFont: .rounded, textBackground: true, fontScale: 1.5)
            edit.annotations.append(Annotation(shape: .text(origin: CGPoint(x: bounds.minX + 60, y: bounds.maxY - 160), string: "배경 라벨 Label"), style: label))
            // 가리기: 왼쪽 위 텍스트 부분을 픽셀화, 그 오른쪽을 블러
            edit.add(Annotation(shape: .redact(CGRect(x: bounds.minX + 120, y: bounds.minY + 120, width: 360, height: 120), .pixelate), style: style))
            edit.add(Annotation(shape: .redact(CGRect(x: bounds.minX + 520, y: bounds.minY + 120, width: 360, height: 120), .blur), style: style))
            // 타원·선·형광펜·카운터
            edit.add(Annotation(shape: .highlighter(CGRect(x: bounds.minX + 120, y: bounds.minY + 280, width: 700, height: 60)), style: AnnotationStyle(color: RGBAColor.palette[2], size: .medium)))
            edit.add(Annotation(shape: .oval(CGRect(x: bounds.midX + 120, y: bounds.midY - 60, width: 240, height: 140)), style: style))
            edit.add(Annotation(shape: .line(start: CGPoint(x: bounds.minX + 120, y: bounds.midY + 200), end: CGPoint(x: bounds.midX, y: bounds.midY + 200)), style: AnnotationStyle(color: RGBAColor.palette[3], size: .medium)))
            for (index, x) in [bounds.midX + 60, bounds.midX + 160].enumerated() {
                edit.add(Annotation(shape: .counter(center: CGPoint(x: x, y: bounds.minY + 200), number: index + 1), style: AnnotationStyle(color: RGBAColor.palette[4], size: .large)))
            }
            // 붙여넣은 이미지: 원본 왼쪽 위 일부를 오른쪽 아래에 절반 크기로 겹친다
            if let piece {
                let rect = CGRect(x: bounds.maxX - source.width / 2 - 40, y: bounds.maxY - source.height / 2 - 40, width: source.width / 2, height: source.height / 2)
                edit.add(Annotation(shape: .image(rect, SendableImage(piece)), style: style))
            }
        }
        // 마지막 텍스트(배경 라벨)를 골라 텍스트 핸들과 툴바 텍스트 옵션을 보인다
        selectedID = document.state.annotations.last { $0.isText }?.id
        selection = CGRect(x: bounds.midX + 40, y: bounds.minY + 40, width: 400, height: 200)
        redraw()
    }

    /// 개발용: 측정 도구를 고르고 이미지 픽셀 point에 커서가 있는 것처럼 확대경·자동 간격을 보인다
    /// end가 있으면 point → end 측정선을 보인다
    func debugInspect(tool: EditorState.Tool, at point: CGPoint, measureTo end: CGPoint?) {
        selectTool(tool)
        hoverPoint = transform.toView(CGPoint(x: point.x + 0.5, y: point.y + 0.5))
        measurement = end.map { Measurement(start: rulerPoint(point), end: rulerPoint($0)) }
        redraw()
    }
    #endif

    // MARK: - 텍스트 편집

    private func beginTextEditing(id: UUID) {
        guard textEditing == nil, let annotation = document.state.annotation(id: id), case .text(_, let string) = annotation.shape else { return }
        beginChange()
        selectedID = nil

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        applyTextStyle(textView, style: annotation.style)
        textView.string = string
        textView.delegate = self
        addSubview(textView)

        textEditing = TextEditing(id: id, view: textView)
        layoutTextEditor()
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        redraw()
    }

    // 렌더러와 같은 글꼴·글자 색을 현재 배율로 맞춘다 (CTFont와 NSFont는 toll-free 브리지)
    private func applyTextStyle(_ textView: NSTextView, style: AnnotationStyle) {
        let size = AnnotationRenderer.fontSize(style, pointScale: document.scale) * transform.zoom
        let font = AnnotationRenderer.font(style.textFont, size: size) as NSFont
        let color = NSColor(cgColor: AnnotationRenderer.textColor(style)) ?? .systemRed
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes = [.font: font, .foregroundColor: color]
    }

    private func layoutTextEditor() {
        guard let textEditing, let annotation = document.state.annotation(id: textEditing.id),
              case .text(let origin, _) = annotation.shape,
              let layoutManager = textEditing.view.layoutManager,
              let container = textEditing.view.textContainer,
              let font = textEditing.view.font else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let viewOrigin = transform.toView(origin)
        textEditing.view.frame = NSRect(
            x: viewOrigin.x,
            y: viewOrigin.y,
            width: max(used.width + font.pointSize, 24),
            height: max(used.height, lineHeight)
        )
    }

    /// 편집 중에도 배경 상자가 글자를 따라가도록 모델 문자열을 갱신한다 (beginTextEditing에서 시작한 변경에 포함)
    func textDidChange(_ notification: Notification) {
        if let textEditing, var annotation = document.state.annotation(id: textEditing.id), case .text(let origin, _) = annotation.shape {
            annotation.shape = .text(origin: origin, string: textEditing.view.string)
            document.state.replace(annotation)
        }
        layoutTextEditor()
        redraw()
    }

    /// Enter는 확정, Shift+Enter는 줄바꿈, Esc는 확정
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            commitTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditing()
            return true
        }
        return false
    }

    /// 빈 텍스트는 지우고, 내용이 있으면 주석에 반영한 뒤 선택 상태로 둔다
    private func commitTextEditing() {
        guard let editing = textEditing else { return }
        textEditing = nil
        let text = editing.view.string
        editing.view.removeFromSuperview()

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.state.remove(id: editing.id)
        } else if var annotation = document.state.annotation(id: editing.id), case .text(let origin, _) = annotation.shape {
            annotation.shape = .text(origin: origin, string: text)
            document.state.replace(annotation)
            selectedID = annotation.id
        }
        endChange()
        window?.makeFirstResponder(self)
        redraw()
    }
}

private extension Annotation {
    /// 가리기 주석의 방식. 다른 주석이면 nil
    var redactMode: RedactMode? {
        guard case .redact(_, let mode) = shape else { return nil }
        return mode
    }
}

private extension AnnotationHandle {
    /// 크기 조절 커서 방향. 화살표 끝점 핸들은 방향이 없어 nil
    var cursorPosition: NSCursor.FrameResizePosition? {
        switch self {
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        case .start, .end: nil
        }
    }
}
