import Foundation
import MCaptureCore

/// 에디터에서 Esc로 창을 닫을 때 수행할 동작
enum EscAction: String, CaseIterable, Identifiable {
    case copy
    case save
    case copySave
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "클립보드에 복사"
        case .save: "파일로 저장"
        case .copySave: "복사하고 저장"
        case .none: "아무것도 안 함"
        }
    }
}

extension Notification.Name {
    /// 설정에서 단축키 녹화를 시작(object: true)하거나 끝냈을(false) 때
    /// 녹화 중에는 전역 단축키를 해제하고, 끝나면 저장된 설정으로 다시 등록한다
    static let mcaptureHotKeyRecording = Notification.Name("mcaptureHotKeyRecording")
}

/// UserDefaults 기반 설정. SwiftUI 설정 화면은 같은 키를 @AppStorage로 직접 쓴다
@MainActor
final class Preferences {
    static let shared = Preferences()

    enum Key {
        static let saveFolder = "saveFolder"
        static let fileNameTemplate = "fileNameTemplate"
        static let afterCaptureCopy = "afterCaptureCopy"
        static let afterCaptureSave = "afterCaptureSave"
        static let afterCaptureOpenEditor = "afterCaptureOpenEditor"
        static let escAction = "escAction"
        static let ocrJoinLines = "ocrJoinLines"
        static let windowShadow = "windowShadow"
        static let hotkeyArea = "hotkeyArea"
        static let hotkeyFullscreen = "hotkeyFullscreen"
        static let hotkeyWindow = "hotkeyWindow"
        static let hotkeyOcr = "hotkeyOcr"
        static let hotkeyColor = "hotkeyColor"
        static let annotationColor = "annotationColor"
        static let annotationSize = "annotationSize"
        static let annotationTextFont = "annotationTextFont"
        static let annotationTextBackground = "annotationTextBackground"
        static let annotationRedactMode = "annotationRedactMode"
    }

