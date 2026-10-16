import CoreGraphics
import Foundation

/// 주석 색상 (sRGB, 각 성분 0~1)
public struct RGBAColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB" 또는 "#RRGGBBAA" 문자열을 색상으로 변환한다. 형식이 틀리면 nil
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }

    /// "#RRGGBB" 형식 문자열 (알파가 1이 아니면 "#RRGGBBAA")
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 1 ? base + String(format: "%02X", byte(alpha)) : base
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// 상대 휘도가 높아 밝은 색인지 판단한다 (텍스트 외곽선 색 결정용)
    public var isLight: Bool {
        0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6
    }

    /// 툴바에 노출하는 기본 8색
    public static let palette: [RGBAColor] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#000000", "#FFFFFF",
    ].compactMap { RGBAColor(hex: $0) }
}

/// 주석 크기 (1~20). 값이 곧 선 두께(논리 포인트)이고 글자·카운터·가리기 강도도 이 값에 비례한다
/// 실제 픽셀 값은 논리 포인트 × 이미지 배율. 예전 S/M/L은 2/4/7이고 아래 공식이 그 값을 그대로 만든다
public struct AnnotationSize: Hashable, Sendable {
    public static let range = 1...20
    public static let small = AnnotationSize(2)
    public static let medium = AnnotationSize(4)
    public static let large = AnnotationSize(7)

    public let value: Int

    /// 범위를 벗어난 값은 가까운 끝값으로 맞춘다
    public init(_ value: Int) {
        self.value = min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }

    private var points: CGFloat { CGFloat(value) }

    /// 선 두께 (논리 포인트)
    public var lineWidth: CGFloat { points }

    /// 텍스트 크기 (논리 포인트)
    public var fontSize: CGFloat { 8 + 4 * points }

    /// 카운터 원 지름 (논리 포인트)
    public var counterDiameter: CGFloat { 14 + 4 * points }

    /// 픽셀화 블록 한 변 (논리 포인트). 작게 해도 글자가 읽히지 않도록 6 아래로 내리지 않는다
    public var pixelateBlock: CGFloat { max(6, 2 + 2 * points) }

    /// 블러 반경 (논리 포인트). 작게 해도 글자가 읽히지 않도록 4 아래로 내리지 않는다
    public var blurRadius: CGFloat { max(4, 2 * points) }
}

/// 텍스트 주석 글꼴. 한글처럼 글꼴에 없는 글자는 CoreText가 시스템 글꼴로 대신 그린다
public enum TextFont: String, CaseIterable, Sendable {
    case system
    case rounded
    case serif
    case mono
    case handwriting

    /// macOS 기본 설치 글꼴의 PostScript 이름. system은 시스템 UI 글꼴을 쓴다
    public var postScriptName: String? {
        switch self {
        case .system: nil
        case .rounded: "ArialRoundedMTBold"
        case .serif: "Georgia-Bold"
        case .mono: "Menlo-Bold"
        case .handwriting: "Noteworthy-Bold"
        }
    }
}

public struct AnnotationStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var size: AnnotationSize
    /// 텍스트 글꼴
    public var textFont: TextFont
    /// 텍스트를 주석 색 둥근 상자 위에 대비색으로 쓴다
    public var textBackground: Bool
    /// 텍스트 모서리 핸들로 조절한 배율. size 단계의 글자 크기에 곱한다
    public var fontScale: CGFloat

    public init(color: RGBAColor, size: AnnotationSize, textFont: TextFont = .system, textBackground: Bool = false, fontScale: CGFloat = 1) {
        self.color = color
        self.size = size
        self.textFont = textFont
        self.textBackground = textBackground
        self.fontScale = fontScale
    }
}

/// 가리기 방식. 원본 픽셀을 읽어 그리고, 강도는 주석 크기로 정한다
public enum RedactMode: String, CaseIterable, Sendable {
    case pixelate
    case blur
}

/// 주석 도형. 모든 좌표는 이미지 픽셀 좌표 (왼쪽 위 원점)
public enum AnnotationShape: Equatable, Sendable {
    case rectangle(CGRect)
    /// rect에 내접하는 타원 테두리
    case oval(CGRect)
    case line(start: CGPoint, end: CGPoint)
    case arrow(start: CGPoint, end: CGPoint)
    /// 반투명하게 덮어 강조한다
    case highlighter(CGRect)
    /// 번호가 쓰인 원. center는 원의 가운데
    case counter(center: CGPoint, number: Int)
    /// origin은 텍스트 상자의 왼쪽 위
    case text(origin: CGPoint, string: String)
    /// 붙여넣은 이미지. rect 크기로 늘려 그린다
    case image(CGRect, SendableImage)
    /// 원본의 일부를 가린다
    case redact(CGRect, RedactMode)
}

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    public var isText: Bool {
        if case .text = shape { return true }
        return false
    }

    /// 원본을 대신하거나 원본에 붙는 레이어(붙여넣은 이미지, 가리기, 형광펜). 나머지 주석은 항상 이 위에 그린다
    public var isBaseLayer: Bool {
        switch shape {
        case .image, .redact, .highlighter: true
        case .rectangle, .oval, .line, .arrow, .text, .counter: false
        }
    }
}
