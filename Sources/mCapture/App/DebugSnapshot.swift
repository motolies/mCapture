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

    /// 뷰 하나의 레이어를 PNG에 쓴다 (팝오버처럼 창 전체가 필요 없을 때)
    /// 팝오버 내용은 바탕이 투명해 어두운 모드의 흰 글자가 PNG에서 안 보이므로 그 모양의 창 배경색을 깔고,
    /// SwiftUI 호스팅 뷰(`isFlipped`)는 위아래를 바로잡아 그린다
    static func render(view: NSView, to url: URL) {
        guard let layer = view.layer else {
            Log.app.error("스냅샷: 뷰에 레이어 없음")
            return
        }
        var background = NSColor.windowBackgroundColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? background
        }
        render(layer: layer, size: view.bounds.size, scale: view.window?.backingScaleFactor ?? 2,
               flipped: view.isFlipped, background: background.cgColor, to: url)
    }

    // 레이어를 비트맵에 그려 PNG로 쓴다. background가 있으면 먼저 채우고, flipped면 위아래를 뒤집어 그린다
    private static func render(layer: CALayer, size: CGSize, scale: CGFloat, flipped: Bool, background: CGColor?, to url: URL) {
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
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        if flipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        guard let image = ctx.makeImage(), let png = ImageEncoder.pngData(image, scale: scale) else { return }
        try? png.write(to: url)
        Log.app.info("스냅샷: \(url.path, privacy: .public)")
    }

    static func write(to url: URL) {
        // 파일 찾기 패널이 보이면 그 창, 아니면 에디터, 키 창, 보이는 창(핀 등) 순
        // (URL로 연 패널은 협력적 활성화 때문에 키 창이 못 될 때가 있어 키 창 여부를 따지지 않는다)
        let finder = NSApp.windows.first { $0 is FindFilePanel && $0.isVisible }
        let window = finder ?? frontEditor ?? NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible }
        guard let view = window?.contentView, let layer = view.layer else {
            Log.app.error("스냅샷: 대상 창 없음")
            return
        }
        if let finder { Log.app.info("스냅샷: 파일 찾기 창 (키 창 \(finder.isKeyWindow))") }
        render(layer: layer, size: view.bounds.size, scale: window?.backingScaleFactor ?? 2, flipped: false, background: nil, to: url)
    }
}
#endif
