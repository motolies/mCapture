import AppKit
import MCaptureCore
import SwiftUI

/// 캡처 한 건을 편집하는 창
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((EditorWindowController) -> Void)?
    /// 캔버스에 이미지 파일을 끌어다 놓았을 때 (새 에디터로 연다)
    var onOpenFiles: (([URL]) -> Void)?
    /// 화면에 고정을 고르면 문서를 넘기고 에디터는 닫힌다
    var onPin: ((CaptureDocument, NSScreen?) -> Void)?

    private let canvas: CanvasView
    private let state: EditorState
    private static let toolbarHeight: CGFloat = 40

    init(document: CaptureDocument, preferences: Preferences, exporter: Exporter, screen: NSScreen?) {
        state = EditorState(
            color: preferences.annotationColor,
            size: preferences.annotationSize,
            textFont: preferences.annotationTextFont,
            textBackground: preferences.annotationTextBackground,
            redactMode: preferences.annotationRedactMode
        )
        canvas = CanvasView(document: document, state: state, preferences: preferences, exporter: exporter)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 560, height: 320)

        let toolbar = NSHostingView(rootView: EditorToolbar(state: state))
        let root = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvas)
        root.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root

        super.init(window: window)
        window.delegate = self
        canvas.onRequestClose = { [weak self] in self?.close() }
        canvas.onDocumentChange = { [weak self] in self?.updateTitle() }
        canvas.onOpenFiles = { [weak self] urls in self?.onOpenFiles?(urls) }
        canvas.onRequestPin = { [weak self] document in
            guard let self else { return }
            onPin?(document, self.window?.screen)
            close()
        }
        place(window, for: document, on: screen)
        updateTitle()
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

    func documentSaved(at url: URL) {
        canvas.documentSaved(at: url)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    // 논리 크기 100%로 보이게 하되 화면의 90%를 넘지 않게 캡처한 화면 가운데에 둔다
    private func place(_ window: NSWindow, for document: CaptureDocument, on screen: NSScreen?) {
        guard let area = (screen ?? NSScreen.underMouse ?? NSScreen.main)?.visibleFrame else { return }
        let logical = CGSize(width: document.visibleRect.width / document.scale, height: document.visibleRect.height / document.scale)
        let content = NSSize(
            width: min(max(logical.width + 48, window.minSize.width), area.width * 0.9),
            height: min(max(logical.height + 48 + Self.toolbarHeight, window.minSize.height), area.height * 0.9)
        )
        window.setContentSize(content)
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
    }

    private func updateTitle() {
        let rect = canvas.document.visibleRect
        window?.title = "mCapture — \(SizeLabel.text(pixelSize: rect.size, scale: canvas.document.scale))"
    }
}
