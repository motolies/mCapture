import CoreGraphics
import CoreText
import Foundation

/// 텍스트 주석의 줄 단위 배치 정보
public struct TextLayout {
    public let lines: [CTLine]
    public let ascent: CGFloat
    public let lineHeight: CGFloat
    public let size: CGSize
}

/// 주석을 그린다. 컨텍스트는 이미지 픽셀 좌표, y 아래 방향이라고 가정한다
public enum AnnotationRenderer {
    /// 이미지 픽셀 단위 선 두께
    public static func lineWidth(_ style: AnnotationStyle, pointScale: CGFloat) -> CGFloat {
        style.size.lineWidth * pointScale
    }

    /// 이미지 픽셀 단위 글자 크기 (크기 단계 × 핸들 배율)
    public static func fontSize(_ style: AnnotationStyle, pointScale: CGFloat) -> CGFloat {
        style.size.fontSize * style.fontScale * pointScale
    }

    /// 주석 하나를 그린다. 픽셀화·블러 가리기는 원본을 읽는 redactions가 있어야 그린다
    public static func draw(_ annotation: Annotation, in ctx: CGContext, pointScale: CGFloat, redactions: RedactionCache? = nil) {
        let style = annotation.style
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch annotation.shape {
        case .rectangle(let rect):
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(lineWidth(style, pointScale: pointScale))
            ctx.setLineJoin(.round)
            ctx.stroke(rect)

        case .oval(let rect):
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(lineWidth(style, pointScale: pointScale))
            ctx.strokeEllipse(in: rect)

        case .line(let start, let end):
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setLineWidth(lineWidth(style, pointScale: pointScale))
            ctx.setLineCap(.round)
            ctx.strokeLineSegments(between: [start, end])

        case .highlighter(let rect):
            // 캔버스는 원본 위 별도 레이어에 그려 블렌드 모드가 원본과 섞이지 않으므로 알파로만 겹친다
            ctx.setFillColor(style.color.cgColor.copy(alpha: highlighterAlpha) ?? style.color.cgColor)
            ctx.fill(rect)

        case .counter(let center, let number):
            drawCounter(number, at: center, style: style, pointScale: pointScale, in: ctx)

        case .arrow(let start, let end):
            ctx.setFillColor(style.color.cgColor)
            ctx.addPath(arrowPath(start: start, end: end, lineWidth: lineWidth(style, pointScale: pointScale)))
            ctx.fillPath()

        case .text(let origin, let string):
            drawTextBackground(annotation, pointScale: pointScale, in: ctx)
            drawText(string, at: origin, style: style, pointScale: pointScale, in: ctx)

        case .image(let rect, let image):
            ctx.interpolationQuality = .high
            DocumentRenderer.drawImage(image.cgImage, in: rect, ctx: ctx)

        case .redact(let rect, let mode):
            redactions?.draw(rect, mode: mode, size: style.size, pointScale: pointScale, in: ctx)
        }
    }

    /// 형광펜 불투명도
    public static let highlighterAlpha: CGFloat = 0.4

    /// 카운터 원 반지름 (이미지 픽셀)
    public static func counterRadius(_ style: AnnotationStyle, pointScale: CGFloat) -> CGFloat {
        style.size.counterDiameter * pointScale / 2
    }

    // 주석 색 원 위에 대비색(검정·흰색) 번호를 가운데 맞춰 쓴다. 두 자리부터는 글자를 줄인다
    private static func drawCounter(_ number: Int, at center: CGPoint, style: AnnotationStyle, pointScale: CGFloat, in ctx: CGContext) {
        let radius = counterRadius(style, pointScale: pointScale)
        ctx.setFillColor(style.color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        let text = String(number)
        let ctFont = font(.system, size: radius * (text.count > 1 ? 0.95 : 1.15))
        let color = style.color.isLight ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // 숫자는 대문자 높이만큼 기준선 위로 올라가므로 그 절반만큼 내려 세로 가운데에 맞춘다
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y + CTFontGetCapHeight(ctFont) / 2)
        CTLineDraw(line, ctx)
    }

    /// 꼬리는 가늘고 머리 쪽으로 굵어지는 화살표 외곽선
    public static func arrowPath(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= 1 else { return path }

        let ux = dx / length
        let uy = dy / length
        // 진행 방향에 수직인 단위 벡터
        let nx = -uy
        let ny = ux

        let headLength = min(max(lineWidth * 4.5, 8), length * 0.6)
        let headHalfWidth = max(headLength * 0.55, lineWidth * 1.6)
        let neckHalfWidth = lineWidth * 0.6
        let tailHalfWidth = lineWidth * 0.25

        let neck = CGPoint(x: end.x - ux * headLength * 0.85, y: end.y - uy * headLength * 0.85)
        let wingBase = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        func offset(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + nx * d, y: p.y + ny * d) }

