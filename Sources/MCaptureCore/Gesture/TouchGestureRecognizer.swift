import Foundation

/// 멀티터치 제스처 인식기 (순수 로직, 프레임워크 타입 의존 없음)
///
/// 접촉 수가 아니라 **거의 동시에 닿기 시작한 손가락 묶음**을 제스처로 본다.
/// 매직마우스는 손가락을 얹은 채 쓰므로 "접촉 0"이 영영 안 올 수 있고, 얹어 둔 손가락은 묶음에 끼지 않아야 한다.
/// 프레임에는 그 순간의 접촉이 전부 들어 있으므로 **이번 프레임에 안 보이는 경로를 떨어진 것**으로 본다.
/// 시간 공백으로 떨어짐을 추정하지 않는 이유: 블루투스 마우스는 손가락을 누른 채로도 45~370ms 공백이 생기고,
/// 공백 뒤 같은 손가락을 새 손가락으로 오인하면 가짜 탭이 나온다.
/// 묶음의 손가락이 모두 떨어지면 평균 변위(mm)와 지속 시간으로 탭·스와이프를 가른다.
/// 장치별 차이(임계값·필터·표면 크기)는 모두 `Profile`에 있어 상태 기계 자체는 장치를 모른다.
public struct TouchGestureRecognizer: Sendable {
    /// 분류 임계값과 필터 기준
    public struct Thresholds: Sendable, Equatable {
        /// 탭으로 보는 최대 이동 거리 (mm)와 최대 지속 시간 (초). 매직마우스 실측 탭은 135~371ms
        public var tapMaxMM: Double = 3
        public var tapMaxDuration: Double = 0.4
        /// 스와이프로 보는 최소 이동 거리 (mm). 마우스 폭이 51mm라 손가락을 벌리면 10mm 남짓밖에 못 움직인다
        public var swipeMinMM: Double = 6
        /// 프레임이 이 시간 동안 끊기면 추적 상태를 통째로 버린다 (장치가 사라진 경우의 안전장치, 이벤트는 내지 않는다)
        public var staleSeconds: Double = 1.0
        /// 첫 손가락이 닿은 뒤 이 시간 안에 닿은 손가락은 무조건 같은 제스처로 묶는다
        public var groupWindow: Double = 0.15
        /// groupWindow를 넘겨 닿았어도 묶음이 아직 탭 범위 안에서만 움직였고 이 시간 안이면 같은 제스처로 본다
        /// (엄지·새끼손가락은 가볍게 떠 있다가 150~200ms 늦게 닿는 일이 흔하다. 실측: 4손가락 탭의 네 번째 손가락이 180ms 뒤 도착)
        public var lateJoinWindow: Double = 0.3
        /// 이보다 오래 눌린 묶음은 쉬는 손가락으로 보고 버린다
        public var maxHold: Double = 1.5
        /// 접촉 2개 이상일 때 이보다 아래(손바닥 쪽 끝)에 있는 접촉은 버린다
        public var palmYLimit: Float = 0.3
        /// 좌우 가장자리에서 이보다 작은 접촉은 버린다
        public var edgeSizeLimit: Float = 0.375
        /// 이보다 큰 접촉이 하나라도 있으면 손바닥으로 보고 프레임 전체를 무시한다
        public var palmSizeLimit: Float = 5.5
        /// 좌우 가장자리(이 비율 안)의 Hover/Linger 접촉은 닿은 것으로 센다. 0이면 끔.
        /// 실측: 넓게 벌린 엄지·새끼손가락은 센서가 Touching 대신 HoverInRange z=0.12~0.25로만 보고해 4손가락이 3으로 세어졌다
        public var edgeHoverX: Float = 0.12
        /// 가장자리 Hover 접촉을 셀 최소 크기
        public var edgeHoverZ: Float = 0.12

        public init() {}
    }

    /// 장치 종류별 인식 설정. 새 터치 장치는 `default(for:surface:)`에 case를 더해 붙인다
    public struct Profile: Sendable, Equatable {
        public var thresholds: Thresholds
        /// 접촉으로 세는 state 값 (3 MakeTouch, 4 Touching 기본)
        public var countedStates: Set<Int32>
        /// 쉬는 손가락·손바닥 필터를 켤지
        public var filterResting: Bool
        public var surface: SurfaceSize

        public init(
            thresholds: Thresholds = Thresholds(), countedStates: Set<Int32> = [3, 4],
            filterResting: Bool = true, surface: SurfaceSize
        ) {
            self.thresholds = thresholds
            self.countedStates = countedStates
            self.filterResting = filterResting
            self.surface = surface
        }

