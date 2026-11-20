import CoreServices
import Foundation
import MCaptureCore

/// 파일 찾기 인덱스의 주인. 인덱스 값을 가지고 스캔·FSEvents 반영·스냅샷 저장을 맡는다
///
/// - 파일 I/O(스캔, 디렉터리 읽기, 스냅샷 읽기·쓰기)는 액터 밖 큐에서 하고, 액터 안에서는 메모리 연산만 한다.
///   그래서 I/O를 기다리는 동안에도 검색 쪽 `snapshot()`이 바로 응답한다
/// - 검색은 `snapshot()`이 돌려준 값(쓰기 전까지 배열 공유)을 액터 밖에서 병렬로 훑는다
/// - 설정을 바꾸거나 다시 만들 때마다 generation을 올려, 기다리던 이전 작업의 결과는 버린다
/// - FSEvents 묶음과 유실 재스캔은 입력 하나에서 순서대로 처리한다. 재스캔의 graft가 다른 묶음의 반영과 섞이지 않는다
actor FileIndexer {
    enum Status: Sendable, Equatable {
        /// 꺼짐
        case idle
        case loading
        /// 전체 스캔 중 (지금까지 항목 수)
        case scanning(Int)
        /// 스냅샷을 불러와 꺼져 있던 동안의 변경을 재생하는 중 (검색은 가능)
        case replaying(count: Int)
        case ready(count: Int, updatedAt: Date)
        case failed(String)
    }

    struct Configuration: Sendable, Equatable {
        let roots: [String]
        let rules: ExclusionRules

        var hash: UInt64 { rules.configHash(roots: roots) }
    }

    /// FSEvents 유실 알림(`MustScanSubDirs`)으로 하는 재스캔의 시점·우선순위
    struct RescanTiming: Sendable {
        /// 마지막 유실 알림 뒤 이만큼 조용하면 재스캔한다 (폭주 동안 오는 알림을 한 번으로 합친다)
        var quiet: Duration
        /// 알림이 계속 와도 첫 알림 뒤 이만큼 지나면 재스캔한다
        var maxDelay: Duration
        /// 재스캔을 돌릴 큐 우선순위. background는 E코어·I/O 스로틀로 같은 스캔이 약 5배 느리고
        /// CPU 시간도 더 들어(실측 루트 3곳 1.5초 → 7~9초) 다시 맞추기와 같은 utility를 쓴다
        var qos: DispatchQoS.QoSClass

        static let standard = RescanTiming(quiet: .seconds(3), maxDelay: .seconds(30), qos: .utility)
    }

    /// 디버그·설정 표시용 통계
    struct Stats: Sendable {
        let status: Status
        let count: Int
        let liveCount: Int
        let removedCount: Int
        let estimatedBytes: Int
        let nameBytes: Int
        let lastEventId: UInt64
        /// 스냅샷에 저장할 이벤트 ID (유실 재스캔을 기다리는 동안은 lastEventId보다 작다)
        let persistedEventId: UInt64
        /// 재스캔을 기다리는 경로 수
        let pendingRescans: Int
        /// 지금까지 유실 때문에 다시 스캔한 경로 수
        let subtreeRescans: Int
        let lastScan: ScanReport?
        let deniedPaths: [String]
        let roots: [String]
    }

    // 처리 순서를 지키는 입력 하나: FSEvents 묶음과 "재스캔할 때가 됐다" 신호
    private enum Input: Sendable {
        case batch(FileEventBatch)
        case rescanDue
    }

    private var index = FileIndex()
    private(set) var status: Status = .idle
    private var configuration: Configuration?
    private var lastEventId: FSEventStreamEventId = 0
    /// 유실 재스캔을 기다리는 동안 저장할 이벤트 ID. 대기 중에 종료되면 다음 실행이 유실 이전부터 다시 재생한다
    private var frozenEventId: FSEventStreamEventId?
    private var deviceUUIDs: [String] = []
    private var isReplaying = false
    private var unsavedChanges = false
    private var changeVersion = 0
    private var saveTask: Task<Void, Never>?
    private let beforeSnapshotWrite: @Sendable () async -> Void
    private var lastSaved = Date.distantPast
    private var watcher: FileEventWatcher?
    private var eventTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?
    private var input: AsyncStream<Input>.Continuation?
    private var rescanTimer: Task<Void, Never>?
    private var rescans = SubtreeRescanQueue()
    private var rescanCancellation: CancellationFlag?
    private var subtreeRescanCount = 0
    private var scanCancellation: CancellationFlag?
    private var generation = 0
    private(set) var deniedPaths: [String] = []
    private var lastScan: ScanReport?
    private var statusHandler: (@Sendable (Status) -> Void)?
    private let snapshotURL: URL
    private let timing: RescanTiming
    /// 바뀐 상태로 이만큼 지나면 저장한다 (SSD 쓰기를 줄이려 주기 저장은 하지 않는다)
    private let saveInterval: TimeInterval = 3600

    init(snapshotURL: URL, timing: RescanTiming = .standard, beforeSnapshotWrite: @escaping @Sendable () async -> Void = {}) {
        self.beforeSnapshotWrite = beforeSnapshotWrite
        self.snapshotURL = snapshotURL
        self.timing = timing
    }

    /// 상태가 바뀔 때 부를 콜백 (액터 밖 스레드에서 불릴 수 있다)
    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    #if SEARCH_BENCHMARK_APP
    func setBenchmarkIndex(_ value: FileIndex) { index = value }
    #endif

    /// 검색용 인덱스 값. 복사 없이 배열을 공유한다
    func snapshot() -> FileIndex {
        index
    }

    func stats() -> Stats {
        Stats(status: status, count: index.count, liveCount: index.liveCount, removedCount: index.removedCount,
              estimatedBytes: index.estimatedBytes, nameBytes: index.nameByteCount, lastEventId: lastEventId,
              persistedEventId: persistedEventId, pendingRescans: rescans.count, subtreeRescans: subtreeRescanCount,
              lastScan: lastScan, deniedPaths: deniedPaths, roots: configuration?.roots ?? [])
    }

    // MARK: - 시작·중지

    /// 설정으로 시작한다. 같은 설정으로 이미 돌고 있으면 그대로 둔다
    /// 스냅샷이 맞으면 불러와 꺼져 있던 동안의 기록을 재생하고, 아니면 처음부터 스캔한다
    func start(_ configuration: Configuration) async {
        if self.configuration == configuration, status != .idle { return }
        let current = beginGeneration()
        self.configuration = configuration
        setStatus(.loading)

        let hash = configuration.hash
        let url = snapshotURL
        let uuids = configuration.roots.map { FileEventWatcher.deviceUUID(for: $0) ?? "" }
        let start = ContinuousClock.now
        let loaded = await Self.run(.utility) { () -> FileIndexSnapshot? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return FileIndexSnapshot.decode(data, expectedConfigHash: hash)
        }
        guard current == generation else { return }

        if let loaded, loaded.deviceUUIDs == uuids, loaded.lastEventId > 0 {
            index = loaded.index
            lastEventId = loaded.lastEventId
            deviceUUIDs = uuids
            lastSaved = loaded.savedAt
            Log.findFile.info("스냅샷 로드 \(self.index.liveCount)개, \((ContinuousClock.now - start).milliseconds, format: .fixed(precision: 0))ms, 기록 재생 시작 id \(loaded.lastEventId)")
            isReplaying = true
            setStatus(.replaying(count: index.liveCount))
            startWatching(since: lastEventId, generation: current)
        } else {
            if loaded != nil { Log.findFile.info("스냅샷의 장치가 달라 다시 스캔") }
            await fullScan(generation: current, uuids: uuids)
        }
    }

    /// 감시를 멈추고 인덱스를 비운다. deleteSnapshot이면 저장한 스냅샷도 지운다 (기능을 끌 때)
    func stop(deleteSnapshot: Bool) {
        _ = beginGeneration()
        index = FileIndex()
        configuration = nil
        unsavedChanges = false
        setStatus(.idle)
        if deleteSnapshot {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
    }

    /// 처음부터 다시 스캔한다 (설정의 "다시 만들기")
    func rebuild() async {
        guard configuration != nil else { return }
        let current = beginGeneration()
        let uuids = configuration?.roots.map { FileEventWatcher.deviceUUID(for: $0) ?? "" } ?? []
        await fullScan(generation: current, uuids: uuids)
    }

    /// 거부됐던 폴더 중 이제 읽을 수 있는 것만 다시 스캔한다 (설정 창·패널을 열 때)
    func retryDeniedFolders() async {
        guard configuration != nil else { return }
        let readable = deniedPaths.filter(FileAccessPermission.canRead)
        guard !readable.isEmpty else { return }
        deniedPaths.removeAll { readable.contains($0) }
        let current = generation
        var changed = false
        for path in readable {
            changed = await rescanSubtree(path, generation: current) || changed
        }
        if current == generation, changed { markChanged(); finishChanges() }
    }

    /// 디렉터리 하나를 실제 목록과 다시 맞춘다 (결과를 열려는데 파일이 없을 때)
    func refresh(directory path: String) async {
        await refresh(directories: [path])
    }

    /// 여러 디렉터리를 한 번에 실제 목록과 다시 맞춘다 (휴지통으로 옮긴 항목의 부모 폴더들)
    /// FSEvents가 뒤따라 같은 폴더를 반영해도 결과는 같다(멱등)
    func refresh(directories paths: Set<String>) async {
        let current = generation
        let before = (index.count, index.removedCount)
        await reconcile(Set(paths.map(HangulText.nfc)), generation: current)
        if current == generation, before != (index.count, index.removedCount) {
            markChanged()
            finishChanges()
        }
    }

    /// 바뀐 내용이 있으면 스냅샷을 저장한다 (종료할 때)
    func saveIfNeeded() async {
        await save()
    }

    // 새 작업 세대를 시작한다: 감시·입력·타이머와 진행 중인 스캔을 멈추고 유실 대기 목록을 비운다
    private func beginGeneration() -> Int {
        generation += 1
        unsavedChanges = false
        scanCancellation?.cancel()
        scanCancellation = nil
        rescanCancellation?.cancel()
        rescanCancellation = nil
        rescanTimer?.cancel()
        rescanTimer = nil
        forwardTask?.cancel()
        forwardTask = nil
        input?.finish()
        input = nil
        eventTask?.cancel()
        eventTask = nil
        watcher?.stop()
        watcher = nil
        rescans = SubtreeRescanQueue()
        frozenEventId = nil
        isReplaying = false
        return generation
    }

    // MARK: - 전체 스캔

    // 전용 큐에서 루트 전체를 스캔해 인덱스를 바꾸고, 스캔 직전 이벤트 ID부터 감시를 시작한다
    private func fullScan(generation current: Int, uuids: [String]) async {
        guard let configuration else { return }
        let since = FileEventWatcher.currentEventId
        let cancellation = CancellationFlag()
        scanCancellation = cancellation
        setStatus(.scanning(0))
        let handler = statusHandler
        let (scanned, report) = await Self.run(.background) {
            FileTreeScanner.scan(roots: configuration.roots, rules: configuration.rules,
                                 progress: { handler?(.scanning($0)) }, isCancelled: { cancellation.isCancelled })
        }
        guard current == generation else { return }
        scanCancellation = nil
        index = scanned
        lastScan = report
        deniedPaths = report.deniedPaths
        lastEventId = since
        deviceUUIDs = uuids
        markChanged()
        Log.findFile.info("""
            전체 스캔 \(report.entries)개(디렉터리 \(report.directories)), \(report.elapsed.milliseconds, format: .fixed(precision: 0))ms, \
            이름 평균 \(scanned.nameByteCount / max(1, scanned.count))바이트, 약 \(scanned.estimatedBytes / 1_000_000)MB, 거부 \(report.deniedPaths.count)개
            """)
        if !report.missingRoots.isEmpty {
            Log.findFile.info("없는 루트: \(report.missingRoots.joined(separator: ", "), privacy: .public)")
        }
        setStatus(.ready(count: index.liveCount, updatedAt: Date()))
        await save()
        guard current == generation else { return }
        startWatching(since: since, generation: current)
    }

    // MARK: - FSEvents

    // since 이후의 기록부터 감시하고, 이벤트 묶음과 재스캔 신호를 입력 하나로 모아 받은 순서대로 처리한다
    private func startWatching(since: FSEventStreamEventId, generation current: Int) {
        guard let configuration else { return }
        let exclusions = configuration.rules.eventExclusions(roots: configuration.roots)
        guard let watcher = FileEventWatcher(paths: configuration.roots, since: since, exclusions: exclusions) else {
            Log.findFile.error("FSEvents 감시 시작 실패")
            setStatus(.failed("변경 감시를 시작하지 못했습니다"))
            return
        }
        self.watcher = watcher
        let (stream, continuation) = AsyncStream<Input>.makeStream()
        input = continuation
        // 감시기가 아니라 스트림만 붙잡아, 감시기 해제를 막지 않는다
        let events = watcher.events
        forwardTask = Task {
            for await batch in events { continuation.yield(.batch(batch)) }
        }
        eventTask = Task { [weak self] in
            for await item in stream {
                guard let self else { return }
                switch item {
                case .batch(let batch): await self.handle(batch, generation: current)
                case .rescanDue: await self.runDueRescans(generation: current)
                }
            }
        }
    }

    // 이벤트 묶음을 "다시 맞출 디렉터리"로 모아 인덱스에 반영한다. 유실 알림은 대기 목록에만 올린다
    private func handle(_ batch: FileEventBatch, generation current: Int) async {
        guard current == generation, let configuration else { return }
        let start = ContinuousClock.now
        var dirty: [String: String] = [:]
        var fullRescan = false
        var historyDone = false
        var noted = 0
        var covered = 0
        var maxId = lastEventId
        let itemChanges = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        let itemAny = itemChanges | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod
            | kFSEventStreamEventFlagItemXattrMod | kFSEventStreamEventFlagItemChangeOwner | kFSEventStreamEventFlagItemFinderInfoMod
            | kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemIsSymlink
            | kFSEventStreamEventFlagItemCloned

        for event in batch.events {
            if event.has(kFSEventStreamEventFlagHistoryDone) {
                historyDone = true
                continue
            }
            maxId = max(maxId, event.id)
            if event.has(kFSEventStreamEventFlagRootChanged) || event.has(kFSEventStreamEventFlagEventIdsWrapped) {
                fullRescan = true
                continue
            }
            let path = Self.normalized(event.path)
            guard let root = Self.root(containing: path, in: configuration.roots) else { continue }
            if event.has(kFSEventStreamEventFlagMustScanSubDirs) {
                // 바로 스캔하지 않고 모은다. 대기가 처음 생기면 저장할 이벤트 ID를 이 묶음 이전 값에 묶는다
                let wasEmpty = rescans.isEmpty
                if rescans.note(path: path, root: root, receivedAt: batch.receivedAt) {
                    noted += 1
                    if wasEmpty { frozenEventId = lastEventId }
                } else {
                    covered += 1
                }
            } else if event.has(itemChanges) {
                // 생성·삭제·이름 변경: 이름 목록이 바뀐 건 부모 디렉터리다
                let parent = path == root ? path : (path as NSString).deletingLastPathComponent
                if !configuration.rules.isInsideExcludedArea(parent, root: root) { dirty[parent] = root }
            } else if event.flags & FSEventStreamEventFlags(itemAny) == 0 {
                // 항목 정보 없는 디렉터리 단위 이벤트
                if !configuration.rules.isInsideExcludedArea(path, root: root) { dirty[path] = root }
            }
            // 내용·속성만 바뀐 이벤트는 이름이 그대로라 무시한다
        }

        if fullRescan {
            Log.findFile.info("루트 변경 또는 이벤트 ID 순환으로 다시 스캔")
            await rebuild()
            return
        }
        let before = (index.count, index.removedCount)
        // 곧 다시 스캔할 트리나 이 묶음 뒤에 이미 다시 스캔한 트리 안의 디렉터리는 따로 맞추지 않는다
        let targets = Set(dirty.filter { path, root in
            !rescans.isPending(path: path, root: root) && !rescans.isCovered(path: path, root: root, receivedAt: batch.receivedAt)
        }.keys)
        await reconcile(targets, generation: current)
        guard current == generation else { return }

        if maxId > lastEventId {
            lastEventId = maxId
            if frozenEventId == nil { markChanged() }
        }
        let changed = before != (index.count, index.removedCount)
        if changed || noted > 0 || covered > 0 {
            Log.findFile.debug("변경 반영: 이벤트 \(batch.events.count)건, 디렉터리 \(targets.count)개, 유실 알림 \(noted)건(이미 반영 \(covered)건), \((ContinuousClock.now - start).milliseconds, format: .fixed(precision: 1))ms")
        }
        if historyDone {
            isReplaying = false
            Log.findFile.info("기록 재생 끝: 항목 \(self.index.liveCount)개")
        }
        if changed || historyDone {
            if changed { markChanged() }
            finishChanges()
        }
        if !rescans.isEmpty { scheduleRescan() }
        if index.needsCompaction {
            index.compact()
        }
        if unsavedChanges, historyDone || Date().timeIntervalSince(lastSaved) > saveInterval {
            await save()
        }
    }

    // 대기 목록의 마감 시각에 재스캔 신호를 입력에 넣는다 (새 알림이 오면 다시 건다)
    private func scheduleRescan() {
        guard let input, let deadline = rescans.deadline(quiet: timing.quiet, maxDelay: timing.maxDelay) else { return }
        rescanTimer?.cancel()
        rescanTimer = Task {
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            input.yield(.rescanDue)
        }
    }

    // 마감이 지났으면 대기 중인 경로를 한 번씩 다시 스캔한다. 시작 시각을 기록해 그 전에 받은 알림·변경은 이후 건너뛴다
    private func runDueRescans(generation current: Int) async {
        guard current == generation, configuration != nil,
              let deadline = rescans.deadline(quiet: timing.quiet, maxDelay: timing.maxDelay) else { return }
        guard ContinuousClock.now >= deadline else {
            scheduleRescan()
            return
        }
        let (jobs, notes) = rescans.takeJobs()
        let began = ContinuousClock.now
        let before = (index.count, index.removedCount)
        let cancellation = CancellationFlag()
        rescanCancellation = cancellation
        for job in jobs {
            let startedAt = ContinuousClock.now
            _ = await rescanSubtree(job.path, qos: timing.qos, cancellation: cancellation, generation: current)
            guard current == generation else { return }
            rescans.complete(job, startedAt: startedAt)
            subtreeRescanCount += 1
        }
        rescanCancellation = nil
        Log.findFile.info("유실 반영 재스캔 \(jobs.count)곳(알림 \(notes)건), \((ContinuousClock.now - began).milliseconds, format: .fixed(precision: 0))ms")
        // 재스캔 중에는 입력을 처리하지 않으므로 대기 목록은 비어 있다. 묶어 둔 저장 ID를 푼다
        if rescans.isEmpty, frozenEventId != nil {
            frozenEventId = nil
            markChanged()
        }
        if before != (index.count, index.removedCount) {
            markChanged()
            finishChanges()
        }
        if index.needsCompaction {
            index.compact()
        }
    }

    // 상태를 갱신한다 (재생 중이면 재생 상태 유지)
    private func finishChanges() {
        setStatus(isReplaying ? .replaying(count: index.liveCount) : .ready(count: index.liveCount, updatedAt: Date()))
    }

    // 디렉터리들의 실제 목록을 읽어(I/O) 인덱스와 맞추고, 새로 생긴 디렉터리는 스캔해 붙인다
    private func reconcile(_ paths: Set<String>, generation current: Int) async {
        guard let rules = configuration?.rules else { return }
        var targets: [UInt32: String] = [:]
        for path in paths {
            guard let (id, resolved) = nearestIndexedEntry(path) else { continue }
            let flags = index.flags(of: id)
            guard flags.contains(.directory), !flags.contains(.unindexed) else { continue }
            targets[id] = resolved
        }
        guard !targets.isEmpty else { return }

        let jobs = Array(targets)
        let listings = await Self.run(.utility) {
            jobs.map { id, path in (id, try? DirectoryReconciler.list(directory: path, rules: rules)) }
        }
        guard current == generation else { return }
        var toScan: [(id: UInt32, path: String)] = []
        for (id, listing) in listings where !index.isRemoved(id) {
            // 목록을 못 읽으면(디렉터리가 사라짐) 부모 쪽 이벤트가 처리한다
            guard let listing else { continue }
            markChanged()
            toScan += DirectoryReconciler.apply(listing, to: id, in: &index).map { ($0, index.path(of: $0)) }
        }
        guard !toScan.isEmpty else { return }
        let scanJobs = toScan
        let subtrees = await Self.run(.utility) {
            scanJobs.map { ($0.id, FileTreeScanner.scanSubtree(path: $0.path, rules: rules)) }
        }
        guard current == generation else { return }
        for (id, sub) in subtrees where !index.isRemoved(id) {
            markChanged()
            index.graft(sub.index, onto: id)
            deniedPaths += sub.report.deniedPaths
        }
    }

    // 경로 아래를 통째로 다시 스캔한다 (FSEvents 유실, 권한 재시도). 바뀌었으면 true
    // 취소되면(세대 교체) 불완전한 결과를 버린다
    private func rescanSubtree(_ path: String, qos: DispatchQoS.QoSClass = .utility, cancellation: CancellationFlag? = nil,
                               generation current: Int) async -> Bool {
        guard let rules = configuration?.rules, let (id, resolved) = nearestIndexedEntry(path) else { return false }
        let flags = index.flags(of: id)
        guard flags.contains(.directory), !flags.contains(.unindexed) else { return false }
        let sub = await Self.run(qos) {
            FileTreeScanner.scanSubtree(path: resolved, rules: rules, isCancelled: { cancellation?.isCancelled ?? false })
        }
        guard current == generation, !index.isRemoved(id), cancellation?.isCancelled != true else { return false }
        markChanged()
        index.removeChildren(of: id)
        index.graft(sub.index, onto: id)
        deniedPaths += sub.report.deniedPaths
        return true
    }

    // 경로가 인덱스에 없으면 가장 가까운 조상을 찾는다 (새로 생긴 디렉터리는 부모 목록에서 추가된다)
    private func nearestIndexedEntry(_ path: String) -> (UInt32, String)? {
        var current = path
        while true {
            if let id = index.lookup(path: current) { return (id, current) }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }

    // MARK: - 저장

    // 스냅샷에 저장할 이벤트 ID. 유실 재스캔을 기다리는 동안은 대기 직전 값이다
    private var persistedEventId: FSEventStreamEventId {
        frozenEventId ?? lastEventId
    }

    private func markChanged() {
        changeVersion += 1
        unsavedChanges = true
    }

    // 모든 호출자는 같은 저장 작업을 기다린다. 저장 중 바뀐 최신 버전까지 비운다.
    private func save() async {
        if let saveTask { await saveTask.value; return }
        let task = Task { await self.drainSaves() }
        saveTask = task
        await task.value
    }

    private func drainSaves() async {
        defer { saveTask = nil }
        while let configuration, unsavedChanges {
            let current = generation
            let version = changeVersion
            let snapshot = FileIndexSnapshot(index: index, configHash: configuration.hash, lastEventId: persistedEventId, deviceUUIDs: deviceUUIDs)
            let url = snapshotURL
            await beforeSnapshotWrite()
            let temporary = await Self.run(.utility) { Self.stage(snapshot, to: url) }
            guard let temporary else { return }
            defer { try? FileManager.default.removeItem(at: temporary) }
            // 검사와 rename 사이에는 액터를 양보하지 않는다.
            guard current == generation else { continue }
            guard rename(temporary.path, url.path) == 0 else { return }
            lastSaved = Date()
            if version == changeVersion { unsavedChanges = false }
        }
    }

    // 백그라운드는 임시 파일만 쓴다. 최종 경로는 액터에서만 교체한다.
    private static func stage(_ snapshot: FileIndexSnapshot, to url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: temporary.path, contents: snapshot.encoded(), attributes: [.posixPermissions: 0o600]) else {
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            return temporary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            Log.findFile.error("스냅샷 저장 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - 도우미

    // 상태를 바꾸고 콜백으로 알린다
    private func setStatus(_ status: Status) {
        self.status = status
        statusHandler?(status)
    }

    // 동기 작업을 지정한 QoS의 전역 큐에서 돌리고 결과를 기다린다 (협력 스레드 풀을 동기 I/O로 막지 않는다)
    private static func run<T: Sendable>(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(returning: work())
            }
        }
    }

    // FSEvents 경로를 NFC로 맞추고 끝의 /를 뗀다
    private static func normalized(_ path: String) -> String {
        var path = HangulText.nfc(path)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    // 경로를 담은 루트 (가장 긴 것)
    private static func root(containing path: String, in roots: [String]) -> String? {
        roots.filter { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }.max { $0.count < $1.count }
    }

    #if DEBUG
    /// 시험용: 실제 FSEvents 대신 이벤트 묶음을 입력에 넣는다 (감시 중일 때만)
    func enqueueForTesting(_ events: [FileEvent], receivedAt: ContinuousClock.Instant = .now) {
        input?.yield(.batch(FileEventBatch(events: events, receivedAt: receivedAt)))
    }
    #endif
}