    /// 저장 폴더와 단축키 기본값은 실행 변형(사용 중인 앱 / 개발 빌드)마다 다르다
    enum Default {
        static var saveFolder: String { AppVariant.current.defaultSaveFolder }
        static var hotkeyArea: String { AppVariant.current.defaultHotkey(key: "4") }
        static var hotkeyFullscreen: String { AppVariant.current.defaultHotkey(key: "1") }
        static var hotkeyWindow: String { AppVariant.current.defaultHotkey(key: "3") }
        static var hotkeyOcr: String { AppVariant.current.defaultHotkey(key: "5") }
        static var hotkeyColor: String { AppVariant.current.defaultHotkey(key: "6") }
        static let annotationColor = "#FF3B30"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.saveFolder: Default.saveFolder,
            Key.fileNameTemplate: FileNaming.defaultTemplate,
            Key.afterCaptureCopy: true,
            Key.afterCaptureSave: true,
            Key.afterCaptureOpenEditor: true,
            Key.escAction: EscAction.copy.rawValue,
            Key.ocrJoinLines: false,
            Key.windowShadow: true,
            Key.hotkeyArea: Default.hotkeyArea,
            Key.hotkeyFullscreen: Default.hotkeyFullscreen,
            Key.hotkeyWindow: Default.hotkeyWindow,
            Key.hotkeyOcr: Default.hotkeyOcr,
            Key.hotkeyColor: Default.hotkeyColor,
            Key.annotationColor: Default.annotationColor,
            Key.annotationSize: AnnotationSize.medium.value,
            Key.annotationTextFont: TextFont.system.rawValue,
            Key.annotationTextBackground: false,
            Key.annotationRedactMode: RedactMode.pixelate.rawValue,
            // AppKit 툴팁이 뜨기까지 기다리는 시간(ms). 시스템 기본(약 1초)보다 빨리 보이게 한다
            "NSInitialToolTipDelay": 300,
        ])
    }

    /// 저장 폴더 (~ 경로 확장)
    var saveFolder: URL {
        let path = defaults.string(forKey: Key.saveFolder) ?? Default.saveFolder
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// 저장 파일 이름 형식 ({date}·{time}·{app} 등 토큰)
    var fileNameTemplate: String {
        defaults.string(forKey: Key.fileNameTemplate) ?? FileNaming.defaultTemplate
    }

    var afterCaptureCopy: Bool { defaults.bool(forKey: Key.afterCaptureCopy) }
    var afterCaptureSave: Bool { defaults.bool(forKey: Key.afterCaptureSave) }
    var afterCaptureOpenEditor: Bool { defaults.bool(forKey: Key.afterCaptureOpenEditor) }

    /// 텍스트 인식 결과의 줄바꿈을 공백으로 바꾼다
    var ocrJoinLines: Bool { defaults.bool(forKey: Key.ocrJoinLines) }

    /// 창 캡처에 창 그림자를 포함한다 (배경은 투명)
    var windowShadow: Bool { defaults.bool(forKey: Key.windowShadow) }

    var escAction: EscAction {
        EscAction(rawValue: defaults.string(forKey: Key.escAction) ?? "") ?? .copy
    }

    /// 동작별 단축키. 저장된 문자열이 잘못됐으면 기본 단축키를 쓴다
    func hotkey(for action: HotKeyCenter.Action) -> HotKeySpec {
        let (key, fallback) = Self.hotkeyKeys(for: action)
        return HotKeySpec(string: defaults.string(forKey: key) ?? "") ?? HotKeySpec(string: fallback)!
    }

    func setHotkey(_ spec: HotKeySpec, for action: HotKeyCenter.Action) {
        defaults.set(spec.stringValue, forKey: Self.hotkeyKeys(for: action).key)
    }

    // 동작별 UserDefaults 키와 기본값
    private static func hotkeyKeys(for action: HotKeyCenter.Action) -> (key: String, fallback: String) {
        switch action {
        case .area: (Key.hotkeyArea, Default.hotkeyArea)
        case .fullscreen: (Key.hotkeyFullscreen, Default.hotkeyFullscreen)
        case .window: (Key.hotkeyWindow, Default.hotkeyWindow)
        case .ocr: (Key.hotkeyOcr, Default.hotkeyOcr)
        case .color: (Key.hotkeyColor, Default.hotkeyColor)
        }
    }

    var annotationColor: RGBAColor {
        get { RGBAColor(hex: defaults.string(forKey: Key.annotationColor) ?? "") ?? RGBAColor(hex: Default.annotationColor)! }
        set { defaults.set(newValue.hex, forKey: Key.annotationColor) }
    }

    /// 주석 크기 (1~20). 예전 버전이 저장한 "small"·"medium"·"large"도 읽는다
    var annotationSize: AnnotationSize {
        get {
            let stored = defaults.object(forKey: Key.annotationSize)
            if let value = stored as? Int { return AnnotationSize(value) }
            switch stored as? String {
            case "small": return .small
            case "large": return .large
            default: return .medium
            }
        }
        set { defaults.set(newValue.value, forKey: Key.annotationSize) }
    }

    var annotationTextFont: TextFont {
        get { TextFont(rawValue: defaults.string(forKey: Key.annotationTextFont) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.annotationTextFont) }
    }

    var annotationTextBackground: Bool {
        get { defaults.bool(forKey: Key.annotationTextBackground) }
        set { defaults.set(newValue, forKey: Key.annotationTextBackground) }
    }

    /// 가리기 도구 방식. "pixelate" 또는 "blur"로 저장한다
    var annotationRedactMode: RedactMode {
        get { RedactMode(rawValue: defaults.string(forKey: Key.annotationRedactMode) ?? "") ?? .pixelate }
        set { defaults.set(newValue.rawValue, forKey: Key.annotationRedactMode) }
    }
}
