import AppKit
import ApplicationServices

/// 다른 앱에 키 이벤트를 보내는 권한 (시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용. macOS 27부터는 "기기 제어 및 데이터 접근"). 제스처 인식 자체에는 필요 없다
@MainActor
enum AccessibilityPermission {
    /// 시스템 설정에 보이는 항목 이름. macOS 27에서 이름이 바뀌어 안내 문구를 화면과 맞춘다
    static var settingsItemName: String {
        if #available(macOS 27, *) { "기기 제어 및 데이터 접근" } else { "손쉬운 사용" }
    }

    /// 지금 키 이벤트를 보낼 수 있는지. 판정은 프로세스 안에 캐시되지만 시스템 설정이 토글 때 보내는 분산 알림
    /// `com.apple.accessibility.api`로 풀리므로 허용하면 앱을 다시 실행하지 않아도 반영된다.
    /// `CGPreflightPostEventAccess`는 쓰지 않는다: `kTCCServicePostEvent`를 묻는데 그 캐시는 이 알림으로 풀리지 않아 허용한 뒤에도 false를 돌려준다 (macOS 27 실측)
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 시스템 권한 대화상자를 띄워 목록에 앱을 올리고, 시스템 설정의 해당 항목도 연다.
    /// 전에 거부했으면 대화상자는 다시 뜨지 않으므로 설정 창은 항상 연다.
    /// `CGRequestPostEventAccess`는 쓰지 않는다: 거부 기록이 있으면 대화상자 없이 거부만 돌려주고 목록에도 올리지 않는다 (macOS 27 실측)
    static func request() {
        guard !isGranted else { return }
        // kAXTrustedCheckOptionPrompt의 값. 그 상수는 전역 var라 Swift 6 동시성 검사에 걸려 문자열을 직접 쓴다
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
