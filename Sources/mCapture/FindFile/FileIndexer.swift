import CoreServices
import Foundation
import MCaptureCore
import Synchronization

/// 파일 찾기 인덱스의 주인. 인덱스 값을 가지고 스캔·FSEvents 반영·스냅샷 저장을 맡는다
///
/// - 파일 I/O(스캔, 디렉터리 읽기, 스냅샷 읽기·쓰기)는 액터 밖 큐에서 하고, 액터 안에서는 메모리 연산만 한다.
///   그래서 I/O를 기다리는 동안에도 검색 쪽 `snapshot()`이 바로 응답한다
/// - 검색은 `snapshot()`이 돌려준 값(쓰기 전까지 배열 공유)을 액터 밖에서 병렬로 훑는다
/// - 설정을 바꾸거나 다시 만들 때마다 generation을 올려, 기다리던 이전 작업의 결과는 버린다
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

    /// 디버그·설정 표시용 통계
    struct Stats: Sendable {
        let status: Status
        let count: Int
        let liveCount: Int
        let removedCount: Int
        let estimatedBytes: Int
        let nameBytes: Int
        let lastEventId: UInt64
        let lastScan: ScanReport?
        let deniedPaths: [String]
        let roots: [String]
    }

    private var index = FileIndex()
    private(set) var status: Status = .idle
    private var configuration: Configuration?
    private var lastEventId: FSEventStreamEventId = 0
    private var deviceUUIDs: [String] = []
    private var isReplaying = false
    private var unsavedChanges = false
    private var lastSaved = Date.distantPast
    private var watcher: FileEventWatcher?
    private var eventTask: Task<Void, Never>?
    private var scanCancellation: ScanCancellation?
    private var generation = 0
    private(set) var deniedPaths: [String] = []
    private var lastScan: ScanReport?
    private var statusHandler: (@Sendable (Status) -> Void)?
    private let snapshotURL: URL
    /// 바뀐 상태로 이만큼 지나면 저장한다 (SSD 쓰기를 줄이려 주기 저장은 하지 않는다)
    private let saveInterval: TimeInterval = 3600

    init(snapshotURL: URL) {
        self.snapshotURL = snapshotURL
    }

    /// 상태가 바뀔 때 부를 콜백 (액터 밖 스레드에서 불릴 수 있다)
    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    /// 검색용 인덱스 값. 복사 없이 배열을 공유한다
    func snapshot() -> FileIndex {
        index
    }

    func stats() -> Stats {
        Stats(status: status, count: index.count, liveCount: index.liveCount, removedCount: index.removedCount,
              estimatedBytes: index.estimatedBytes, nameBytes: index.nameByteCount, lastEventId: lastEventId,
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
        if changed { finishChanges() }
    }

    /// 바뀐 내용이 있으면 스냅샷을 저장한다 (종료할 때)
    func saveIfNeeded() async {
        await save()
    }

    // 새 작업 세대를 시작한다: 감시와 진행 중인 스캔을 멈춘다
    private func beginGeneration() -> Int {
        generation += 1
        scanCancellation?.cancel()
        scanCancellation = nil
        eventTask?.cancel()
        eventTask = nil
        watcher?.stop()
        watcher = nil
        isReplaying = false
        return generation
    }

    // MARK: - 전체 스캔

    // 전용 큐에서 루트 전체를 스캔해 인덱스를 바꾸고, 스캔 직전 이벤트 ID부터 감시를 시작한다
    private func fullScan(generation current: Int, uuids: [String]) async {
        guard let configuration else { return }
        let since = FileEventWatcher.currentEventId
        let cancellation = ScanCancellation()
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
        unsavedChanges = true
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

    // since 이후의 기록부터 감시하고, 이벤트 묶음을 받은 순서대로 처리한다
    private func startWatching(since: FSEventStreamEventId, generation current: Int) {
        guard let configuration else { return }
        guard let watcher = FileEventWatcher(paths: configuration.roots, since: since, exclusions: configuration.rules.paths) else {
            Log.findFile.error("FSEvents 감시 시작 실패")
            setStatus(.failed("변경 감시를 시작하지 못했습니다"))
            return
        }
        self.watcher = watcher
        eventTask = Task { [weak self] in
            for await batch in watcher.events {
                guard let self else { return }
                await self.handle(batch, generation: current)
            }
        }
    }

    // 이벤트 묶음을 "다시 맞출 디렉터리"로 모아 인덱스에 반영한다
    private func handle(_ events: [FileEvent], generation current: Int) async {
        guard current == generation, let configuration else { return }
        let start = ContinuousClock.now
        var dirty = Set<String>()
        var subtrees = Set<String>()
        var fullRescan = false
        var historyDone = false
        var maxId = lastEventId
        let itemChanges = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        let itemAny = itemChanges | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod
            | kFSEventStreamEventFlagItemXattrMod | kFSEventStreamEventFlagItemChangeOwner | kFSEventStreamEventFlagItemFinderInfoMod
            | kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemIsSymlink
            | kFSEventStreamEventFlagItemCloned

        for event in events {
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
                subtrees.insert(path)
            } else if event.has(itemChanges) {
                // 생성·삭제·이름 변경: 이름 목록이 바뀐 건 부모 디렉터리다
                let parent = path == root ? path : (path as NSString).deletingLastPathComponent
                if !configuration.rules.isInsideExcludedArea(parent, root: root) { dirty.insert(parent) }
            } else if event.flags & FSEventStreamEventFlags(itemAny) == 0 {
                // 항목 정보 없는 디렉터리 단위 이벤트
                if !configuration.rules.isInsideExcludedArea(path, root: root) { dirty.insert(path) }
            }
            // 내용·속성만 바뀐 이벤트는 이름이 그대로라 무시한다
        }

        if fullRescan {
            Log.findFile.info("루트 변경 또는 이벤트 ID 순환으로 다시 스캔")
            await rebuild()
            return
        }
        let before = (index.count, index.removedCount)
        for path in subtrees {
            _ = await rescanSubtree(path, generation: current)
            guard current == generation else { return }
        }
        dirty = dirty.filter { path in !subtrees.contains { path == $0 || path.hasPrefix($0 + "/") } }
        await reconcile(dirty, generation: current)
        guard current == generation else { return }

        lastEventId = max(lastEventId, maxId)
        let changed = before != (index.count, index.removedCount)
        if changed {
            Log.findFile.debug("변경 반영: 이벤트 \(events.count)건, 디렉터리 \(dirty.count)개, 하위 트리 \(subtrees.count)개, \((ContinuousClock.now - start).milliseconds, format: .fixed(precision: 1))ms")
        }
        if historyDone {
            isReplaying = false
            Log.findFile.info("기록 재생 끝: 항목 \(self.index.liveCount)개")
        }
        if changed || historyDone {
            unsavedChanges = unsavedChanges || changed
            finishChanges()
        }
        if index.needsCompaction {
            index.compact()
        }
        if unsavedChanges, historyDone || Date().timeIntervalSince(lastSaved) > saveInterval {
            await save()
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
            toScan += DirectoryReconciler.apply(listing, to: id, in: &index).map { ($0, index.path(of: $0)) }
        }
        guard !toScan.isEmpty else { return }
        let scanJobs = toScan
        let subtrees = await Self.run(.utility) {
            scanJobs.map { ($0.id, FileTreeScanner.scanSubtree(path: $0.path, rules: rules)) }
        }
        guard current == generation else { return }
        for (id, sub) in subtrees where !index.isRemoved(id) {
            index.graft(sub.index, onto: id)
            deniedPaths += sub.report.deniedPaths
        }
    }

    // 경로 아래를 통째로 다시 스캔한다 (MustScanSubDirs, 권한 재시도). 바뀌었으면 true
    private func rescanSubtree(_ path: String, generation current: Int) async -> Bool {
        guard let rules = configuration?.rules, let (id, resolved) = nearestIndexedEntry(path) else { return false }
        let flags = index.flags(of: id)
        guard flags.contains(.directory), !flags.contains(.unindexed) else { return false }
        let sub = await Self.run(.utility) { FileTreeScanner.scanSubtree(path: resolved, rules: rules) }
        guard current == generation, !index.isRemoved(id) else { return false }
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

    // 스냅샷을 임시 파일에 0600 권한으로 쓴 뒤 이름을 바꿔 원자적으로 저장한다
    private func save() async {
        guard let configuration, unsavedChanges else { return }
        let snapshot = FileIndexSnapshot(index: index, configHash: configuration.hash, lastEventId: lastEventId, deviceUUIDs: deviceUUIDs)
        let url = snapshotURL
        let start = ContinuousClock.now
        let bytes = await Self.run(.utility) { Self.write(snapshot, to: url) }
        if let bytes {
            unsavedChanges = false
            lastSaved = Date()
            Log.findFile.info("스냅샷 저장 \(bytes / 1000)KB, \((ContinuousClock.now - start).milliseconds, format: .fixed(precision: 0))ms")
        }
    }

    // 파일에 쓰고 바이트 수를 돌려준다. 실패하면 nil
    private static func write(_ snapshot: FileIndexSnapshot, to url: URL) -> Int? {
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = snapshot.encoded()
            let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return nil
            }
            guard rename(temporary.path, url.path) == 0 else {
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            return data.count
        } catch {
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
}

/// 스캔 스레드가 읽는 취소 표시
final class ScanCancellation: Sendable {
    private let flag = Atomic<Bool>(false)

    var isCancelled: Bool { flag.load(ordering: .relaxed) }

    func cancel() {
        flag.store(true, ordering: .relaxed)
    }
}
