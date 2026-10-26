import AppKit
import MCaptureCore
import Synchronization

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

    /// 체크한 항목. 검색어가 바뀌거나 패널이 닫혀도 남는다 (해제는 명시적으로)
    private var selection = PathSelection()
    /// 일치하는 모든 항목을 불러와 체크한 상태 (삭제 확인을 한 단계 더 거친다)
    private var allMatchesSelected = false
    /// 목록에 체크한 항목만 보이는 중 (검색어를 고치면 검색 결과로 돌아간다)
    private var showingSelection = false
    /// Finder 창이 여러 개 열려 한 번 더 누르길 기다리는 경로들
    private var pendingReveal: [String]?
    /// 여러 폴더에 걸친 Finder 보기를 한 번 더 확인하는 기준 (폴더 수)
    private static let revealConfirmFolders = 5

    /// 휴지통 이동 단계
    private enum DeletionMode {
        case idle
        /// 확인 카드가 떠 있음 (크기 계산 취소 표시)
        case reviewing(DeletionPlan, sizing: CancellationFlag)
        /// 옮기는 중 (중지 표시)
        case deleting(CancellationFlag)
    }

    private var deletionMode = DeletionMode.idle
    /// 마지막으로 휴지통에 옮긴 묶음 (되돌리기)
    private var lastTrashed: [DeletionReport.Trashed] = []
    private let remover = SystemFileRemover()
    /// 진행 배너를 이보다 오래 걸릴 때만 보인다
    private static let progressBannerDelay = Duration.milliseconds(500)

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
            // 스캔이 끝났거나 변경이 반영됐으면 같은 검색어로 다시 찾는다 (커서 행은 그대로)
            // 확인·이동 중에는 목록을 바꾸지 않는다 (끝나면 다시 찾는다)
            guard !showingSelection, case .idle = deletionMode else { return }
            if case .scanning = previous { lastSearch = nil }
            if case .loading = previous { lastSearch = nil }
            search(panel.query, composing: false, force: true, preserveCursor: true)
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
    /// activate가 false면 앱을 활성화하지 않는다 (DEBUG URL `find?activate=0`로만 씀)
    func show(query: String?, activate: Bool = true) {
        let panel = panel ?? makePanel()
        let front = NSWorkspace.shared.frontmostApplication
        if !panel.isVisible, front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        if let query { panel.setQuery(query) }
        panel.update(selection: selection, allMatchesSelected: allMatchesSelected)
        // 1분 안에 다시 열면 마지막 휴지통 결과(되돌리기)를 다시 보인다
        if let lastResult, ContinuousClock.now - lastResult.at < Self.resultBannerLifetime {
            panel.showBanner(lastResult.banner)
        }
        panel.present(on: nil, activate: activate)
        Log.findFile.debug("패널 열기: 키 창 \(panel.isKeyWindow), 앱 활성 \(NSApp.isActive)")
        lastSearch = nil
        showingSelection = false
        search(panel.query, composing: false, force: true)
        Task { [indexer] in await indexer.retryDeniedFolders() }
    }

    // 패널을 만들고 동작을 연결한다 (한 번만 만들어 재사용)
    private func makePanel() -> FindFilePanel {
        let panel = FindFilePanel()
        panel.onQueryChange = { [weak self] text, composing in self?.search(text, composing: composing) }
        panel.onOpen = { [weak self] hit in self?.open(hit) }
        panel.onReveal = { [weak self] paths in self?.reveal(paths) }
        panel.onCopyPaths = { [weak self] paths in self?.copyPaths(paths) }
        panel.onCheck = { [weak self] hits, checking in self?.check(hits, checking) }
        panel.onCheckAllMatches = { [weak self] in self?.checkAllMatches() }
        panel.onClearChecks = { [weak self] in self?.clearChecks() }
        panel.onShowSelection = { [weak self] in self?.showSelection() }
        panel.onRequestDelete = { [weak self] hits in self?.requestDelete(hits) }
        panel.onConfirmDelete = { [weak self] in self?.confirmDelete() }
        panel.onCancelDelete = { [weak self] in self?.cancelDelete() }
        panel.onReviewDelete = { [weak self] in
            self?.cancelDelete()
            self?.showSelection()
        }
        panel.onStopDeletion = { [weak self] in self?.stopDeletion() }
        panel.onUndoDeletion = { [weak self] in self?.undoDeletion() }
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
        // 확인 중에 닫히면(바깥을 눌러도) 아무것도 지우지 않는다. 옮기는 중이면 그대로 끝까지 하고 토스트로 알린다
        if case .reviewing = deletionMode { cancelDelete() }
        panel.showBanner(nil)
        panel.orderOut(nil)
        if restoringFocus, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    // 검색어가 바뀌면 이전 검색을 취소하고 새로 찾는다 (디바운스 없음: 110만 개에서 수 ms)
    // preserveCursor면 커서 행을 경로로 기억했다가 다시 고른다 (인덱스 변경으로 다시 찾을 때)
    private func search(_ text: String, composing: Bool, force: Bool = false, preserveCursor: Bool = false,
                        limit: Int = FileSearcher.defaultLimit, completion: ((SearchResults) -> Void)? = nil) {
        if !force, let lastSearch, lastSearch.text == text, lastSearch.composing == composing { return }
        lastSearch = (text, composing)
        showingSelection = false
        pendingReveal = nil
        searchTask?.cancel()
        guard let panel else { return }
        let query = SearchQuery(text, home: NSHomeDirectory(), composing: composing)
        if query.isEmpty || query.error != nil {
            panel.show([])
            panel.setStatus(query.error ?? Self.statusText(status))
            return
        }
        let cursor = preserveCursor ? panel.selectedHit?.path : nil
        searchTask = Task { [indexer, status] in
            let index = await indexer.snapshot()
            let start = ContinuousClock.now
            let results = await FileSearcher.search(query, in: index, limit: limit)
            guard !Task.isCancelled else { return }
            let elapsed = (ContinuousClock.now - start).milliseconds
            panel.show(results.hits, total: results.totalMatches, preserving: cursor)
            panel.setStatus(Self.resultText(results, milliseconds: elapsed, status: status))
            completion?(results)
        }
    }

    // MARK: - 결과 동작

    // 기본 앱으로 연다. 파일이 없어졌으면 알리고 그 폴더를 다시 맞춘다
    private func open(_ hit: SearchHit) {
        guard exists(hit.path) else { return }
        dismiss(restoringFocus: false)
        NSWorkspace.shared.open(URL(fileURLWithPath: hit.path))
    }

    // Finder에서 선택해 보여 준다. 여러 폴더에 걸쳐 Finder 창이 많이 열리면 한 번 더 누를 때 연다
    private func reveal(_ paths: [String]) {
        let existing = paths.filter { exists($0, quietly: paths.count > 1) }
        guard !existing.isEmpty else { return }
        let folders = Set(existing.map { ($0 as NSString).deletingLastPathComponent }).count
        if folders > Self.revealConfirmFolders, pendingReveal != paths {
            pendingReveal = paths
            panel?.setStatus("Finder 창이 \(folders)개 열립니다 · ⌘↩를 한 번 더 누르면 엽니다")
            return
        }
        pendingReveal = nil
        dismiss(restoringFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting(existing.map { URL(fileURLWithPath: $0) })
    }

    // 전체 경로를 복사하고(여러 개는 줄바꿈으로) 이전 앱으로 돌아가 바로 붙여넣을 수 있게 한다
    private func copyPaths(_ paths: [String]) {
        guard let first = paths.first else { return }
        exporter.copy(text: paths.joined(separator: "\n"))
        dismiss(restoringFocus: true)
        let text = paths.count == 1 ? "경로 복사됨 · \((first as NSString).abbreviatingWithTildeInPath)" : "경로 \(paths.count)개 복사됨"
        ToastPanel.show(text, systemImage: "doc.on.clipboard")
    }

    // 결과가 아직 있는지 확인한다. 없으면(quietly가 아니면) 토스트로 알리고 부모 폴더를 인덱스와 다시 맞춘다
    private func exists(_ path: String, quietly: Bool = false) -> Bool {
        if FileManager.default.fileExists(atPath: path) { return true }
        if !quietly {
            ToastPanel.show("파일이 없습니다 · \((path as NSString).lastPathComponent)", systemImage: "exclamationmark.triangle.fill", tint: .orange)
        }
        let folder = (path as NSString).deletingLastPathComponent
        Task { [indexer] in await indexer.refresh(directory: folder) }
        return false
    }

    // MARK: - 체크

    /// 지울 수 없는 경로를 가려낸다 (시스템·검색 폴더·앱·클라우드)
    private var deletionGuard: DeletionGuard {
        DeletionGuard(home: NSHomeDirectory(), roots: configuration.roots, appPath: Bundle.main.bundlePath)
    }

    // 결과를 체크하거나 해제한다. 지울 수 없는 항목은 체크하지 않고 이유를 상태 줄에 보인다
    private func check(_ hits: [SearchHit], _ checking: Bool) {
        pendingReveal = nil
        var notice: String?
        if checking {
            let guardian = deletionGuard
            var blocked: [DeletionGuard.Reason] = []
            var items: [PathSelection.Item] = []
            for hit in hits {
                if let reason = guardian.reason(path: hit.path) {
                    blocked.append(reason)
                } else {
                    items.append(PathSelection.Item(path: hit.path, isDirectory: hit.isDirectory, isPackage: hit.isPackage))
                }
            }
            let result = selection.insert(contentsOf: items)
            if result.truncated {
                notice = "최대 \(selection.limit.formatted())개까지 고를 수 있습니다"
            } else if let reason = blocked.first {
                notice = blocked.count == 1 ? reason.message : "\(blocked.count)개는 체크하지 않았습니다 · \(reason.message)"
            }
        } else {
            selection.remove(paths: hits.map(\.path), includingDescendants: false)
            if selection.isEmpty { allMatchesSelected = false }
        }
        panel?.update(selection: selection, allMatchesSelected: allMatchesSelected)
        if let notice { panel?.setStatus(notice) }
    }

    // 일치하는 모든 항목(상한까지)을 목록에 불러와 체크한다. 본 적 없는 항목을 고르지 않도록 먼저 목록에 올린다
    private func checkAllMatches() {
        guard let panel else { return }
        let text = panel.query
        let query = SearchQuery(text, home: NSHomeDirectory())
        guard !query.isEmpty, query.error == nil else { return }
        Task { [indexer, weak self] in
            let index = await indexer.snapshot()
            let total = await FileSearcher.search(query, in: index, limit: 1).totalMatches
            guard let self else { return }
            guard total <= selection.limit else {
                panel.setStatus("일치하는 항목이 \(selection.limit.formatted())개를 넘습니다 · 검색어를 좁혀 주세요")
                return
            }
            search(text, composing: false, force: true, limit: max(total, 1)) { [weak self] results in
                guard let self else { return }
                check(results.hits, true)
                allMatchesSelected = true
                panel.update(selection: selection, allMatchesSelected: allMatchesSelected)
            }
        }
    }

    // 체크를 모두 푼다
    private func clearChecks() {
        selection.removeAll()
        allMatchesSelected = false
        pendingReveal = nil
        panel?.update(selection: selection, allMatchesSelected: false)
        if showingSelection, let panel {
            lastSearch = nil
            search(panel.query, composing: false, force: true)
        }
    }

    // 목록에 체크한 항목만 보인다 (검색어를 고치면 검색 결과로 돌아간다)
    private func showSelection() {
        guard let panel, !selection.isEmpty else { return }
        searchTask?.cancel()
        let hits = selection.orderedItems.map { item in
            var flags: FileIndex.Flags = item.isDirectory ? .directory : []
            if item.isPackage { flags.insert(.package) }
            return SearchHit(id: 0, name: (item.path as NSString).lastPathComponent, path: item.path, flags: flags)
        }
        showingSelection = true
        panel.show(hits)
        panel.setStatus("체크한 항목 \(hits.count.formatted())개 · 검색어를 고치면 검색 결과로 돌아갑니다")
    }

    // MARK: - 휴지통

    // 확인 카드를 연다. hits가 nil이면 체크한 항목, 아니면 그 결과들(우클릭한 체크 안 된 줄)
    // 파일 상태를 읽고 인덱스로 폴더 안을 세는 일은 메인 밖에서 한다
    private func requestDelete(_ hits: [SearchHit]?) {
        guard case .idle = deletionMode, let panel else { return }
        var target = selection
        var fromAllMatches = allMatchesSelected
        if let hits {
            target = PathSelection()
            target.insert(contentsOf: hits.map { PathSelection.Item(path: $0.path, isDirectory: $0.isDirectory, isPackage: $0.isPackage) })
            fromAllMatches = false
        }
        guard !target.isEmpty else { return }
        let guardian = deletionGuard
        let remover = remover
        let visible = Set(panel.hits.map(\.path))
        let items = target
        let allMatches = fromAllMatches
        Task { [indexer, weak self] in
            let index = await indexer.snapshot()
            let plan = await Task.detached(priority: .userInitiated) {
                DeletionPlan.make(selection: items, guardian: guardian, probe: remover.probe,
                                  stats: { path in index.lookup(path: path).map { index.subtreeStats(of: $0) } },
                                  fromAllMatches: allMatches)
            }.value
            self?.presentConfirmation(plan, visible: visible)
        }
    }

    // 계획으로 확인 카드를 띄우고 크기 계산을 시작한다. 옮길 항목이 없으면 이유만 알린다
    private func presentConfirmation(_ plan: DeletionPlan, visible: Set<String>) {
        guard let panel, panel.isVisible, case .idle = deletionMode else { return }
        // 그사이 밖에서 지워진 항목은 체크에서도 뺀다
        let missing = plan.excluded.filter { $0.reason == .missing }.map(\.path)
        if !missing.isEmpty {
            selection.remove(paths: missing, includingDescendants: false)
            if selection.isEmpty { allMatchesSelected = false }
            panel.update(selection: selection, allMatchesSelected: allMatchesSelected)
        }
        guard !plan.entries.isEmpty else {
            panel.setStatus(plan.excluded.first.map { "옮길 수 있는 항목이 없습니다 · \($0.reason.message)" } ?? "옮길 수 있는 항목이 없습니다")
            return
        }
        let sizing = CancellationFlag()
        deletionMode = .reviewing(plan, sizing: sizing)
        panel.showConfirmation(Self.card(for: plan, outside: plan.entries.count { !visible.contains($0.path) }, size: nil))
        let paths = plan.entries.map(\.path)
        Task { [weak self] in
            let size = await Task.detached(priority: .utility) {
                FileSizeCalculator.size(of: paths, isCancelled: { sizing.isCancelled })
            }.value
            guard let self, !sizing.isCancelled, case .reviewing = deletionMode else { return }
            panel.updateConfirmationSummary(Self.summary(for: plan, size: size))
        }
    }

    // 확인을 닫는다 (아무것도 지우지 않음, 체크는 남김)
    private func cancelDelete() {
        guard case .reviewing(_, let sizing) = deletionMode else { return }
        sizing.cancel()
        deletionMode = .idle
        panel?.hideConfirmation()
    }

    // 확정: 메인 밖에서 순서대로 휴지통으로 옮기고, 0.5초가 넘으면 진행 배너를 보인다
    private func confirmDelete() {
        guard case .reviewing(let plan, let sizing) = deletionMode else { return }
        sizing.cancel()
        let stop = CancellationFlag()
        deletionMode = .deleting(stop)
        panel?.hideConfirmation()
        let total = plan.entries.count
        let progress = Mutex(0)
        let started = ContinuousClock.now
        let remover = remover
        let entries = plan.entries
        Log.findFile.info("휴지통으로 옮기기 시작: \(total)개")
        // 진행 배너: 0.1초마다 끝낸 수를 읽어 그린다 (항목마다 메인으로 보내지 않음)
        let ticker = Task { [weak self] in
            try? await Task.sleep(for: Self.progressBannerDelay)
            while !Task.isCancelled {
                let done = progress.withLock { $0 }
                self?.panel?.showBanner(DeletionBanner(text: "휴지통으로 옮기는 중… \(done.formatted()) / \(total.formatted())",
                                                       tone: .progress, progress: (done, total), canStop: true))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        Task { [weak self] in
            let report = await Task.detached(priority: .userInitiated) {
                DeletionExecutor.run(entries, remover: remover, isCancelled: { stop.isCancelled },
                                     progress: { done, _ in progress.withLock { $0 = done } })
            }.value
            ticker.cancel()
            let elapsed = (ContinuousClock.now - started).milliseconds
            Log.findFile.info("휴지통으로 옮김 \(report.trashed.count)개, 실패 \(report.failed.count), 건너뜀 \(report.skipped.count), 중지 \(report.cancelledRemaining), \(Int(elapsed))ms")
            self?.finishDeletion(report)
        }
    }

    // 결과 반영: 옮긴 항목(과 그 안)의 체크·목록 줄을 빼고, 부모 폴더를 인덱스와 다시 맞추고, 결과를 알린다
    private func finishDeletion(_ report: DeletionReport) {
        deletionMode = .idle
        lastTrashed = report.trashed
        let gone = report.trashedPaths + report.skipped.filter { $0.reason == .missing }.map(\.path)
        selection.remove(paths: gone, includingDescendants: true)
        if selection.isEmpty { allMatchesSelected = false }
        let folders = Set(gone.map { ($0 as NSString).deletingLastPathComponent })
        Task { [indexer] in await indexer.refresh(directories: folders) }
        let banner = Self.banner(for: report)
        lastResult = (banner, .now)
        guard let panel, panel.isVisible else {
            ToastPanel.show(Self.toastText(for: report), systemImage: report.failed.isEmpty ? "trash" : "exclamationmark.triangle.fill",
                            tint: report.failed.isEmpty ? .secondary : .orange)
            return
        }
        panel.update(selection: selection, allMatchesSelected: allMatchesSelected)
        panel.removeHits(paths: Set(gone))
        panel.showBanner(banner)
    }

    // 중지: 지금 옮기는 항목까지 끝내고 멈춘다
    private func stopDeletion() {
        guard case .deleting(let stop) = deletionMode else { return }
        stop.cancel()
    }

    // 마지막 묶음을 원래 자리로 되돌린다 (원래 자리가 차 있으면 휴지통에 남김)
    private func undoDeletion() {
        guard case .idle = deletionMode, !lastTrashed.isEmpty else { return }
        let items = lastTrashed
        lastTrashed = []
        lastResult = nil
        let remover = remover
        Task { [indexer, weak self] in
            let report = await Task.detached(priority: .userInitiated) {
                DeletionExecutor.restore(items, remover: remover)
            }.value
            let folders = Set(report.restored.map { ($0 as NSString).deletingLastPathComponent })
            await indexer.refresh(directories: folders)
            guard let self else { return }
            Log.findFile.info("되돌림 \(report.restored.count)개, 충돌 \(report.conflicts.count), 실패 \(report.failed.count)")
            let text = Self.restoreText(for: report)
            guard let panel, panel.isVisible else {
                ToastPanel.show(text, systemImage: "arrow.uturn.backward")
                return
            }
            panel.showBanner(DeletionBanner(text: text, tone: report.conflicts.isEmpty && report.failed.isEmpty ? .info : .warning,
                                            details: (report.conflicts + report.failed).map { "\(Self.display($0)) — 원래 위치에 같은 이름이 있거나 휴지통에 없음" }))
            lastSearch = nil
            search(panel.query, composing: false, force: true, preserveCursor: true)
        }
    }

    /// 마지막 결과 배너와 그 시각 (1분 안에 창을 다시 열면 다시 보인다)
    private var lastResult: (banner: DeletionBanner, at: ContinuousClock.Instant)?
    private static let resultBannerLifetime = Duration.seconds(60)

    // MARK: 휴지통 문구

    // 확인 카드 내용 (제목·요약·미리보기 5줄·경고·개수 입력)
    private static func card(for plan: DeletionPlan, outside: Int, size: FileSizeCalculator.Result?) -> DeletionCard {
        let count = plan.entries.count
        let title = count == 1
            ? "‘\((plan.entries[0].path as NSString).lastPathComponent)’ 항목을 휴지통으로 옮길까요?"
            : "\(count.formatted())개 항목을 휴지통으로 옮길까요?"
        let preview = plan.preview
        let rows = preview.prefix(5).map { entry in
            DeletionCard.Row(icon: NSWorkspace.shared.icon(forFile: entry.path), name: (entry.path as NSString).lastPathComponent,
                             detail: entry.isDirectory ? "폴더 · " + containedText(entry.contained, unindexed: entry.hasUnindexed) : "",
                             location: display((entry.path as NSString).deletingLastPathComponent))
        }
        var notes: [String] = []
        if outside > 0 { notes.append("지금 목록에 없는 항목 \(outside.formatted())개가 들어 있습니다") }
        if plan.coveredCount > 0 { notes.append("체크한 폴더 안의 \(plan.coveredCount.formatted())개는 폴더와 함께 옮겨집니다") }
        if let first = plan.excluded.first {
            let others = plan.excluded.count > 1 ? " 외 \(plan.excluded.count - 1)개" : ""
            notes.append("뺀 항목: \((first.path as NSString).lastPathComponent)\(others) · \(first.reason.message)")
        }
        var locations: String?
        if plan.requiresCountConfirmation {
            locations = plan.topLocations().map { "\(display($0.folder)) \($0.count.formatted())" }.joined(separator: " · ")
        }
        return DeletionCard(title: title, summary: summary(for: plan, size: size), rows: rows,
                            moreText: count > 5 ? "외 \((count - 5).formatted())개 · 모두 보기" : nil,
                            notes: notes, locations: locations, countToType: plan.requiresCountConfirmation ? count : nil)
    }

    // 요약 줄: 파일 n개 · 폴더 m개(안에 최소 N개) · 약 2.3GB
    private static func summary(for plan: DeletionPlan, size: FileSizeCalculator.Result?) -> String {
        var parts: [String] = []
        if plan.fileCount > 0 { parts.append("파일 \(plan.fileCount.formatted())개") }
        if plan.folderCount > 0 {
            parts.append("폴더 \(plan.folderCount.formatted())개(안에 \(containedText(plan.containedTotal, unindexed: plan.hasUnindexed)))")
        }
        if let size {
            let text = ByteCountFormatter.string(fromByteCount: size.bytes, countStyle: .file)
            parts.append(size.isComplete ? "약 \(text)" : "\(text) 이상(계산 중단)")
        } else {
            parts.append("크기 계산 중…")
        }
        return parts.joined(separator: " · ")
    }

    // 폴더 안 항목 수 문구 (인덱스로 센 하한)
    private static func containedText(_ count: Int, unindexed: Bool) -> String {
        unindexed ? "\(count.formatted())개 이상 (색인하지 않은 폴더 포함)" : "최소 \(count.formatted())개"
    }

    // 결과 배너
    private static func banner(for report: DeletionReport) -> DeletionBanner {
        let moved = report.trashed.count
        let details = report.failed.map { "\(display($0.path)) — \($0.failure.message)" }
            + report.skipped.filter { $0.reason != .missing }.map { "\(display($0.path)) — \($0.reason == .changed ? "확인한 뒤 바뀜" : "클라우드 항목")" }
        if report.cancelledRemaining > 0 {
            return DeletionBanner(text: "중지했습니다 · \(moved.formatted())개를 옮겼고 \(report.cancelledRemaining.formatted())개는 그대로입니다",
                                  tone: .warning, canUndo: moved > 0, details: details)
        }
        if !details.isEmpty {
            return DeletionBanner(text: "\(moved.formatted())개를 옮겼고 \(details.count.formatted())개는 옮기지 못했습니다 · 옮기지 못한 항목은 체크해 두었습니다",
                                  tone: .warning, canUndo: moved > 0, details: details)
        }
        return DeletionBanner(text: "\(moved.formatted())개 항목을 휴지통으로 옮겼습니다", tone: .success, canUndo: moved > 0)
    }

    // 창이 닫힌 뒤 결과 토스트
    private static func toastText(for report: DeletionReport) -> String {
        let failed = report.failed.count
        return failed == 0
            ? "\(report.trashed.count.formatted())개 항목을 휴지통으로 옮겼습니다"
            : "휴지통으로 \(report.trashed.count.formatted())개 옮김 · \(failed.formatted())개 실패 · 파일 찾기 창에서 확인"
    }

    // 되돌림 결과 문구
    private static func restoreText(for report: RestoreReport) -> String {
        let left = report.conflicts.count + report.failed.count
        return left == 0
            ? "\(report.restored.count.formatted())개 항목을 원래 위치로 되돌렸습니다"
            : "\(report.restored.count.formatted())개를 되돌렸고 \(left.formatted())개는 휴지통에 남겼습니다"
    }

    // 경로를 ~로 줄여 보인다
    private static func display(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
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

    /// 열린 패널에 키를 흉내 낸다 (mcapture-dev://debug/find-key?cmd=moveLeft:|text=|key=51&mods=cmd)
    func debugKey(command: String?, text: String?, keyCode: UInt16?, modifiers: String?) {
        guard let panel, panel.isVisible else {
            Log.findFile.error("find-key: 패널이 열려 있지 않음")
            return
        }
        panel.debugKey(command: command, text: text, keyCode: keyCode, modifiers: modifiers)
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
