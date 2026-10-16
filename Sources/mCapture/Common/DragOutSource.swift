import AppKit
import MCaptureCore
import SwiftUI

/// 끌어놓기로 내보낼 이미지
struct DragPayload {
    let png: Data
    let fileName: String
    /// 끄는 동안 커서에 붙는 미리보기
    let preview: NSImage
}

/// 끌면 이미지를 다른 앱으로 내보내는 손잡이. 받는 앱에 따라 쓸 수 있도록 파일 URL과 PNG 데이터를 함께 준다
final class DragOutView: NSView, NSDraggingSource {
    var payload: (() -> DragPayload?)?
    /// 마우스를 올리면 호출한다. 큰 이미지는 인코딩이 오래 걸려 드래그 전에 미리 준비하게 한다
    var onHover: (() -> Void)?

    private let iconView = NSImageView()
    private var downPoint: CGPoint?
    private static let dragThreshold: CGFloat = 3
    private static let usageHint = "손잡이를 끌어 Finder·메신저·브라우저에 놓으면 이미지 파일로 들어갑니다"

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "끌어서 내보내기")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.contentTintColor = .labelColor
        iconView.autoresizingMask = [.width, .height]
        iconView.frame = bounds
        addSubview(iconView)
        toolTip = "끌어서 다른 앱에 놓기 (클릭하면 사용법)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let start = downPoint, hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
        downPoint = nil
        beginDrag(with: event, at: point)
    }

    /// 끌지 않고 클릭만 했으면 사용법을 알린다
    override func mouseUp(with event: NSEvent) {
        if downPoint != nil {
            ToastPanel.show(Self.usageHint, systemImage: "hand.draw", tint: .secondary, duration: .seconds(3), on: window?.screen)
        }
        downPoint = nil
    }

    // 결과 이미지를 임시 파일로 쓰고 드래그를 시작한다
    private func beginDrag(with event: NSEvent, at point: CGPoint) {
        guard let payload = payload?(), let url = try? DragOutFiles.write(payload.png, named: payload.fileName) else {
            NSSound.beep()
            return
        }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(payload.png, forType: .png)

        let dragging = NSDraggingItem(pasteboardWriter: item)
        let size = payload.preview.size
        dragging.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), contents: payload.preview)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    /// 앱 안(에디터 캔버스는 파일 드롭을 새 에디터로 연다)에는 놓지 않는다
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}

/// SwiftUI 툴바에 넣는 끌어놓기 손잡이
struct DragOutButton: NSViewRepresentable {
    let prepare: () -> Void
    let payload: () -> DragPayload?

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.onHover = prepare
        view.payload = payload
    }
}

/// 끌어놓기용 임시 파일. 받는 앱이 놓은 뒤에 파일을 읽을 수 있어 바로 지우지 않고 앱을 시작할 때 비운다
enum DragOutFiles {
    static var folder: URL {
        // 사용 중인 앱과 개발 빌드가 서로의 임시 파일을 지우지 않도록 변형마다 폴더를 나눈다
        FileManager.default.temporaryDirectory.appendingPathComponent(AppVariant.current.dragFolderName, isDirectory: true)
    }

    /// 드래그마다 새 하위 폴더에 원래 파일명으로 쓴다 (앞 드래그 파일을 읽는 중인 앱과 겹치지 않게)
    static func write(_ png: Data, named name: String) throws -> URL {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        return url
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
