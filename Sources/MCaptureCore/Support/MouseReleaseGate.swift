/// 제스처에 묶은 키 조합을 언제 보낼지 마우스 버튼 상태 표본으로 정한다. KeySender가 16ms마다 표본을 넣는다.
///
/// 클릭 제스처는 MT 버튼 콜백(누름)에서 발화하는데, 이 콜백은 시스템 버튼 상태보다 11~22ms 먼저 온다.
/// 그래서 발화 순간에는 버튼이 아직 안 눌린 것으로 보인다. 그 상태로 보내면 곧이어 들어온 진짜 클릭이
/// 앞 앱(Finder)의 마우스 추적을 시작해 키가 먹지 않는다. 클릭이면 눌림이 보일 때까지 기다린 뒤 뗌을 기다린다
public struct MouseReleaseGate: Sendable {
    public enum Decision: Equatable, Sendable {
        case wait
        case send
        /// 버튼이 너무 오래 눌려 있다 (드래그로 보고 보내지 않음)
        case abandon
    }

    /// 눌림이 안 보여도 이만큼 지나면 보낸다 (합성 이벤트나 끝내 눌림을 못 본 클릭). 0이면 첫 표본이 안 눌림일 때 바로 보낸다
    public let pressGrace: Duration
    /// 처음부터 이만큼 지나도록 눌려 있으면 보내지 않는다
    public let releaseTimeout: Duration
    /// 한 번이라도 눌린 표본을 봤는지
    public private(set) var sawPress = false

    public init(pressGrace: Duration, releaseTimeout: Duration) {
        self.pressGrace = pressGrace
        self.releaseTimeout = releaseTimeout
    }

    /// 클릭 제스처면 눌림을 0.1초까지 기다린다 (MT 선행 22ms + 앱 디스패치 지연에 여유). 그 밖은 지금 눌려 있을 때만 뗌을 기다린다
    public static func forGesture(isClick: Bool) -> MouseReleaseGate {
        MouseReleaseGate(pressGrace: isClick ? .milliseconds(100) : .zero, releaseTimeout: .seconds(1))
    }

    /// 표본 하나를 반영한다. elapsed는 첫 표본(발화)부터 지난 시간
    public mutating func update(pressed: Bool, elapsed: Duration) -> Decision {
        if pressed {
            sawPress = true
            return elapsed >= releaseTimeout ? .abandon : .wait
        }
        return sawPress || elapsed >= pressGrace ? .send : .wait
    }
}
