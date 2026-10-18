import Foundation

/// 앱 버전. 원본은 Resources/Info.plist의 CFBundleShortVersionString(버전)·CFBundleVersion(빌드 번호)이고
/// 빌드한 커밋(MCaptureGitCommit)은 build-app.sh가 번들을 만들 때 넣는다
public struct AppVersion: Sendable, Equatable {
    public static let commitKey = "MCaptureGitCommit"

    public let version: String?
    public let build: String?
    /// 짧은 커밋 해시. 커밋하지 않은 변경으로 빌드했으면 -dirty가 붙는다
    public let commit: String?

    /// 지금 실행 중인 앱의 버전
    public static let current = AppVersion(infoDictionary: Bundle.main.infoDictionary)

    /// 번들 없이 실행하면 키가 없어 모두 nil이 된다
    public init(infoDictionary: [String: Any]?) {
        version = Self.value(infoDictionary?["CFBundleShortVersionString"])
        build = Self.value(infoDictionary?["CFBundleVersion"])
        commit = Self.value(infoDictionary?[Self.commitKey])
    }

    /// 설정 화면·툴팁에 보이는 문자열 (예: 0.1.1 (344637f))
    /// 빌드 번호는 같은 버전의 빌드끼리 구분하지 못해 커밋이 있으면 커밋을 보여 준다
    public var displayString: String {
        switch (version, commit ?? build) {
        case let (version?, detail?): "\(version) (\(detail))"
        case let (version?, nil): version
        case let (nil, detail?): "빌드 \(detail)"
        case (nil, nil): "알 수 없음"
        }
    }

    // 문자열이고 비어 있지 않을 때만 쓴다
    private static func value(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
}