        /// 장치 종류별 기본값. 아직 다루지 않는 종류면 nil (트랙패드는 실측 뒤 edgeHoverX 0 등으로 추가한다)
        public static func `default`(for kind: InputDeviceKind, surface: SurfaceSize) -> Profile? {
            switch kind {
            case .magicMouse: Profile(surface: surface)
            case .magicTrackpad, .builtInTrackpad, .unknown: nil
            }
        }
    }

    /// 걸러낸 결과. raw 출력에서 버린 접촉을 표시하는 데도 쓴다
    public struct Filtered: Sendable, Equatable {
        public var kept: [TouchContact]
        public var dropped: [TouchContact]
        public var palmFrame: Bool

        public init(kept: [TouchContact], dropped: [TouchContact], palmFrame: Bool) {
            self.kept = kept
            self.dropped = dropped
            self.palmFrame = palmFrame
        }

        /// 접촉으로 센 경로 번호
        public var countedPaths: Set<Int32> { Set(kept.map(\.pathIndex)) }
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

    public let profile: Profile
    /// 프레임마다 1씩 오른다. 프레임이 끊긴 뒤 타이머가 "그 사이 새 프레임이 없었는지" 확인하는 데 쓴다
    public private(set) var generation = 0
    private var tracks: [Int32: PathTrack] = [:]
    private var group: Group?
    /// 묶음에 속했다가 떨어진 경로. 묶음이 닫힐 때 변위 계산에 쓴다
    private var lifted: [Int32: PathTrack] = [:]
    /// 마지막 버튼 누름 시각. MT 버튼 콜백과 이벤트 탭이 같은 클릭을 11~22ms 차이로 둘 다 알려 주므로 가까운 두 번째는 버린다
    private var lastButtonDownAt: Double?

    public init(profile: Profile) {
        self.profile = profile
    }

    /// 추적 중인 경로나 열린 묶음이 있으면 true. 프레임이 끊겼을 때 정리 타이머를 걸지 결정한다
    public var isTracking: Bool { !tracks.isEmpty || group != nil }

    /// 접촉으로 셀 것만 남기고 쉬는 손가락·손바닥을 걸러낸다 (Jitouch magicMouseCallback 기준)
    public static func filter(_ contacts: [TouchContact], profile: Profile) -> Filtered {
        let t = profile.thresholds
        let counted = contacts.filter { contact in
            if profile.countedStates.contains(contact.state) { return true }
            // 가장자리에서 약하게 닿은 손가락: Hover(2)·Linger(6)로만 보고되지만 실제로는 얹혀 있다
            let hovering = contact.state == 2 || contact.state == 6
            let nearEdge = contact.x < t.edgeHoverX || contact.x > 1 - t.edgeHoverX
            return hovering && t.edgeHoverX > 0 && nearEdge && contact.zTotal >= t.edgeHoverZ
        }
        guard profile.filterResting else { return Filtered(kept: counted, dropped: [], palmFrame: false) }
        if counted.contains(where: { $0.zTotal > t.palmSizeLimit }) {
            return Filtered(kept: [], dropped: counted, palmFrame: true)
        }
        var kept: [TouchContact] = []
        var dropped: [TouchContact] = []
        for contact in counted {
            let palmEnd = counted.count >= 2 && contact.y < t.palmYLimit
            let edge = (contact.x < 0.001 || contact.x > 0.999) && contact.zTotal < t.edgeSizeLimit
            if palmEnd || edge { dropped.append(contact) } else { kept.append(contact) }
        }
        return Filtered(kept: kept, dropped: dropped, palmFrame: false)
    }

    /// 이 인식기의 설정으로 프레임을 걸러낸 결과 (raw 표시용)
    public func filtered(_ frame: TouchFrame) -> Filtered {
        Self.filter(frame.contacts, profile: profile)
    }

    /// 프레임 하나를 반영한다. 묶음이 닫히면 이벤트를 돌려준다
    /// 순서: 보이는 경로 갱신 → 안 보이는 경로 떨어짐 처리 → 묶음 판정 → 새로 닿은 경로 배정
    /// (떨어짐을 먼저 처리해야 같은 프레임에서 "이전 탭이 끝나고 새 손가락이 닿는" 경우에 이전 탭을 잃지 않는다)
    public mutating func process(_ frame: TouchFrame) -> [RecognizedGesture] {
        generation &+= 1
        let filtered = Self.filter(frame.contacts, profile: profile)
        if filtered.palmFrame { return [] }
        let timestamp = frame.timestamp
        var present = Set<Int32>()
        var landed: [TouchContact] = []
        for contact in filtered.kept {
            present.insert(contact.pathIndex)
            if var track = tracks[contact.pathIndex] {
                track.lastX = contact.x
                track.lastY = contact.y
                track.lastSeen = timestamp
                tracks[contact.pathIndex] = track
            } else {
                landed.append(contact)
            }
        }
        for path in tracks.keys.filter({ !present.contains($0) }) {
            lift(path)
        }
        let events = settle(now: timestamp)
        for contact in landed {
            tracks[contact.pathIndex] = PathTrack(
                beganAt: timestamp, firstX: contact.x, firstY: contact.y,
                lastX: contact.x, lastY: contact.y, lastSeen: timestamp
            )
            // 처음 보인 상태가 MakeTouch(3)나 Hover(2, 가장자리 약한 접촉)면 지금 닿은 손가락이다.
            // Touching(4)으로 처음 보이면 시작 전부터 닿아 있던 손가락이므로 묶음에 넣지 않는다
            if contact.state == 3 || contact.state == 2 || !profile.countedStates.contains(3) {
                assign(path: contact.pathIndex, beganAt: timestamp)
            }
        }
        return events
    }

