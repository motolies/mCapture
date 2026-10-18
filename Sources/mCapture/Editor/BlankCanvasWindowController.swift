import AppKit
import MCaptureCore

/// 실행 중에 앱을 다시 실행하면 뜨는 빈 캔버스. 이미지를 끌어다 놓거나 붙여넣으면 그 이미지의 에디터로 바뀐다
final class BlankCanvasWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    /// 받은 이미지. 파일을 여러 개 놓으면 여러 장이다
    var onImages: (([LoadedImage]) -> Void)?

    private let canvas = BlankCanvasView()
    private static let contentSize = NSSize(width: 640, height: 400)

    /// others: 이미 열린 에디터 창. 같은 자리에 겹치지 않게 비켜 띄운다
    init(screen: NSScreen?, avoiding others: [NSWindow]) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 400, height: 260)
        window.title = "\(AppVariant.current.displayName) — 빈 캔버스"
        window.contentView = canvas

        super.init(window: window)
        window.delegate = self
        canvas.onImages = { [weak self] images in self?.onImages?(images) }
        canvas.onCancel = { [weak self] in self?.close() }
        window.center(on: screen, avoiding: others)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 앱이 활성화되지 못해도 창이 보이도록 강제로 앞에 띄운다
    func present() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// 빈 캔버스 내용: 놓을 자리 테두리와 안내 문구. 다른 앱에서 끌어온 이미지 파일·데이터와 클립보드 이미지를 받는다
private final class BlankCanvasView: NSView {
    var onImages: (([LoadedImage]) -> Void)?
    var onCancel: (() -> Void)?

    /// 받을 수 있는 이미지를 끌어와 캔버스 위에 있는 동안 테두리를 강조한다
    private var isDropTarget = false {
        didSet { if isDropTarget != oldValue { needsDisplay = true } }
    }

    @MainActor
    private enum Metrics {
        static let background = NSColor(white: 0.13, alpha: 1)
        static let inset: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let iconSpacing: CGFloat = 14
        static let lineSpacing: CGFloat = 6
        static let title = NSAttributedString(string: "이미지를 끌어다 놓거나 붙여넣으세요 (⌘V)", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.85),
        ])
        static let detail = NSAttributedString(string: "파일을 여러 개 놓으면 각각 에디터로 열립니다 · Esc로 닫기", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(white: 1, alpha: 0.45),
        ])
        static let icon = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 40, weight: .light)
                    .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor(white: 1, alpha: 0.6)))
            )
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    // 놓을 자리 테두리를 그리고 아이콘·안내 두 줄을 가운데에 쌓는다
    override func draw(_ dirtyRect: NSRect) {
        Metrics.background.setFill()
        bounds.fill()

        let zone = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Metrics.inset, dy: Metrics.inset),
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        if isDropTarget {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            zone.fill()
        }
        (isDropTarget ? NSColor.controlAccentColor : NSColor(white: 1, alpha: 0.25)).setStroke()
        zone.lineWidth = 2
        zone.setLineDash([6, 4], count: 2, phase: 0)
        zone.stroke()

        let iconSize = Metrics.icon?.size ?? .zero
        let titleSize = Metrics.title.size()
        let detailSize = Metrics.detail.size()
        let height = iconSize.height + Metrics.iconSpacing + titleSize.height + Metrics.lineSpacing + detailSize.height
        // 뒤집히지 않은 뷰라 위에서부터 y를 줄여 가며 놓는다 (창 내용 뷰가 뒤집혀 있으면 debug/snapshot 결과가 뒤집힌다)
        var top = bounds.midY + height / 2
        top -= iconSize.height
        Metrics.icon?.draw(in: NSRect(x: bounds.midX - iconSize.width / 2, y: top, width: iconSize.width, height: iconSize.height))
        top -= Metrics.iconSpacing + titleSize.height
        Metrics.title.draw(at: NSPoint(x: bounds.midX - titleSize.width / 2, y: top))
        top -= Metrics.lineSpacing + detailSize.height
        Metrics.detail.draw(at: NSPoint(x: bounds.midX - detailSize.width / 2, y: top))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    /// 클립보드 이미지로 채운다. 빈 캔버스는 붙여넣기가 목적이라 메뉴를 끄는 대신 이미지가 없다고 알린다
    @objc func paste(_ sender: Any?) {
        guard let loaded = ImageLoader.load(from: .general) else {
            ToastPanel.show("클립보드에 이미지가 없습니다", systemImage: "exclamationmark.triangle.fill", on: window?.screen)
            return
        }
        onImages?([loaded])
    }

    // MARK: - 끌어다 놓기

    /// 다른 앱에서 끌어온 이미지 파일·이미지 데이터만 받는다
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = sender.draggingSource == nil && ImageLoader.canLoad(from: sender.draggingPasteboard)
        return isDropTarget ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    /// 이미지 파일은 모두 읽고, 파일이 없으면 이미지 데이터 하나를 읽는다. 창을 바꾸는 일은 드래그가 끝난 뒤로 미룬다
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard sender.draggingSource == nil else { return false }
        let pasteboard = sender.draggingPasteboard
        let urls = ImageLoader.imageFileURLs(from: pasteboard)
        let images = urls.isEmpty ? [ImageLoader.load(from: pasteboard)].compactMap { $0 } : urls.compactMap(ImageLoader.load(url:))
        guard !images.isEmpty else {
            ToastPanel.show("이미지를 열 수 없습니다", systemImage: "xmark.octagon.fill", on: window?.screen)
            return false
        }
        Task { [weak self] in self?.onImages?(images) }
        return true
    }
}
