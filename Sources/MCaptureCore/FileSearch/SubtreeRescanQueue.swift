import Foundation

/// FSEvents 유실 알림(`MustScanSubDirs`)으로 생긴 하위 트리 재스캔을 모았다가 한 번에 처리하도록 계획한다
///
/// - 알림은 바로 처리하지 않고 대기 목록에 올린다. 같은 루트 트리 안에서 조상이 대기 중이면 자손은 합친다
/// - 재스캔을 시작한 시각(S)을 기록해 두고, S보다 먼저 받은 알림·변경은 이미 반영된 것으로 본다.
///   순서가 "변경 → 콜백(받은 시각) → S"라서, S 뒤에 디렉터리를 읽는 스캐너는 그 변경을 본다
/// - 루트가 다르면(중첩 루트) 서로 덮지 않는다. 바깥 루트 스캔은 안쪽 루트의 트리를 건드리지 않는다
/// - 유실 이벤트의 ID는 무엇을 가리키는지 정해져 있지 않아 판정에 쓰지 않는다
public struct SubtreeRescanQueue: Sendable {
    /// 재스캔할 경로와 그 경로가 속한 루트(가장 긴 루트)
    public struct Job: Sendable, Hashable {
        public let path: String
        public let root: String

        public init(path: String, root: String) {
            self.path = path
            self.root = root
        }
    }

    /// 덮임 기록을 이보다 많이 들고 있지 않는다 (경로별 하나라 보통 루트 수 정도)
    static let coverageLimit = 512

    private var pending: Set<Job> = []
    private var firstNotedAt: ContinuousClock.Instant?
    private var lastNotedAt: ContinuousClock.Instant?
    /// 대기 목록에 반영된 알림 수 (합쳐진 것 포함, 로그용)
    public private(set) var noteCount = 0
    /// 경로별로 가장 최근 재스캔 시작 시각
    private var coverage: [Job: ContinuousClock.Instant] = [:]

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }

    /// 유실 알림을 대기 목록에 올린다. 이미 반영된 알림이면 무시하고 false를 돌려준다
    public mutating func note(path: String, root: String, receivedAt: ContinuousClock.Instant) -> Bool {
        guard !isCovered(path: path, root: root, receivedAt: receivedAt) else { return false }
        noteCount += 1
        firstNotedAt = min(firstNotedAt ?? receivedAt, receivedAt)
        lastNotedAt = max(lastNotedAt ?? receivedAt, receivedAt)
        guard !isPending(path: path, root: root) else { return true }
        // 새 경로가 대기 중인 자손을 덮으면 자손은 뺀다
        pending = pending.filter { $0.root != root || !Self.contains(path, $0.path) }
        pending.insert(Job(path: path, root: root))
        return true
    }

    /// 같은 루트 트리 안에서 자기 또는 조상 경로가 대기 중인지 (곧 다시 스캔하므로 개별 반영이 필요 없다)
    public func isPending(path: String, root: String) -> Bool {
        pending.contains { $0.root == root && Self.contains($0.path, path) }
    }

    /// receivedAt에 받은 변경이 그 뒤에 시작한 재스캔으로 이미 반영됐는지
    public func isCovered(path: String, root: String, receivedAt: ContinuousClock.Instant) -> Bool {
        coverage.contains { job, startedAt in
            job.root == root && receivedAt < startedAt && Self.contains(job.path, path)
        }
    }

    /// 재스캔할 시각. 마지막 알림 뒤 quiet만큼 조용하거나, 첫 알림 뒤 maxDelay가 지나면(계속 오더라도) 실행한다
    public func deadline(quiet: Duration, maxDelay: Duration) -> ContinuousClock.Instant? {
        guard let firstNotedAt, let lastNotedAt, !pending.isEmpty else { return nil }
        return min(lastNotedAt + quiet, firstNotedAt + maxDelay)
    }

    /// 대기 중인 작업을 모두 꺼낸다 (경로 순서로 정렬). 꺼낸 뒤 오는 알림은 새 대기 목록에 쌓인다
    public mutating func takeJobs() -> (jobs: [Job], notes: Int) {
        let jobs = pending.sorted { ($0.root, $0.path) < ($1.root, $1.path) }
        let notes = noteCount
        pending.removeAll()
        firstNotedAt = nil
        lastNotedAt = nil
        noteCount = 0
        return (jobs, notes)
    }

    /// 재스캔을 startedAt에 시작했음을 기록한다. 이보다 먼저 받은 같은 트리의 알림·변경은 이후 무시된다
    public mutating func complete(_ job: Job, startedAt: ContinuousClock.Instant) {
        coverage[job] = max(coverage[job] ?? startedAt, startedAt)
        if coverage.count > Self.coverageLimit, let oldest = coverage.min(by: { $0.value < $1.value })?.key {
            coverage[oldest] = nil
        }
    }

    // ancestor가 path 자신이거나 조상인지 ("/" 루트 포함)
    static func contains(_ ancestor: String, _ path: String) -> Bool {
        if path == ancestor { return true }
        return path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
    }
}