    /// 물리 버튼이 눌렸다. 그 순간 닿아 있는(걸러낸) 접촉 수를 손가락 수로 본다.
    /// 열린 묶음은 조용히 닫아, 클릭한 손가락이 떨어질 때 탭으로 다시 분류되지 않게 한다.
    /// 같은 클릭을 다른 경로가 150ms 안에 다시 알려 주면 무시한다 (먼저 온 쪽이 이긴다. 실측으로는 MT 콜백이 항상 먼저다).
    /// 시각은 마지막 프레임의 장치 시계로 넘겨야 두 경로의 중복 제거가 맞는다
    public mutating func buttonDown(_ button: MouseButton, at deviceTime: Double) -> [RecognizedGesture] {
        if let last = lastButtonDownAt, deviceTime - last < 0.15 { return [] }
        lastButtonDownAt = deviceTime
        if let current = group { close(current) }
        return [RecognizedGesture(gesture: .click(fingers: tracks.count, button: button))]
    }

    /// 프레임이 오래 끊겼을 때 타이머가 부른다. 세대가 그대로면 추적 상태를 버린다 (떨어짐 시각을 모르므로 분류하지 않는다)
    public mutating func flush(ifGeneration expected: Int) -> [RecognizedGesture] {
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
        let t = profile.thresholds
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
        let t = profile.thresholds
        return current.paths.allSatisfy { path in
            guard let track = tracks[path] ?? lifted[path] else { return true }
            return abs(Double(track.lastX - track.firstX) * profile.surface.widthMM) <= t.tapMaxMM
                && abs(Double(track.lastY - track.firstY) * profile.surface.heightMM) <= t.tapMaxMM
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
    private mutating func settle(now: Double) -> [RecognizedGesture] {
        guard let current = group else { return [] }
        if !current.paths.contains(where: { tracks[$0] != nil }) {
            let groupTracks = current.paths.compactMap { lifted[$0] }
            close(current)
            return current.paths.count >= 2 ? [classify(current, tracks: groupTracks)] : []
        }
        if now - current.firstBegan > profile.thresholds.maxHold {
            close(current)
            return current.paths.count >= 2 ? [RecognizedGesture(gesture: .hold(fingers: current.paths.count))] : []
        }
        return []
    }

    // 묶음을 닫고 그 경로들의 떨어진 기록을 지운다. 아직 눌린 경로는 tracks에 남아 쉬는 손가락이 된다
    private mutating func close(_ current: Group) {
        group = nil
        for path in current.paths { lifted[path] = nil }
    }

    // 평균 변위(mm)와 지속 시간으로 탭·스와이프·미분류를 가른다
    private func classify(_ current: Group, tracks: [PathTrack]) -> RecognizedGesture {
        let n = current.paths.count
        let end = tracks.map(\.lastSeen).max() ?? current.firstBegan
        let duration = end - current.firstBegan
        let dx = tracks.map { Double($0.lastX - $0.firstX) * profile.surface.widthMM }.mean
        let dy = tracks.map { Double($0.lastY - $0.firstY) * profile.surface.heightMM }.mean
        let metrics = GestureMetrics(dxMM: dx, dyMM: dy, duration: duration)
        let t = profile.thresholds
        if abs(dx) <= t.tapMaxMM, abs(dy) <= t.tapMaxMM {
            let gesture: InputGesture = duration <= t.tapMaxDuration ? .tap(fingers: n) : .longPress(fingers: n)
            return RecognizedGesture(gesture: gesture, metrics: metrics)
        }
        if max(abs(dx), abs(dy)) >= t.swipeMinMM {
            let direction: SwipeDirection = abs(dx) >= abs(dy)
                ? (dx < 0 ? .left : .right)
                : (dy > 0 ? .up : .down)
            return RecognizedGesture(gesture: .swipe(fingers: n, direction: direction), metrics: metrics)
        }
        return RecognizedGesture(gesture: .move(fingers: n), metrics: metrics)
    }
}

private extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}
