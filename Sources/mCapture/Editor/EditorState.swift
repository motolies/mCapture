import Combine
import MCaptureCore

/// 툴바와 캔버스가 공유하는 에디터 상태
@MainActor
final class EditorState: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case select
        case rectangle
        case oval
        case line
        case arrow
        case highlighter
        case text
        case counter
        case redact
        case colorPicker
        case ruler

        var id: String { rawValue }

        var title: String {
            switch self {
            case .select: "선택"
            case .rectangle: "사각형"
            case .oval: "타원"
            case .line: "선"
            case .arrow: "화살표"
            case .highlighter: "형광펜"
            case .text: "텍스트"
            case .counter: "카운터"
            case .redact: "가리기"
            case .colorPicker: "컬러 피커"
            case .ruler: "픽셀 자"
            }
        }

        var symbol: String {
            switch self {
            case .select: "crop"
            case .rectangle: "rectangle"
            case .oval: "circle"
            case .line: "line.diagonal"
            case .arrow: "arrow.up.right"
            case .highlighter: "highlighter"
            case .text: "textformat"
            case .counter: "1.circle"
            case .redact: "checkerboard.rectangle"
            case .colorPicker: "eyedropper"
            case .ruler: "ruler"
            }
        }

        var shortcut: String {
            switch self {
            case .select: "V"
            case .rectangle: "R"
            case .oval: "O"
            case .line: "L"
            case .arrow: "A"
            case .highlighter: "H"
            case .text: "T"
            case .counter: "N"
            case .redact: "B"
            case .colorPicker: "I"
            case .ruler: "M"
            }
        }

        /// 툴바 툴팁에 덧붙이는 사용법
        var usage: String? {
            switch self {
            case .colorPicker: "클릭 HEX, ⇧클릭 RGB 복사"
            case .ruler: "올리면 간격, 끌면 거리 (⇧ 45°)"
            case .select, .rectangle, .oval, .line, .arrow, .highlighter, .text, .counter, .redact: nil
            }
        }

        /// 주석을 만들거나 고르지 않고 원본 픽셀을 살펴보는 도구. 툴바에서 구분선 뒤에 둔다
        var isInspection: Bool {
            switch self {
            case .colorPicker, .ruler: true
            case .select, .rectangle, .oval, .line, .arrow, .highlighter, .text, .counter, .redact: false
            }
        }

        static var editingTools: [Tool] { allCases.filter { !$0.isInspection } }
        static var inspectionTools: [Tool] { allCases.filter(\.isInspection) }

        /// 한글 입력 상태에서도 동작하도록 문자 대신 ANSI 키 코드로 찾는다
        init?(keyCode: UInt16) {
            switch keyCode {
            case 9: self = .select
            case 15: self = .rectangle
            case 31: self = .oval
            case 37: self = .line
            case 0: self = .arrow
            case 4: self = .highlighter
            case 17: self = .text
            case 45: self = .counter
            case 11: self = .redact
            case 34: self = .colorPicker
            case 46: self = .ruler
            default: return nil
            }
        }
    }

    /// 툴바 도구 옵션 칸에 보일 옵션
    enum ToolOptions {
        case none
        /// 텍스트 도구이거나 텍스트 주석을 고르거나 편집 중: 글꼴·배경
        case text
        /// 가리기 도구이거나 가리기 주석을 고름: 방식
        case redact
    }

    @Published var tool: Tool = .select
    @Published var color: RGBAColor
    @Published var size: AnnotationSize
    @Published var textFont: TextFont
    @Published var textBackground: Bool
    /// 가리기 도구로 새로 만들 방식
    @Published var redactMode: RedactMode
    @Published var toolOptions: ToolOptions = .none
    /// 좁은 창에서 접힌 색상 팔레트 팝오버
    @Published var showsColorPopover = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var sizeText = ""
    @Published var zoomText = ""

    /// 툴바 동작을 전달할 캔버스
    weak var canvas: CanvasView?

    init(color: RGBAColor, size: AnnotationSize, textFont: TextFont, textBackground: Bool, redactMode: RedactMode) {
        self.color = color
        self.size = size
        self.textFont = textFont
        self.textBackground = textBackground
        self.redactMode = redactMode
    }

    /// 새로 만드는 주석의 스타일
    var style: AnnotationStyle {
        AnnotationStyle(color: color, size: size, textFont: textFont, textBackground: textBackground)
    }
}

extension RedactMode {
    var title: String {
        switch self {
        case .pixelate: "픽셀화"
        case .blur: "블러"
        }
    }

    var symbol: String {
        switch self {
        case .pixelate: "square.grid.3x3.fill"
        case .blur: "drop.halffull"
        }
    }
}

extension TextFont {
    /// 툴바 글꼴 메뉴에 보이는 이름
    var title: String {
        switch self {
        case .system: "시스템"
        case .rounded: "둥근 글꼴"
        case .serif: "세리프"
        case .mono: "고정폭"
        case .handwriting: "손글씨"
        }
    }
}
