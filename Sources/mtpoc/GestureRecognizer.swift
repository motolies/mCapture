import Foundation

/// 분류 임계값과 필터 기준을 한곳에 모은다. CLI 플래그로 덮어쓴다
struct Thresholds: Sendable {
    /// 탭으로 보는 최대 이동 거리 (mm)와 최대 지속 시간 (초). 매직마우스 실측 탭은 135~315ms
    var tapMaxMM: Double = 3
    var tapMaxDuration: Double = 0.4
    /// 스와이프로 보는 최소 이동 거리 (mm). 마우스 폭이 51mm라 손가락을 벌리면 10mm 남짓밖에 못 움직인다
    var swipeMinMM: Double = 6
    /// 프레임이 이 시간 동안 끊기면 추적 상태를 통째로 버린다 (장치가 사라진 경우의 안전장치, 이벤트는 내지 않는다)
    var staleSeconds: Double = 1.0
    /// 첫 손가락이 닿은 뒤 이 시간 안에 닿은 손가락은 무조건 같은 제스처로 묶는다
    var groupWindow: Double = 0.15
    /// groupWindow를 넘겨 닿았어도 묶음이 아직 탭 범위 안에서만 움직였고 이 시간 안이면 같은 제스처로 본다
    /// (엄지·새끼손가락은 가볍게 떠 있다가 150~200ms 늦게 닿는 일이 흔하다. 실측: 4손가락 탭의 네 번째 손가락이 180ms 뒤 도착)
    var lateJoinWindow: Double = 0.3
    /// 이보다 오래 눌린 묶음은 쉬는 손가락으로 보고 버린다
    var maxHold: Double = 1.5
    /// 접촉 2개 이상일 때 이보다 아래(손바닥 쪽 끝)에 있는 접촉은 버린다
    var palmYLimit: Float = 0.3
    /// 좌우 가장자리에서 이보다 작은 접촉은 버린다
    var edgeSizeLimit: Float = 0.375
    /// 이보다 큰 접촉이 하나라도 있으면 손바닥으로 보고 프레임 전체를 무시한다
    var palmSizeLimit: Float = 5.5
}

/// y는 0이 손바닥 쪽, 1이 손끝 쪽이므로 +y를 "앞"으로 적는다 (--raw로 실측해 확정)
enum SwipeDirection: String, Sendable {
    case left = "왼쪽 ←"
    case right = "오른쪽 →"
    case forward = "앞 ↑"
    case backward = "뒤 ↓"
}

enum GestureEvent: Sendable, CustomStringConvertible {
    case tap(fingers: Int, duration: Double)
    /// 탭 범위 안에서 움직이지 않았지만 탭보다 오래 눌렀다 뗀 것
    case press(fingers: Int, duration: Double)
    case swipe(fingers: Int, direction: SwipeDirection, dxMM: Double, dyMM: Double, duration: Double)
    case unclassified(fingers: Int, dxMM: Double, dyMM: Double, duration: Double)
    case hold(fingers: Int)

    var description: String {
        switch self {
        case .tap(let n, let duration):
            "\(n)손가락 탭            \(Format.seconds(duration))"
        case .press(let n, let duration):
            "\(n)손가락 길게 탭       \(Format.seconds(duration))"
        case .swipe(let n, let direction, let dx, let dy, let duration):
            "\(n)손가락 스와이프 \(direction.rawValue)  dx=\(Format.mm(dx)) dy=\(Format.mm(dy)) \(Format.seconds(duration))"
        case .unclassified(let n, let dx, let dy, let duration):
            "\(n)손가락 이동(미분류)   dx=\(Format.mm(dx)) dy=\(Format.mm(dy)) \(Format.seconds(duration))"
        case .hold(let n):
            "\(n)손가락 길게 누름 → 쉬는 손가락으로 보고 무시"
        }
    }
}

/// 숫자 표기 도우미
enum Format {
    static func mm(_ value: Double) -> String { String(format: "%+.1fmm", value) }
    static func seconds(_ value: Double) -> String { String(format: "%.0fms", value * 1000) }
    static func f3(_ value: Float) -> String { String(format: "%.3f", Double(value)) }
    static func f2(_ value: Float) -> String { String(format: "%.2f", Double(value)) }
}