        path.move(to: offset(start, tailHalfWidth))
        path.addLine(to: offset(neck, neckHalfWidth))
        path.addLine(to: offset(wingBase, headHalfWidth))
        path.addLine(to: end)
        path.addLine(to: offset(wingBase, -headHalfWidth))
        path.addLine(to: offset(neck, -neckHalfWidth))
        path.addLine(to: offset(start, -tailHalfWidth))
        path.closeSubpath()
        return path
    }

    /// 텍스트 글꼴. 지정한 글꼴이 설치돼 있지 않으면 굵은 시스템 글꼴을 쓴다
    public static func font(_ textFont: TextFont = .system, size: CGFloat) -> CTFont {
        if let name = textFont.postScriptName {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            // 없는 이름이면 CoreText가 다른 글꼴로 대신 만들어 주므로 이름으로 확인한다
            if CTFontCopyPostScriptName(font) as String == name { return font }
        }
        return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// 줄바꿈 기준으로 텍스트를 배치한다. 빈 문자열도 한 줄 높이를 가진다
    public static func layout(_ string: String, font textFont: TextFont = .system, fontSize: CGFloat, color: CGColor? = nil) -> TextLayout {
        let ctFont = font(textFont, size: fontSize)
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        let ascent = CTFontGetAscent(ctFont)
        let lineHeight = (ascent + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)).rounded(.up)

        let lines = string.components(separatedBy: "\n").map { line in
            CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
        }
        let width = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return TextLayout(
            lines: lines,
            ascent: ascent,
            lineHeight: lineHeight,
            size: CGSize(width: width.rounded(.up), height: lineHeight * CGFloat(max(lines.count, 1)))
        )
    }

    /// 텍스트 상자 크기 (이미지 픽셀)
    public static func textSize(_ string: String, style: AnnotationStyle, pointScale: CGFloat) -> CGSize {
        layout(string, font: style.textFont, fontSize: fontSize(style, pointScale: pointScale)).size
    }

    /// 글자 색. 배경이 있으면 배경(주석 색)과 대비되는 검정·흰색
    public static func textColor(_ style: AnnotationStyle) -> CGColor {
        guard style.textBackground else { return style.color.cgColor }
        return style.color.isLight ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    /// 텍스트 상자 바깥 여백. 배경 상자는 넉넉하게, 외곽선만 있으면 외곽선 두께만큼
    public static func textInsets(_ style: AnnotationStyle, pointScale: CGFloat) -> CGSize {
        let size = fontSize(style, pointScale: pointScale)
        return style.textBackground ? CGSize(width: size * 0.4, height: size * 0.2) : CGSize(width: size * 0.1, height: size * 0.1)
    }

    /// 주석이 그려지는 영역 (선 두께 포함). 선택 표시와 다시 그리기 범위 계산에 사용
    public static func bounds(of annotation: Annotation, pointScale: CGFloat) -> CGRect {
        let width = lineWidth(annotation.style, pointScale: pointScale)
        switch annotation.shape {
        case .rectangle(let rect), .oval(let rect):
            return rect.insetBy(dx: -width, dy: -width)
        case .line(let start, let end):
            return RectMath.rect(from: start, to: end).insetBy(dx: -width, dy: -width)
        case .highlighter(let rect):
            return rect
        case .counter(let center, _):
            let radius = counterRadius(annotation.style, pointScale: pointScale)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case .arrow(let start, let end):
            let headPad = max(width * 4.5, 8)
            return RectMath.rect(from: start, to: end).insetBy(dx: -headPad, dy: -headPad)
        case .text(let origin, let string):
            let size = textSize(string, style: annotation.style, pointScale: pointScale)
            let insets = textInsets(annotation.style, pointScale: pointScale)
            return CGRect(origin: origin, size: size).insetBy(dx: -insets.width, dy: -insets.height)
        case .image(let rect, _), .redact(let rect, _):
            return rect
        }
    }

    /// 배경을 켠 텍스트의 둥근 상자를 그린다. 텍스트 편집 중에는 캔버스가 이것만 그리고 글자는 편집 뷰가 그린다
    public static func drawTextBackground(_ annotation: Annotation, pointScale: CGFloat, in ctx: CGContext) {
        guard annotation.style.textBackground, annotation.isText else { return }
        let box = bounds(of: annotation, pointScale: pointScale)
        let radius = min(fontSize(annotation.style, pointScale: pointScale) * 0.3, box.height / 2)
        ctx.saveGState()
        ctx.setFillColor(annotation.style.color.cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 배경이 없으면 대비되는 외곽선을 먼저 그리고 그 위에 글자를 채운다
    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, pointScale: CGFloat, in ctx: CGContext) {
        let size = fontSize(style, pointScale: pointScale)
        let layout = layout(string, font: style.textFont, fontSize: size, color: textColor(style))
        let outlineColor = style.color.isLight
            ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.75)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)

        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(outlineColor)
        ctx.setLineWidth(size * 0.16)

        for (index, line) in layout.lines.enumerated() {
            let baseline = CGPoint(x: origin.x, y: origin.y + layout.ascent + layout.lineHeight * CGFloat(index))
            if !style.textBackground {
                ctx.textPosition = baseline
                ctx.setTextDrawingMode(.stroke)
                CTLineDraw(line, ctx)
            }
            ctx.textPosition = baseline
            ctx.setTextDrawingMode(.fill)
            CTLineDraw(line, ctx)
        }
    }
}
