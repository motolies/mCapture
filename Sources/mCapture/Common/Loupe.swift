import AppKit
import MCaptureCore

/// 커서 옆에 이미지 픽셀을 크게 보여 주는 확대경 (영역 선택 오버레이·에디터 컬러 피커 공용)
/// 가운데 칸이 읽는 픽셀이고, 아래 정보 줄에 좌표·색을 보인다. 뒤집힌(왼쪽 위 원점) 뷰에서 그린다
@MainActor
enum Loupe {
    private static let cells = 15
    private static let cell: CGFloat = 8
    private static let offset: CGFloat = 24
    private static let lineHeight: CGFloat = 14
    /// 정보 칸 위아래 여백 합. 한 줄이면 정보 칸 높이가 34pt
    private static let infoPadding: CGFloat = 20
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    /// 커서 오른쪽 아래에 두고, bounds 가장자리면 반대편으로 옮긴다
    /// 정보 줄 수만큼 길어지고, 글자가 픽셀 칸보다 넓으면 그만큼 넓어진다
    static func frame(at point: CGPoint, info: [String], in bounds: CGRect) -> NSRect {
        let side = CGFloat(cells) * cell
        let textWidth = info.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let size = NSSize(width: max(side, textWidth.rounded(.up) + 16), height: side + infoPadding + lineHeight * CGFloat(info.count))
        var origin = NSPoint(x: point.x + offset, y: point.y + offset)
        if origin.x + size.width > bounds.maxX { origin.x = point.x - offset - size.width }
        if origin.y + size.height > bounds.maxY { origin.y = point.y - offset - size.height }
        return NSRect(origin: origin, size: size)
    }

    /// center 픽셀(이미지 픽셀) 둘레 15×15칸을 frame 위쪽에, info를 아래쪽에 한 줄씩 가운데 맞춰 그린다
    /// readable 밖 칸(이미지 밖·크롭 밖)은 비워 둔다
    static func draw(_ ctx: CGContext, image: CGImage, center: CGPoint, readable: CGRect, info: [String], in frame: NSRect) {
        let half = cells / 2
        let side = CGFloat(cells) * cell
        let loupe = NSRect(x: frame.midX - side / 2, y: frame.minY, width: side, height: side)
        let source = CGRect(x: center.x - CGFloat(half), y: center.y - CGFloat(half), width: CGFloat(cells), height: CGFloat(cells))

        ctx.saveGState()
        let outline = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 0.92).setFill()
        outline.fill()
        outline.addClip()

        // 가장자리에서는 읽을 수 있는 부분만 제자리에 그린다
        if let visible = RectMath.clamp(source, to: readable), let pixels = image.cropping(to: visible) {
            let destination = CGRect(
                x: loupe.minX + (visible.minX - source.minX) * cell,
                y: loupe.minY + (visible.minY - source.minY) * cell,
                width: visible.width * cell,
                height: visible.height * cell
            )
            ctx.interpolationQuality = .none
            DocumentRenderer.drawImage(pixels, in: destination, ctx: ctx)
        }

        // 픽셀 격자와 가운데 픽셀 표시
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.25))
        ctx.setLineWidth(0.5)
        for index in 1..<cells {
            let offset = CGFloat(index) * cell
            ctx.strokeLineSegments(between: [CGPoint(x: loupe.minX + offset, y: loupe.minY), CGPoint(x: loupe.minX + offset, y: loupe.maxY),
                                             CGPoint(x: loupe.minX, y: loupe.minY + offset), CGPoint(x: loupe.maxX, y: loupe.minY + offset)])
        }
        let centerCell = CGRect(x: loupe.minX + CGFloat(half) * cell, y: loupe.minY + CGFloat(half) * cell, width: cell, height: cell)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.stroke(centerCell.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.stroke(centerCell)
        ctx.restoreGState()

        var lineTop = loupe.maxY + (frame.maxY - loupe.maxY - lineHeight * CGFloat(info.count)) / 2
        for line in info {
            let textSize = (line as NSString).size(withAttributes: attributes)
            (line as NSString).draw(
                at: NSPoint(x: frame.midX - textSize.width / 2, y: lineTop + (lineHeight - textSize.height) / 2),
                withAttributes: attributes
            )
            lineTop += lineHeight
        }
    }
}
