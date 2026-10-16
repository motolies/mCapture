import AppKit
import CoreGraphics

/// 화면 기록 권한 확인과 안내
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 권한이 없으면 시스템 요청을 띄우고 안내 창을 보여준다. 캡처를 진행해도 되면 true
    static func ensureGranted() -> Bool {
        if isGranted { return true }
        // 처음이면 시스템 권한 요청 창이 뜬다. 허용해도 앱을 다시 실행해야 적용된다
        _ = CGRequestScreenCaptureAccess()

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = """
            시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 mCapture를 허용한 뒤 \
            mCapture를 다시 실행하세요.
            """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
        return false
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
