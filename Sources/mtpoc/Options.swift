import Foundation

/// 명령줄 옵션
struct Options: Sendable {
    var raw = false
    var all = false
    var device: Int?
    var filter = true
    /// IOHIDRequestAccess로 입력 모니터링 권한을 요청한다 (시스템 대화상자가 뜬다)
    var requestAccess = false
    /// 1초마다 포인터 위치 변화를 찍는다 (마우스를 실제로 움직였는지 보는 보조 신호)
    var pointer = false
    var states: Set<Int32> = [3, 4]
    var thresholds = Thresholds()

    static let usage = """
    사용법: swift run mtpoc [옵션]
      --raw            프레임마다 접촉 수·좌표·state를 모두 출력 (걸러진 접촉은 x 표시)
      --all            매직마우스뿐 아니라 모든 멀티터치 장치에서 받기
      --device N       표의 N번 장치만
      --no-filter      쉬는 손가락·손바닥 필터 끄기
      --request-access 입력 모니터링 권한을 요청 (프레임이 전혀 안 올 때)
      --pointer        포인터 이동을 1초 간격으로 기록 (사용자 활동 확인용)
      --states 3,4     접촉으로 셀 state 값 (기본 3,4)
      --tap-mm 3       탭 최대 이동 (mm)
      --tap-time 0.4   탭 최대 지속 (초)
      --swipe-mm 6     스와이프 최소 이동 (mm)
      --group-ms 150   같은 제스처로 묶는 손가락 도착 간격 (ms)
      --hold-s 1.5     이보다 오래 누르면 쉬는 손가락으로 간주 (초)
    """

    /// 인자를 해석한다. 모르는 옵션이면 사용법을 적고 종료
    static func parse(_ args: [String]) -> Options {
        var options = Options()
        var i = 0
        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        func number() -> Double? { value().flatMap(Double.init) }
        while i < args.count {
            switch args[i] {
            case "--raw": options.raw = true
            case "--all": options.all = true
            case "--no-filter": options.filter = false
            case "--request-access": options.requestAccess = true
            case "--pointer": options.pointer = true
            case "--device": options.device = value().flatMap(Int.init)
            case "--states": options.states = Set((value() ?? "").split(separator: ",").compactMap { Int32($0) })
            case "--tap-mm": options.thresholds.tapMaxMM = number() ?? options.thresholds.tapMaxMM
            case "--tap-time": options.thresholds.tapMaxDuration = number() ?? options.thresholds.tapMaxDuration
            case "--swipe-mm": options.thresholds.swipeMinMM = number() ?? options.thresholds.swipeMinMM
            case "--group-ms": options.thresholds.groupWindow = (number() ?? options.thresholds.groupWindow * 1000) / 1000
            case "--hold-s": options.thresholds.maxHold = number() ?? options.thresholds.maxHold
            case "--help", "-h":
                Console.line(usage)
                exit(0)
            default:
                Console.error("알 수 없는 옵션: \(args[i])\n\(usage)")
                exit(2)
            }
            i += 1
        }
        return options
    }

    /// 시작할 때 보여 줄 설정 요약
    var summary: String {
        let t = thresholds
        return "설정: 탭 ≤\(t.tapMaxMM)mm·≤\(Int(t.tapMaxDuration * 1000))ms, 스와이프 ≥\(t.swipeMinMM)mm, 묶음 \(Int(t.groupWindow * 1000))ms, 끊김 정리 \(Int(t.staleSeconds * 1000))ms, 길게 누름 \(t.maxHold)s, state \(states.sorted()), 필터 \(filter ? "켬" : "끔")"
    }
}
