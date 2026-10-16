#if DEBUG
import AppKit
import MCaptureCore

/// 개발용: 앞쪽 창의 레이어 트리를 PNG로 렌더링한다 (화면 기록 권한 없이 UI 확인)
/// mcapture://debug/snapshot?path=/abs/out.png
@MainActor
enum DebugSnapshot {
    /// 앞쪽 에디터에 샘플 주석을 넣는다 (mcapture://debug/samples)
    static func addSamples() {
        frontCanvas?.debugAddSamples()
    }

    /// 앞쪽 에디터에서 ⌘V와 같은 붙여넣기를 실행한다 (mcapture://debug/paste)
    static func paste() {
        frontCanvas?.paste(nil)
    }

    /// 앞쪽 에디터를 화면에 고정한다 (mcapture://debug/pin)
    static func pin() {
        frontCanvas?.pinToScreen(nil)
    }

    private static var frontCanvas: CanvasView? {
        frontEditor?.contentView?.subviews.first { $0 is CanvasView } as? CanvasView
    }

    private static var frontEditor: NSWindow? {
        NSApp.orderedWindows.first { $0.isVisible && $0.windowController is EditorWindowController }
    }

    static func write(to url: URL) {
        // 에디터가 없으면 키 창, 그것도 없으면 보이는 창(핀 등)
        let window = frontEditor ?? NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible }
        guard let view = window?.contentView, let layer = view.layer else {
            Log.app.error("스냅샷: 대상 창 없음")
            return
        }
        let scale = window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage(), let png = ImageEncoder.pngData(image, scale: scale) else { return }
        try? png.write(to: url)
        Log.app.info("스냅샷: \(url.path, privacy: .public)")
    }
}
#endif
