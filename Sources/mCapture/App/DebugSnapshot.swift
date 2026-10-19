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

    /// 앞쪽 에디터(또는 빈 캔버스)에서 ⌘V와 같은 붙여넣기를 실행한다 (mcapture://debug/paste)
    static func paste() {
        frontEditor?.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: nil)
    }

    /// 앞쪽 에디터를 화면에 고정한다 (mcapture://debug/pin)
    static func pin() {
        frontCanvas?.pinToScreen(nil)
    }

    /// 앞쪽 에디터에서 측정 도구를 이미지 픽셀 위치에 대 본다 (mcapture://debug/inspect?tool=colorPicker|ruler&x=&y=[&x2=&y2=])
    static func inspect(tool: EditorState.Tool, point: CGPoint, end: CGPoint?) {
        frontCanvas?.debugInspect(tool: tool, at: point, measureTo: end)
    }

    private static var frontCanvas: CanvasView? {
        frontEditor?.contentView?.subviews.first { $0 is CanvasView } as? CanvasView
    }

    /// 앞쪽 에디터 또는 빈 캔버스 창
    private static var frontEditor: NSWindow? {
        NSApp.orderedWindows.first {
            $0.isVisible && ($0.windowController is EditorWindowController || $0.windowController is BlankCanvasWindowController)
        }
    }

    static func write(to url: URL) {
        // 파일 찾기 패널이 키 창이면 그 창, 아니면 에디터, 키 창, 보이는 창(핀 등) 순
        let window = (NSApp.keyWindow as? FindFilePanel) ?? frontEditor ?? NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible }
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
