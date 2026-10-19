import AppKit
import MCaptureCore

/// 파일 찾기 기능의 진입점. 인덱서를 설정에 맞춰 켜고 끄며, 검색 패널과 결과 동작을 맡는다
@MainActor
final class FindFileController {
    private let preferences: Preferences
    private let exporter: Exporter
    let indexer: FileIndexer
    /// 인덱서의 최근 상태 (설정·패널 표시용)
    private(set) var status: FileIndexer.Status = .idle
    /// 상태가 바뀌면 부른다 (설정 창·패널이 구독)
    var onStatusChange: ((FileIndexer.Status) -> Void)?
    private var startTask: Task<Void, Never>?

    init(preferences: Preferences, exporter: Exporter) {
        self.preferences = preferences
        self.exporter = exporter
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppVariant.current.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("FileIndex", isDirectory: true)
        indexer = FileIndexer(snapshotURL: folder.appendingPathComponent("index.v1"))
        Task { [weak self, indexer] in
            await indexer.setStatusHandler { status in
                Task { @MainActor in self?.statusChanged(status) }
            }
        }
    }

    /// 지금 설정의 검색 폴더와 제외 규칙
    var configuration: FileIndexer.Configuration {
        let home = NSHomeDirectory()
        return FileIndexer.Configuration(
            roots: ExclusionRules.normalizedRoots(preferences.findFileRoots, home: home),
            rules: ExclusionRules(text: preferences.findFileExclusions, home: home, includeHidden: preferences.findFileIncludeHidden)
        )
    }

    /// 앱 시작 직후의 경합을 피해 잠시 뒤 인덱싱을 시작한다 (설정에서 꺼져 있으면 하지 않는다)
    func startIndexingIfEnabled(after delay: Duration = .seconds(5)) {
        startTask?.cancel()
        startTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applyPreferences()
        }
    }

    /// 설정을 반영한다: 켜져 있으면 지금 설정으로 시작(같으면 그대로), 꺼져 있으면 멈추고 스냅샷을 지운다
    func applyPreferences() {
        let enabled = preferences.findFileEnabled
        let configuration = configuration
        Task { [indexer] in
            if enabled {
                await indexer.start(configuration)
            } else {
                await indexer.stop(deleteSnapshot: true)
            }
        }
    }

    /// 처음부터 다시 만든다
    func rebuild() {
        Task { [indexer] in await indexer.rebuild() }
    }

    /// 종료 전에 바뀐 내용을 저장한다
    func saveBeforeQuit() async {
        await indexer.saveIfNeeded()
    }

    // 인덱서 상태를 받아 보관하고, 처음 스캔이면 한 번 안내한다
    private func statusChanged(_ status: FileIndexer.Status) {
        if case .scanning(0) = status, !preferences.findFileFirstScanNotified {
            preferences.findFileFirstScanNotified = true
            ToastPanel.show("파일 찾기 인덱스를 처음 만듭니다. 폴더 접근 허용 창이 뜰 수 있습니다",
                            systemImage: "magnifyingglass", tint: .secondary, duration: .seconds(6))
        }
        self.status = status
        onStatusChange?(status)
    }

    // MARK: - 개발용

    #if DEBUG
    /// 인덱스 통계를 JSON으로 쓴다 (mcapture-dev://debug/find-stats?path=)
    func debugWriteStats(to url: URL) {
        Task { [indexer] in
            let stats = await indexer.stats()
            let json: [String: Any] = [
                "status": String(describing: stats.status),
                "count": stats.count,
                "liveCount": stats.liveCount,
                "removedCount": stats.removedCount,
                "estimatedBytes": stats.estimatedBytes,
                "nameBytes": stats.nameBytes,
                "lastEventId": stats.lastEventId,
                "scanEntries": stats.lastScan?.entries ?? -1,
                "scanMilliseconds": stats.lastScan?.elapsed.milliseconds ?? -1,
                "deniedPaths": stats.deniedPaths,
                "roots": stats.roots,
                "footprintBytes": Self.physicalFootprint,
            ]
            Self.writeJSON(json, to: url)
        }
    }

    /// 패널 없이 검색해 결과를 JSON으로 쓴다 (mcapture-dev://debug/find-query?q=&path=)
    func debugWriteQuery(_ text: String, to url: URL) {
        Task { [indexer] in
            let index = await indexer.snapshot()
            let start = ContinuousClock.now
            let results = await FileSearcher.search(SearchQuery(text, home: NSHomeDirectory()), in: index)
            let elapsed = (ContinuousClock.now - start).milliseconds
            let json: [String: Any] = [
                "query": text,
                "milliseconds": elapsed,
                "total": results.totalMatches,
                "hits": results.hits.prefix(50).map { ["path": $0.path, "score": $0.score, "highlights": $0.highlights] },
            ]
            Self.writeJSON(json, to: url)
        }
    }

    // JSON 파일로 쓴다
    private static func writeJSON(_ object: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // 이 프로세스의 실제 메모리 사용량 (Activity Monitor의 "메모리"와 같은 phys_footprint)
    private static var physicalFootprint: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : -1
    }
    #endif
}
