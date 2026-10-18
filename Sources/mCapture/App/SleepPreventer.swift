import IOKit.pwr_mgt
import MCaptureCore

/// 시스템 유휴 잠자기 방지. caffeinate -i와 같은 전원 관리 assertion이고 화면은 평소대로 꺼진다
/// 앱이 끝나면(비정상 종료 포함) 시스템이 assertion을 풀어 주므로 따로 정리하지 않는다
/// 상태는 저장하지 않아 실행할 때마다 꺼진 채로 시작한다
@MainActor
final class SleepPreventer {
    private var assertionID: IOPMAssertionID?

    var isActive: Bool { assertionID != nil }

    /// 켜거나 끈다. 이미 그 상태면 아무것도 하지 않는다. 켜기에 실패하면 false
    /// assertion 이름에 앱 이름을 넣어 `pmset -g assertions`에서 사용 중인 앱과 개발 빌드가 구분된다
    /// pmset은 ASCII가 아닌 이름을 빈 문자열로 보여 주므로 이름은 영문으로 둔다
    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        if active {
            guard assertionID == nil else { return true }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "\(AppVariant.current.displayName) prevent idle sleep" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                Log.app.error("잠자기 방지 켜기 실패: \(result)")
                return false
            }
            assertionID = id
            Log.app.info("잠자기 방지 켜짐")
        } else if let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
            Log.app.info("잠자기 방지 꺼짐")
        }
        return true
    }
}