/// 매직마우스 제스처 인식기 (순수 로직, MT 타입 의존 없음)
///
/// 접촉 수가 아니라 **거의 동시에 닿기 시작한 손가락 묶음**을 제스처로 본다.
/// 매직마우스는 손가락을 얹은 채 쓰므로 "접촉 0"이 영영 안 올 수 있고, 얹어 둔 손가락은 묶음에 끼지 않아야 한다.
/// 프레임에는 그 순간의 접촉이 전부 들어 있으므로 **이번 프레임에 안 보이는 경로를 떨어진 것**으로 본다.
/// 시간 공백으로 떨어짐을 추정하지 않는 이유: 블루투스 마우스는 손가락을 누른 채로도 45~370ms 공백이 생기고,
/// 공백 뒤 같은 손가락을 새 손가락으로 오인하면 가짜 탭이 나온다.
/// 묶음의 손가락이 모두 떨어지면 평균 변위(mm)와 지속 시간으로 탭·스와이프를 가른다.
struct GestureRecognizer: Sendable {
    struct Config: Sendable {
        var thresholds: Thresholds
        /// 접촉으로 세는 state 값 (3 MakeTouch, 4 Touching 기본)
        var countedStates: Set<Int32>
        var filterResting: Bool
        var widthMM: Double
        var heightMM: Double
    }

    /// 걸러낸 결과. raw 출력에서 버린 접촉을 표시하는 데도 쓴다
    struct Filtered: Sendable {
        var kept: [Touch]
        var dropped: [Touch]
        var palmFrame: Bool
    }

    /// 한 손가락이 닿아 있는 동안의 경로
    private struct PathTrack: Sendable {
        let beganAt: Double
        let firstX: Float
        let firstY: Float
        var lastX: Float
        var lastY: Float
        var lastSeen: Double
    }

    /// 같은 제스처로 묶인 경로들
    private struct Group: Sendable {
        let firstBegan: Double
        var paths: Set<Int32>
    }

    let config: Config
    /// 프레임마다 1씩 오른다. 프레임이 끊긴 뒤 타이머가 "그 사이 새 프레임이 없었는지" 확인하는 데 쓴다
    private(set) var generation = 0
    private var tracks: [Int32: PathTrack] = [:]
    private var group: Group?
    /// 묶음에 속했다가 떨어진 경로. 묶음이 닫힐 때 변위 계산에 쓴다
    private var lifted: [Int32: PathTrack] = [:]

    init(config: Config) {
        self.config = config
    }

    /// 추적 중인 경로나 열린 묶음이 있으면 true. 프레임이 끊겼을 때 정리 타이머를 걸지 결정한다
    var isTracking: Bool { !tracks.isEmpty || group != nil }

    /// 접촉으로 셀 것만 남기고 쉬는 손가락·손바닥을 걸러낸다 (Jitouch magicMouseCallback 기준)
    static func filter(_ touches: [Touch], config: Config) -> Filtered {
        let contacts = touches.filter { config.countedStates.contains($0.state) }
        guard config.filterResting else { return Filtered(kept: contacts, dropped: [], palmFrame: false) }
        let t = config.thresholds
        if contacts.contains(where: { $0.zTotal > t.palmSizeLimit }) {
            return Filtered(kept: [], dropped: contacts, palmFrame: true)
        }
        var kept: [Touch] = []
        var dropped: [Touch] = []
        for touch in contacts {
            let palmEnd = contacts.count >= 2 && touch.y < t.palmYLimit
            let edge = (touch.x < 0.001 || touch.x > 0.999) && touch.zTotal < t.edgeSizeLimit
            if palmEnd || edge { dropped.append(touch) } else { kept.append(touch) }
        }
        return Filtered(kept: kept, dropped: dropped, palmFrame: false)
    }

    /// 프레임 하나를 반영한다. 묶음이 닫히면 이벤트를 돌려준다
    /// 순서: 보이는 경로 갱신 → 안 보이는 경로 떨어짐 처리 → 묶음 판정 → 새로 닿은 경로 배정
    /// (떨어짐을 먼저 처리해야 같은 프레임에서 "이전 탭이 끝나고 새 손가락이 닿는" 경우에 이전 탭을 잃지 않는다)
    mutating func process(timestamp: Double, touches: [Touch]) -> [GestureEvent] {
        generation &+= 1
        let filtered = Self.filter(touches, config: config)
        if filtered.palmFrame { return [] }
        var present = Set<Int32>()
        var landed: [Touch] = []
        for touch in filtered.kept {
            present.insert(touch.pathIndex)
            if var track = tracks[touch.pathIndex] {
                track.lastX = touch.x
                track.lastY = touch.y
                track.lastSeen = timestamp
                tracks[touch.pathIndex] = track
            } else {
                landed.append(touch)
            }
        }
        for path in tracks.keys.filter({ !present.contains($0) }) {
            lift(path)
        }
        let events = settle(now: timestamp)
        for touch in landed {
            tracks[touch.pathIndex] = PathTrack(
                beganAt: timestamp, firstX: touch.x, firstY: touch.y,
                lastX: touch.x, lastY: touch.y, lastSeen: timestamp
            )
            // MakeTouch(3) 없이 Touching으로 처음 보인 경로는 시작 전부터 닿아 있던 손가락이다 → 묶음에 넣지 않는다
            if touch.state == 3 || !config.countedStates.contains(3) {
                assign(path: touch.pathIndex, beganAt: timestamp)
            }
        }
        return events
    }

