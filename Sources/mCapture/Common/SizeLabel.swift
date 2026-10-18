import AppKit

/// 선택 영역·측정선 옆에 표시하는 "W × H" 라벨 (논리 픽셀)
@MainActor
enum SizeLabel {
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

    /// 이미지 픽셀 크기를 논리 픽셀 문자열로 만든다. 소수점이 있으면 한 자리까지
    static func text(pixelSize: CGSize, scale: CGFloat) -> String {
        "\(format(pixelSize.width / scale)) × \(format(pixelSize.height / scale))"
    }

    static func format(_ value: CGFloat) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// 선택 영역 아래에 두고, 공간이 없으면 안쪽 위에 둔다
    static func frame(text: String, near rect: CGRect, in bounds: CGRect) -> NSRect {
        let labelSize = size(of: text)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + labelSize.height > bounds.maxY {
            origin = NSPoint(x: rect.minX + 6, y: rect.minY + 6)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - labelSize.width)
        return NSRect(origin: origin, size: labelSize)
    }

    /// 점(커서·측정 끝점) 오른쪽 아래에 두고, 가장자리면 반대편으로 옮긴다 (픽셀 자)
    static func frame(text: String, beside point: CGPoint, in bounds: CGRect) -> NSRect {
        let labelSize = size(of: text)
        let offset: CGFloat = 14
        var origin = NSPoint(x: point.x + offset, y: point.y + offset)
        if origin.x + labelSize.width > bounds.maxX { origin.x = point.x - offset - labelSize.width }
        if origin.y + labelSize.height > bounds.maxY { origin.y = point.y - offset - labelSize.height }
        return NSRect(origin: origin, size: labelSize)
    }

    // 글자 둘레 여백을 더한 라벨 크기
    private static func size(of text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: size.width + 12, height: size.height + 6)
    }

    /// 뒤집힌(왼쪽 위 원점) 뷰에서 그린다
    static func draw(text: String, in frame: NSRect) {
        NSColor(white: 0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: frame.minX + 6, y: frame.minY + 3), withAttributes: attributes)
    }
}
