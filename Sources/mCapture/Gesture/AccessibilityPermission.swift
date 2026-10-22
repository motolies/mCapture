import AppKit
import CoreGraphics

/// 다른 앱에 키 이벤트를 보내는 권한 (시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용). 제스처 인식 자체에는 필요 없다
@MainActor
enum AccessibilityPermission {
    /// 지금 키 이벤트를 보낼 수 있는지. 허용하면 앱을 다시 실행하지 않아도 반영된다
    static var isGranted: Bool {
        CGPreflightPostEventAccess()
    }

    /// 시스템에 권한을 요청하고(처음이면 목록에 앱이 올라감) 아직 없으면 시스템 설정의 손쉬운 사용 항목을 연다
    static func request() {
        guard !CGRequestPostEventAccess() else { return }
        openSystemSettings()
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