    /// 프레임이 오래 끊겼을 때 타이머가 부른다. 세대가 그대로면 추적 상태를 버린다 (떨어짐 시각을 모르므로 분류하지 않는다)
    mutating func flush(ifGeneration expected: Int) -> [GestureEvent] {
        guard expected == generation, isTracking else { return [] }
        tracks.removeAll()
        lifted.removeAll()
        group = nil
        return []
    }

    // 새 경로를 묶음에 넣는다. 열린 묶음의 첫 손가락보다 groupWindow 안이면 무조건, lateJoinWindow 안이면 묶음이 아직 가만히 있을 때만 같은 제스처다.
    // 잠깐 끊겼다 다시 닿은 묶음 안의 손가락은 그대로 둔다.
    // 그 밖에 늦게 닿은 손가락은 새 제스처의 시작이므로, 아직 눌려 있는 이전 묶음은 쉬는 손가락으로 보고 버린다
    private mutating func assign(path: Int32, beganAt: Double) {
        let t = config.thresholds
        if var current = group {
            if current.paths.contains(path) { return }
            let age = beganAt - current.firstBegan
            if age <= t.groupWindow || (age <= t.lateJoinWindow && isStill(current)) {
                current.paths.insert(path)
                group = current
                return
            }
            close(current)
        }
        group = Group(firstBegan: beganAt, paths: [path])
    }

    // 묶음의 손가락이 모두 탭 허용 범위 안에서만 움직였는지 (늦게 닿는 손가락을 받아 줄지 판단)
    private func isStill(_ current: Group) -> Bool {
        let t = config.thresholds
        return current.paths.allSatisfy { path in
            guard let track = tracks[path] ?? lifted[path] else { return true }
            return abs(Double(track.lastX - track.firstX) * config.widthMM) <= t.tapMaxMM
                && abs(Double(track.lastY - track.firstY) * config.heightMM) <= t.tapMaxMM
        }
    }

    // 경로가 떨어졌다. 묶음에 속한 경로면 변위 계산용으로 보관한다 (잠깐 끊겼다 다시 닿은 경우는 첫 위치를 유지)
    private mutating func lift(_ path: Int32) {
        guard let track = tracks.removeValue(forKey: path), group?.paths.contains(path) == true else { return }
        if var earlier = lifted[path] {
            earlier.lastX = track.lastX
            earlier.lastY = track.lastY
            earlier.lastSeen = track.lastSeen
            lifted[path] = earlier
        } else {
            lifted[path] = track
        }
    }

    // 묶음의 손가락이 모두 떨어졌으면 분류하고, 너무 오래 눌려 있으면 쉬는 손가락으로 버린다
    private mutating func settle(now: Double) -> [GestureEvent] {
        guard let current = group else { return [] }
        if !current.paths.contains(where: { tracks[$0] != nil }) {
            let groupTracks = current.paths.compactMap { lifted[$0] }
            close(current)
            return current.paths.count >= 2 ? [classify(current, tracks: groupTracks)] : []
        }
        if now - current.firstBegan > config.thresholds.maxHold {
            close(current)
            return current.paths.count >= 2 ? [.hold(fingers: current.paths.count)] : []
        }
        return []
    }

    // 묶음을 닫고 그 경로들의 떨어진 기록을 지운다. 아직 눌린 경로는 tracks에 남아 쉬는 손가락이 된다
    private mutating func close(_ current: Group) {
        group = nil
        for path in current.paths { lifted[path] = nil }
    }

    // 평균 변위(mm)와 지속 시간으로 탭·스와이프·미분류를 가른다
    private func classify(_ current: Group, tracks: [PathTrack]) -> GestureEvent {
        let n = current.paths.count
        let end = tracks.map(\.lastSeen).max() ?? current.firstBegan
        let duration = end - current.firstBegan
        let dx = tracks.map { Double($0.lastX - $0.firstX) * config.widthMM }.mean
        let dy = tracks.map { Double($0.lastY - $0.firstY) * config.heightMM }.mean
        let t = config.thresholds
        if abs(dx) <= t.tapMaxMM, abs(dy) <= t.tapMaxMM {
            return duration <= t.tapMaxDuration
                ? .tap(fingers: n, duration: duration)
                : .press(fingers: n, duration: duration)
        }
        if max(abs(dx), abs(dy)) >= t.swipeMinMM {
            let direction: SwipeDirection = abs(dx) >= abs(dy)
                ? (dx < 0 ? .left : .right)
                : (dy > 0 ? .forward : .backward)
            return .swipe(fingers: n, direction: direction, dxMM: dx, dyMM: dy, duration: duration)
        }
        return .unclassified(fingers: n, dxMM: dx, dyMM: dy, duration: duration)
    }
}

private extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}
