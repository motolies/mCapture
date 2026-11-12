import Foundation

/// 인식 실패한 외부 디스플레이를 자동으로 복구할지 정하는 규칙.
///
/// 자동 복구는 화면 구성이 바뀔 때마다 확인하는데, 복구 자체가 화면 구성을 바꾼다.
/// 그래서 같은 연결에는 한 번만 시도하고, 연결이 계속 새로 생기는 경우에 대비해 일정 시간 안의 시도 횟수도 제한한다
public struct DisplayAutoRecoveryPolicy: Sendable {
    /// 한 번의 확인에서 내린 결정
    public struct Decision: Equatable, Sendable {
        /// 지금 복구를 시도할 연결 (번호 순)
        public let attempts: [UInt64]
        /// 시도 횟수 제한에 걸려 미룬 연결이 있음
        public let limited: Bool

        public init(attempts: [UInt64], limited: Bool) {
            self.attempts = attempts
            self.limited = limited
        }
    }

    /// window 초 안에 허용하는 자동 시도 횟수
    public let maxAttempts: Int
    public let window: TimeInterval

    /// 이미 시도한 연결. 인식 실패 상태가 이어지는 동안에만 기억한다
    private var attempted: Set<UInt64> = []
    /// window 안에 자동으로 시도한 시각
    private var recentAttempts: [TimeInterval] = []

    public init(maxAttempts: Int = 3, window: TimeInterval = 300) {
        self.maxAttempts = maxAttempts
        self.window = window
    }

    /// 지금 인식 실패 상태인 연결을 받아 자동으로 시도할 연결을 고른다. now는 거꾸로 가지 않는 시각(초).
    /// 정상 인식되거나 뽑힌 연결은 잊으므로, 나중에 다시 인식에 실패하면 다시 시도한다
    public mutating func evaluate(unrecognized: Set<UInt64>, now: TimeInterval) -> Decision {
        attempted.formIntersection(unrecognized)
        recentAttempts.removeAll { now - $0 >= window }

        var attempts: [UInt64] = []
        var limited = false
        for id in unrecognized.subtracting(attempted).sorted() {
            guard recentAttempts.count < maxAttempts else {
                limited = true
                break
            }
            recentAttempts.append(now)
            attempted.insert(id)
            attempts.append(id)
        }
        return Decision(attempts: attempts, limited: limited)
    }

    /// 사용자가 직접 복구한 연결을 기록한다. 그 복구가 일으킨 화면 변경으로 같은 연결을 자동으로 또 시도하지 않게 한다.
    /// 직접 한 복구는 횟수 제한에 넣지 않는다
    public mutating func markAttempted(_ id: UInt64) {
        attempted.insert(id)
    }
}
