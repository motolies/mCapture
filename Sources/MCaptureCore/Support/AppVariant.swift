import Foundation

/// 같은 Mac에서 사용 중인 앱과 개발 빌드가 겹치지 않도록 번들 ID로 나누는 실행 변형
/// 설정 도메인·URL Scheme·단축키·저장 폴더·임시 폴더가 변형마다 달라 두 앱을 동시에 띄워도 서로 건드리지 않는다
public enum AppVariant: Sendable, Equatable {
    /// DMG로 배포해 상주시키는 앱 (com.motolies.mcapture)
    case production
    /// 개발 빌드. 워크트리 빌드나 번들 없이 실행한 경우도 여기에 든다
    case dev

    public static let productionBundleID = "com.motolies.mcapture"

    /// 지금 실행 중인 앱의 변형
    public static let current = AppVariant(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// 원래 번들 ID와 정확히 같을 때만 production으로 본다. 나머지는 모두 dev라 사용 중인 앱 쪽으로 새지 않는다
    public init(bundleIdentifier: String?) {
        self = bundleIdentifier == Self.productionBundleID ? .production : .dev
    }

    /// 번들 ID이자 UserDefaults 도메인, 로그 subsystem
    public var bundleIdentifier: String {
        switch self {
        case .production: Self.productionBundleID
        case .dev: Self.productionBundleID + ".dev"
        }
    }

    /// 메뉴·창 제목·권한 안내에 보이는 앱 이름
    public var displayName: String {
        switch self {
        case .production: "mCapture"
        case .dev: "mCapture Dev"
        }
    }

    public var urlScheme: String {
        switch self {
        case .production: "mcapture"
        case .dev: "mcapture-dev"
        }
    }

    public var defaultSaveFolder: String {
        switch self {
        case .production: "~/Pictures/mCapture"
        case .dev: "~/Pictures/mCapture-dev"
        }
    }

    /// 끌어놓기 임시 파일 폴더 이름. 앱이 시작할 때 비우므로 변형끼리 나눠야 한다
    public var dragFolderName: String {
        switch self {
        case .production: "mCapture-drag"
        case .dev: "mCapture-dev-drag"
        }
    }

    /// 동작별 기본 단축키 문자열. dev는 ⌥를 더해 사용 중인 앱의 ⌃⇧ 조합과 겹치지 않게 한다
    public func defaultHotkey(key: String) -> String {
        switch self {
        case .production: "ctrl+shift+\(key)"
        case .dev: "ctrl+opt+shift+\(key)"
        }
    }
}
