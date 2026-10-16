import AppKit
import MCaptureCore

/// 창 캡처 후보. frame은 AppKit 전역 좌표(주 화면 왼쪽 아래 원점, 포인트)
struct WindowTarget: Sendable {
    let id: CGWindowID
    let frame: CGRect
    /// 창을 가진 앱 이름 (파일 이름 {app})
    let ownerName: String?
}

/// 화면에 보이는 창 목록
@MainActor
enum WindowList {
    /// 일반 창을 앞에서 뒤 순서로 돌려준다. 자기 앱 창, 메뉴 막대·Dock 같은 시스템 레이어, 투명하거나 아주 작은 창은 뺀다
    static func onScreen() -> [WindowTarget] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CG 창 좌표는 주 화면(메뉴 막대가 있는 첫 화면) 왼쪽 위 원점이다
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width >= 40, bounds.height >= 40
            else { return nil }
            return WindowTarget(id: id, frame: RectMath.flipped(bounds, height: primaryHeight), ownerName: info[kCGWindowOwnerName as String] as? String)
        }
    }
}
