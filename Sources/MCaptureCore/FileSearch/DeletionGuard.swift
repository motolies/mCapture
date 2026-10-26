import Foundation

/// 휴지통으로 옮기면 안 되는 경로를 가려낸다. 체크할 때 한 번, 옮기기 직전에 한 번 더 쓴다
///
/// 시스템 폴더·홈 자체·검색 폴더와 그 위·홈의 표준 폴더·앱 번들·클라우드 폴더 안은 막는다.
/// 대소문자를 가리지 않는 APFS가 기본이라 비교는 소문자로 한다
public struct DeletionGuard: Sendable {
    public enum Reason: Sendable, Equatable {
        /// 시스템 폴더와 그 안
        case system
        /// `/`, `/Applications`, `/Users`, 볼륨 루트, 사용자 홈 같은 최상위 폴더
        case topLevel
        /// 설정한 검색 폴더 자신이나 그 위 폴더
        case searchRoot
        /// 홈의 표준 폴더(데스크탑·문서 등)와 `~/Library` 바로 아래
        case standardFolder
        /// mCapture 앱과 그것을 품은 폴더
        case selfApp
        /// 앱 번들(.app)과 그 안
        case appBundle
        /// iCloud Drive·클라우드 저장소 폴더 안 (다른 기기에서도 지워진다)
        case cloud

        /// 사용자에게 보일 이유
        public var message: String {
            switch self {
            case .system: "시스템 폴더는 지울 수 없습니다"
            case .topLevel: "최상위 폴더는 지울 수 없습니다"
            case .searchRoot: "검색 폴더와 그 위 폴더는 지울 수 없습니다"
            case .standardFolder: "기본 폴더는 지울 수 없습니다"
            case .selfApp: "mCapture 앱은 지울 수 없습니다"
            case .appBundle: "앱은 지울 수 없습니다"
            case .cloud: "클라우드 폴더 안의 항목은 지울 수 없습니다"
            }
        }
    }

    /// 그 안까지 모두 막는 시스템 폴더
    static let systemTrees = ["/system", "/bin", "/sbin", "/usr", "/etc", "/var", "/dev", "/cores", "/library",
                              "/private/var", "/private/etc"]
    /// 그 자신만 막는 최상위 폴더
    static let topLevelFolders: Set<String> = ["/", "/applications", "/applications/utilities", "/users", "/volumes",
                                               "/network", "/private", "/tmp", "/private/tmp", "/opt"]
    /// 홈 바로 아래 표준 폴더 (그 자신만)
    static let standardFolders = ["desktop", "documents", "downloads", "library", "movies", "music", "pictures",
                                  "public", "applications", ".trash"]

    private let home: String
    private let roots: [String]
    private let appPath: String?

    /// home·roots·appPath는 실제 경로. 홈은 `~` 확장에, 루트는 검색 폴더 보호에, appPath는 자기 앱 보호에 쓴다
    public init(home: String, roots: [String], appPath: String?) {
        self.home = Self.normalized(home)
        self.roots = roots.map(Self.normalized)
        self.appPath = appPath.map(Self.normalized)
    }

    /// 막을 이유. 지워도 되면 nil
    public func reason(path: String) -> Reason? {
        let path = Self.normalized(path)
        if Self.topLevelFolders.contains(path) || path == home || Self.isUserHome(path) || Self.isVolumeRoot(path) {
            return .topLevel
        }
        if Self.systemTrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .system }
        if roots.contains(where: { path == $0 || $0.hasPrefix(path + "/") }) { return .searchRoot }
        if let appPath, path == appPath || appPath.hasPrefix(path + "/") { return .selfApp }
        let library = home + "/library"
        if path.hasPrefix(library + "/mobile documents/") || path.hasPrefix(library + "/cloudstorage/") { return .cloud }
        if path.hasPrefix(home + "/") {
            let relative = path.dropFirst(home.count + 1)
            if !relative.contains("/"), Self.standardFolders.contains(String(relative)) { return .standardFolder }
            if relative.hasPrefix("library/"), !relative.dropFirst("library/".count).contains("/") { return .standardFolder }
        }
        if path.hasSuffix(".app") || path.contains(".app/") { return .appBundle }
        return nil
    }

    // `/Users/이름` (다른 사용자 홈 포함)
    private static func isUserHome(_ path: String) -> Bool {
        path.hasPrefix("/users/") && !path.dropFirst("/users/".count).contains("/")
    }

    // `/Volumes/이름`
    private static func isVolumeRoot(_ path: String) -> Bool {
        path.hasPrefix("/volumes/") && !path.dropFirst("/volumes/".count).contains("/")
    }

    // NFC 소문자, 끝의 / 제거 (`/`는 그대로)
    static func normalized(_ path: String) -> String {
        var text = HangulText.nfc(path).lowercased()
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
