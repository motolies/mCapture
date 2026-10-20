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
    private var panel: FindFilePanel?
    private var searchTask: Task<Void, Never>?
    /// 마지막으로 검색한 (검색어, 조합 중) — 같은 알림이 겹쳐 와도 한 번만 검색한다
    private var lastSearch: (text: String, composing: Bool)?
    /// 패널을 열기 전 앞에 있던 앱. 결과를 열지 않고 닫으면 이 앱으로 포커스를 돌려준다
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?

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
        let rules = ExclusionRules(text: preferences.findFileExclusions, home: home, includeHidden: preferences.findFileIncludeHidden)
        return FileIndexer.Configuration(roots: rules.normalizedRoots(preferences.findFileRoots, home: home), rules: rules)
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

    // 인덱서 상태를 받아 보관하고, 처음 스캔이면 한 번 안내한다. 패널이 열려 있으면 상태 줄과 결과를 갱신한다
    private func statusChanged(_ status: FileIndexer.Status) {
        if case .scanning(0) = status, !preferences.findFileFirstScanNotified {
            preferences.findFileFirstScanNotified = true
            ToastPanel.show("파일 찾기 인덱스를 처음 만듭니다. 폴더 접근 허용 창이 뜰 수 있습니다",
                            systemImage: "magnifyingglass", tint: .secondary, duration: .seconds(6))
        }
        let previous = self.status
        self.status = status
        onStatusChange?(status)
        guard let panel, panel.isVisible else { return }
        switch status {
        case .ready, .replaying:
            // 스캔이 끝났거나 변경이 반영됐으면 같은 검색어로 다시 찾는다
            if case .scanning = previous { lastSearch = nil }
            if case .loading = previous { lastSearch = nil }
            search(panel.query, composing: false, force: true)
        default:
            if panel.query.trimmingCharacters(in: .whitespaces).isEmpty { panel.setStatus(Self.statusText(status)) }
        }
    }

    // MARK: - 패널

    /// 단축키·메뉴: 패널이 열려 있으면 닫고, 아니면 연다
    func toggle() {
        if let panel, panel.isVisible {
            dismiss(restoringFocus: true)
        } else {
            show(query: nil)
        }
    }

    /// 패널을 연다. query가 있으면 검색어를 채운다 (URL). 결과는 자동으로 열지 않는다
    func show(query: String?) {
        let panel = panel ?? makePanel()
        let front = NSWorkspace.shared.frontmostApplication
        if !panel.isVisible, front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        if let query { panel.setQuery(query) }
        panel.present(on: nil)
        Log.findFile.debug("패널 열기: 키 창 \(panel.isKeyWindow), 앱 활성 \(NSApp.isActive)")
        lastSearch = nil
        search(panel.query, composing: false, force: true)
        Task { [indexer] in await indexer.retryDeniedFolders() }
    }

    // 패널을 만들고 동작을 연결한다 (한 번만 만들어 재사용)
    private func makePanel() -> FindFilePanel {
        let panel = FindFilePanel()
        panel.onQueryChange = { [weak self] text, composing in self?.search(text, composing: composing) }
        panel.onOpen = { [weak self] hit in self?.open(hit) }
        panel.onReveal = { [weak self] hit in self?.reveal(hit) }
        panel.onCopyPath = { [weak self] hit in self?.copyPath(hit) }
        panel.onDismiss = { [weak self] in self?.dismiss(restoringFocus: true) }
        // 다른 앱이나 창을 누르면 닫는다 (포커스는 이미 그쪽으로 갔으므로 돌려주지 않는다)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        }
        self.panel = panel
        return panel
    }

    // 패널을 닫고, 필요하면 열기 전 앱으로 포커스를 돌려준다
    private func dismiss(restoringFocus: Bool) {
        guard let panel, panel.isVisible else { return }
        Log.findFile.debug("패널 닫기: 포커스 복귀 \(restoringFocus)")
        searchTask?.cancel()
        panel.orderOut(nil)
        if restoringFocus, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    // 검색어가 바뀌면 이전 검색을 취소하고 새로 찾는다 (디바운스 없음: 110만 개에서 수 ms)
    private func search(_ text: String, composing: Bool, force: Bool = false) {
        if !force, let lastSearch, lastSearch.text == text, lastSearch.composing == composing { return }
        lastSearch = (text, composing)
        searchTask?.cancel()
        guard let panel else { return }
        let query = SearchQuery(text, home: NSHomeDirectory(), composing: composing)
        if query.isEmpty || query.error != nil {
            panel.show([])
            panel.setStatus(query.error ?? Self.statusText(status))
            return
        }
        searchTask = Task { [indexer, status] in
            let index = await indexer.snapshot()
            let start = ContinuousClock.now
            let results = await FileSearcher.search(query, in: index)
            guard !Task.isCancelled else { return }
            let elapsed = (ContinuousClock.now - start).milliseconds
            panel.show(results.hits)
            panel.setStatus(Self.resultText(results, milliseconds: elapsed, status: status))
        }
    }

    // MARK: - 결과 동작

    // 기본 앱으로 연다. 파일이 없어졌으면 알리고 그 폴더를 다시 맞춘다
    private func open(_ hit: SearchHit) {
        guard exists(hit) else { return }
        dismiss(restoringFocus: false)
        NSWorkspace.shared.open(URL(fileURLWithPath: hit.path))
    }

    // Finder에서 선택해 보여 준다
    private func reveal(_ hit: SearchHit) {
        guard exists(hit) else { return }
        dismiss(restoringFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.path)])
    }

    // 전체 경로를 복사하고 이전 앱으로 돌아가 바로 붙여넣을 수 있게 한다
    private func copyPath(_ hit: SearchHit) {
        exporter.copy(text: hit.path)
        dismiss(restoringFocus: true)
        ToastPanel.show("경로 복사됨 · \((hit.path as NSString).abbreviatingWithTildeInPath)", systemImage: "doc.on.clipboard")
    }

    // 결과가 아직 있는지 확인한다. 없으면 토스트로 알리고 부모 폴더를 인덱스와 다시 맞춘다
    private func exists(_ hit: SearchHit) -> Bool {
        if FileManager.default.fileExists(atPath: hit.path) { return true }
        ToastPanel.show("파일이 없습니다 · \(hit.name)", systemImage: "exclamationmark.triangle.fill", tint: .orange)
        let folder = (hit.path as NSString).deletingLastPathComponent
        Task { [indexer] in await indexer.refresh(directory: folder) }
        return false
    }

    // MARK: - 상태 문구

    /// 검색어가 없을 때 상태 줄에 보일 인덱스 상태
    static func statusText(_ status: FileIndexer.Status) -> String {
        switch status {
        case .idle: "파일 찾기 인덱스가 꺼져 있습니다 (설정에서 켜기)"
        case .loading: "인덱스를 불러오는 중…"
        case .scanning(let count): "인덱스를 만드는 중… \(count.formatted())개"
        case .replaying(let count): "인덱스 \(count.formatted())개 · 변경 반영 중"
        case .ready(let count, _): "인덱스 \(count.formatted())개"
        case .failed(let message): message
        }
    }

    // 검색 결과 상태 줄: 일치 수·걸린 시간 (인덱스를 만드는 중이면 함께 알린다)
    private static func resultText(_ results: SearchResults, milliseconds: Double, status: FileIndexer.Status) -> String {
        var text = results.totalMatches == 0 ? "일치하는 항목 없음" : "\(results.totalMatches.formatted())개 일치"
        if results.totalMatches > results.hits.count { text += " · 상위 \(results.hits.count)개" }
        text += " · \(Int(milliseconds.rounded()))ms"
        switch status {
        case .scanning, .loading, .idle: text += " · " + statusText(status)
        default: break
        }
        return text
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
