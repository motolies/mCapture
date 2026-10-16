import AppKit
import MCaptureCore

/// 화면 위에 항상 떠 있는 캡처 이미지. 끌어서 옮기고 스크롤·핀치로 크기를 바꾸며, 우클릭 메뉴로 다룬다
/// 앱을 활성화하지 않는 패널이라 다른 앱을 쓰면서 참고 자료로 띄워 둘 수 있다
@MainActor
final class PinPanel: NSPanel {
    var onClose: ((PinPanel) -> Void)?
    /// 편집을 고르면 문서(편집 상태 포함)를 넘기고 핀은 닫힌다
    var onEdit: ((CaptureDocument, NSScreen?) -> Void)?

    private var document: CaptureDocument
    private let image: CGImage
    private let exporter: Exporter
    /// 100%일 때 크기 (논리 포인트)
    private let naturalSize: CGSize
    private var semiTransparent = false

    private enum Metrics {
        static let minSide: CGFloat = 48
        static let maxScale: CGFloat = 4
        static let initialScreenFraction: CGFloat = 0.8
    }

    init(document: CaptureDocument, image: CGImage, exporter: Exporter, screen: NSScreen?) {
        self.document = document
        self.image = image
        self.exporter = exporter
        self.naturalSize = CGSize(width: CGFloat(image.width) / document.scale, height: CGFloat(image.height) / document.scale)
        super.init(contentRect: NSRect(origin: .zero, size: naturalSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let view = PinView(image: image)
        view.onDrag = { [weak self] event in self?.performDrag(with: event) }
        view.onScale = { [weak self] factor, anchor in self?.scale(by: factor, around: anchor) }
        view.makeMenu = { [weak self] in self?.contextMenu() }
        view.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        contentView = view
        place(on: screen ?? NSScreen.underMouse ?? NSScreen.main)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        onClose?(self)
    }

    // 논리 크기로 띄우되 화면의 80%를 넘으면 비율을 유지해 줄이고 화면 가운데에 둔다
    private func place(on screen: NSScreen?) {
        guard let area = screen?.visibleFrame else { return }
        let fit = min(1, area.width * Metrics.initialScreenFraction / naturalSize.width, area.height * Metrics.initialScreenFraction / naturalSize.height)
        let size = CGSize(width: (naturalSize.width * fit).rounded(), height: (naturalSize.height * fit).rounded())
        setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }

    // MARK: - 크기

    /// anchor(화면 좌표)를 고정한 채 크기를 바꾼다. 짧은 변 48pt ~ 원래 크기 4배로 제한한다
    private func scale(by factor: CGFloat, around anchor: CGPoint) {
        let current = frame
        let minWidth = Metrics.minSide * max(1, naturalSize.width / naturalSize.height)
        let width = min(max(current.width * factor, minWidth), naturalSize.width * Metrics.maxScale)
        setFrame(RectMath.scaled(current, by: width / current.width, around: anchor).integral, display: true)
    }

    // 메뉴의 50% / 100% / 200%: 가운데를 고정한다
    private func setZoom(_ zoom: CGFloat) {
        scale(by: naturalSize.width * zoom / frame.width, around: CGPoint(x: frame.midX, y: frame.midY))
    }

    // MARK: - 메뉴·키

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        for zoom in [0.5, 1, 2] as [CGFloat] {
            let item = ClosureMenuItem("\(Int(zoom * 100))%", modifiers: []) { [weak self] in self?.setZoom(zoom) }
            item.state = abs(frame.width - naturalSize.width * zoom) < 1 ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let transparent = ClosureMenuItem("반투명", modifiers: []) { [weak self] in self?.toggleSemiTransparent() }
        transparent.state = semiTransparent ? .on : .off
        menu.addItem(transparent)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("복사", keyEquivalent: "c") { [weak self] in self?.copyImage() })
        menu.addItem(ClosureMenuItem("저장", keyEquivalent: "s") { [weak self] in self?.saveImage() })
        menu.addItem(ClosureMenuItem("편집", modifiers: []) { [weak self] in self?.edit() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("닫기", keyEquivalent: "w") { [weak self] in self?.close() })
        return menu
    }

    /// 한글 입력 상태에서도 되도록 키 코드로 판별한다. 처리했으면 true
    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        switch (event.keyCode, command) {
        case (53, false), (13, true), (12, true): close()   // Esc, ⌘W, ⌘Q(앱은 종료하지 않음)
        case (8, true): copyImage()                         // ⌘C
        case (1, true): saveImage()                         // ⌘S
        default: return false
        }
        return true
    }

    // 반투명하면 그림자를 꺼 아래 화면과 겹쳐 비교하기 쉽게 한다
    private func toggleSemiTransparent() {
        semiTransparent.toggle()
        alphaValue = semiTransparent ? 0.5 : 1
        hasShadow = !semiTransparent
    }

    private func copyImage() {
        let (image, scale, screen) = (image, document.scale, self.screen)
        Task { [exporter] in
            await exporter.export(image, scale: scale, copy: true, save: false, overwriting: nil, screen: screen)
        }
    }

    /// 같은 캡처는 같은 파일에 덮어쓴다
    private func saveImage() {
        let (image, scale, existing, appName, screen) = (image, document.scale, document.savedURL, document.sourceAppName, self.screen)
        Task { [weak self, exporter] in
            if let url = await exporter.export(image, scale: scale, copy: false, save: true, overwriting: existing, appName: appName, screen: screen) {
                self?.document.savedURL = url
            }
        }
    }

    private func edit() {
        onEdit?(document, screen)
        close()
    }
}

/// 핀 내용: 이미지와 얇은 테두리. 마우스·키 입력은 패널로 넘긴다
private final class PinView: NSView {
    var onDrag: ((NSEvent) -> Void)?
    var onScale: ((CGFloat, CGPoint) -> Void)?
    var makeMenu: (() -> NSMenu?)?
    var onKey: ((NSEvent) -> Bool)?

    private let imageView = ImageLayerView()

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.5, alpha: 0.6).cgColor
        imageView.image = image
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onDrag?(event)
    }

    /// 마우스 휠은 한 칸에 10%, 트랙패드는 이동량에 비례해 커서 위치를 기준으로 크기를 바꾼다
    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
        guard delta != 0 else { return }
        onScale?(pow(1.1, delta), NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        onScale?(1 + event.magnification, NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu?()
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    // 키 창이 아닐 때도 단축키가 돌아올 수 있어, 에디터의 ⌘C 등을 가로채지 않게 키 창일 때만 처리한다
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
        return onKey?(event) == true || super.performKeyEquivalent(with: event)
    }
}
