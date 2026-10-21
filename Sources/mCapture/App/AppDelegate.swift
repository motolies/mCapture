import AppKit
import MCaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let hotKeys = HotKeyCenter()
    private let sleepPreventer = SleepPreventer()
    private lazy var exporter = Exporter(preferences: preferences)
    private lazy var coordinator = CaptureCoordinator(preferences: preferences, exporter: exporter)
    private lazy var settings = SettingsWindowController(findFile: fileFinder)
    private lazy var fileFinder = FindFileController(preferences: preferences, exporter: exporter)
    private lazy var systemMonitor = SystemMonitorController(preferences: preferences)
    private var statusItem: StatusItemController?
    // 실행이 끝나기 전에 받은 URL. 실행을 마치면 nil
    private var pendingURLs: [URL]? = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        DragOutFiles.clear()
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
        statusItem = StatusItemController(preferences: preferences, sleepPreventer: sleepPreventer, actions: .init(
            captureArea: { [weak self] in self?.coordinator.captureArea() },
            captureFullscreen: { [weak self] in self?.coordinator.captureFullscreen() },
            captureWindow: { [weak self] in self?.coordinator.captureWindow() },
            recognizeText: { [weak self] in self?.coordinator.recognizeText() },
            pickColor: { [weak self] in self?.coordinator.pickColor() },
            findFile: { [weak self] in self?.fileFinder.toggle() },
            openFile: { [weak self] in self?.coordinator.openWithPanel() },
            openSaveFolder: { [weak self] in self?.exporter.openSaveFolder() },
            showSettings: { [weak self] in self?.settings.present() }
        ))

        // 메뉴바 아이콘 다음에 만들어 왼쪽에 CPU·MEM 항목이 놓인다
        systemMonitor.start()

        hotKeys.onAction = { [weak self] action in
            switch action {
            case .area: self?.coordinator.captureArea()
            case .fullscreen: self?.coordinator.captureFullscreen()
            case .window: self?.coordinator.captureWindow()
            case .ocr: self?.coordinator.recognizeText()
            case .color: self?.coordinator.pickColor()
            case .findFile: self?.fileFinder.toggle()
            }
        }
        hotKeys.install()
        registerHotKeys()
        NotificationCenter.default.addObserver(forName: .mcaptureHotKeyRecording, object: nil, queue: .main) { [weak self] note in
            let recording = (note.object as? Bool) == true
            MainActor.assumeIsolated {
                if recording {
                    self?.hotKeys.unregisterAll()
                } else {
                    self?.registerHotKeys()
                }
            }
        }
        Log.app.info("\(AppVariant.current.displayName, privacy: .public) 시작")
        fileFinder.startIndexingIfEnabled()

        let pending = pendingURLs ?? []
        pendingURLs = nil
        pending.forEach(handle)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 종료 전에 파일 찾기 인덱스의 바뀐 내용을 저장한다. 2초 안에 못 끝내도 종료한다
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let fileFinder = fileFinder
        Task {
            let save = Task { await fileFinder.saveBeforeQuit() }
            let timeout = Task { try? await Task.sleep(for: .seconds(2)) }
            _ = await (save.value, timeout.isCancelled)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// 실행 중에 앱을 다시 실행하면(Finder·Spotlight·Dock 아이콘 클릭) 빈 캔버스를 띄운다. 처음 실행할 때는 불리지 않는다
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.openBlankCanvas()
        return false
    }

    /// 파일이나 URL로 앱을 실행하면 applicationDidFinishLaunching보다 먼저 불리므로, 메뉴·상태 아이템을 만든 뒤 처리하도록 모아 둔다
    func application(_ application: NSApplication, open urls: [URL]) {
        if pendingURLs != nil {
            pendingURLs?.append(contentsOf: urls)
        } else {
            urls.forEach(handle)
        }
    }

    // MARK: - 메뉴 동작

    @objc func captureArea(_ sender: Any?) {
        coordinator.captureArea()
    }

    @objc func captureFullscreen(_ sender: Any?) {
        coordinator.captureFullscreen()
    }

    @objc func captureWindow(_ sender: Any?) {
        coordinator.captureWindow()
    }

    @objc func recognizeText(_ sender: Any?) {
        coordinator.recognizeText()
    }

    @objc func pickColor(_ sender: Any?) {
        coordinator.pickColor()
    }

    @objc func findFile(_ sender: Any?) {
        fileFinder.toggle()
    }

    @objc func openDocument(_ sender: Any?) {
        coordinator.openWithPanel()
    }

    @objc func showSettings(_ sender: Any?) {
        settings.present()
    }

    // MARK: - 내부

    /// 동작별 단축키를 등록한다. 앞 동작과 같은 조합이면(새 동작의 기본값이 바꾼 단축키와 겹칠 때 등) 등록하지 않고 알린다
    private func registerHotKeys() {
        var registered: [(action: HotKeyCenter.Action, spec: HotKeySpec)] = []
        var conflicts: [String] = []
        var failed = false
        for action in HotKeyCenter.Action.allCases {
            let spec = preferences.hotkey(for: action)
            if let owner = registered.first(where: { $0.spec == spec })?.action {
                hotKeys.unregister(action)
                Log.app.error("단축키 겹침 \(action.title, privacy: .public) = \(owner.title, privacy: .public): \(spec.stringValue, privacy: .public)")
                conflicts.append("\(action.title)(\(owner.title)와 같은 \(spec.displayString))")
            } else if hotKeys.register(spec, for: action) {
                registered.append((action, spec))
            } else {
                failed = true
            }
        }
        if !conflicts.isEmpty {
            ToastPanel.show("단축키가 겹쳐 꺼짐: \(conflicts.joined(separator: ", ")) — 설정에서 바꾸세요", systemImage: "exclamationmark.triangle.fill")
        } else if failed {
            ToastPanel.show("단축키 등록 실패 — 다른 앱과 겹치는지 확인하세요", systemImage: "exclamationmark.triangle.fill")
        }
    }

    /// Finder "다음으로 열기"로 받은 파일, mcapture://grab/area, grab/fullscreen, grab/window, ocr, color, find?q=, settings, open?path= (개발 빌드는 mcapture-dev://)
    private func handle(_ url: URL) {
        if url.isFileURL {
            coordinator.open(fileURL: url)
            return
        }
        guard url.scheme == AppVariant.current.urlScheme else { return }
        let command = url.pathComponents.first { $0 != "/" }
        switch (url.host, command) {
        case ("grab", "area"):
            coordinator.captureArea()
        case ("grab", "fullscreen"):
            coordinator.captureFullscreen()
        case ("grab", "window"):
            coordinator.captureWindow()
        case ("ocr", _):
            coordinator.recognizeText()
        case ("color", _):
            coordinator.pickColor()
        case ("settings", _):
            settings.present(tab: Self.queryValue(url, "tab").flatMap(SettingsTab.init(rawValue:)))
        case ("find", _):
            // 패널만 열고 검색어를 채운다. 다른 앱도 URL을 부를 수 있어 결과를 자동으로 열지 않는다
            fileFinder.show(query: Self.queryValue(url, "q"))
        case ("open", _):
            if let path = Self.queryPath(url) { coordinator.open(fileURL: URL(fileURLWithPath: path)) }
        #if DEBUG
        case ("debug", "snapshot"):
            if let path = Self.queryPath(url) { DebugSnapshot.write(to: URL(fileURLWithPath: path)) }
        case ("debug", "samples"):
            DebugSnapshot.addSamples()
        case ("debug", "paste"):
            DebugSnapshot.paste()
        case ("debug", "pin"):
            DebugSnapshot.pin()
        case ("debug", "inspect"):
            // ?tool=colorPicker|ruler&x=&y= (이미지 픽셀), x2·y2가 있으면 측정선
            let number = { (name: String) in Self.queryValue(url, name).flatMap(Double.init) }
            if let tool = Self.queryValue(url, "tool").flatMap(EditorState.Tool.init(rawValue:)), tool.isInspection,
               let x = number("x"), let y = number("y") {
                let end = number("x2").flatMap { x2 in number("y2").map { CGPoint(x: x2, y: $0) } }
                DebugSnapshot.inspect(tool: tool, point: CGPoint(x: x, y: y), end: end)
            }
        case ("debug", "awake"):
            // ?on=1 켜기, ?on=0 끄기, 값이 없으면 토글 (pmset -g assertions로 확인)
            switch Self.queryValue(url, "on") {
            case "1": statusItem?.setSleepPrevention(true)
            case "0": statusItem?.setSleepPrevention(false)
            default: statusItem?.toggleSleepPrevention()
            }
        case ("debug", "find-stats"):
            if let path = Self.queryPath(url) { fileFinder.debugWriteStats(to: URL(fileURLWithPath: path)) }
        case ("debug", "find-query"):
            if let text = Self.queryValue(url, "q"), let path = Self.queryPath(url) {
                fileFinder.debugWriteQuery(text, to: URL(fileURLWithPath: path))
            }
        case ("debug", "find-rebuild"):
            fileFinder.rebuild()
        case ("debug", "monitor-stats"):
            // ?path= 상태 JSON, ?image= 메뉴바 글자 이미지 PNG
            if let path = Self.queryPath(url) { systemMonitor.debugWriteStats(to: URL(fileURLWithPath: path)) }
            if let image = Self.queryValue(url, "image") { systemMonitor.debugWriteItemImages(to: URL(fileURLWithPath: (image as NSString).expandingTildeInPath)) }
        case ("debug", "monitor-smc"):
            if let path = Self.queryPath(url) { systemMonitor.debugWriteSMC(to: URL(fileURLWithPath: path)) }
        case ("debug", "monitor-show"):
            // ?kind=cpu|memory 팝오버 토글, path가 있으면 1.5초 뒤 내용을 PNG로, cores=N이면 코어 링을 그 수로 흉내
            CPUDetailView.debugCoreCount = Self.queryValue(url, "cores").flatMap(Int.init)
            if let kind = Self.queryValue(url, "kind").flatMap(MonitorStatusItem.Kind.init(rawValue:)) {
                systemMonitor.debugShow(kind: kind, snapshotTo: Self.queryPath(url).map { URL(fileURLWithPath: $0) })
            }
        case ("debug", "window"):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let id = items.first(where: { $0.name == "id" })?.value.flatMap(CGWindowID.init), let path = Self.queryPath(url) {
                coordinator.debugCaptureWindow(id: id, shadow: items.first { $0.name == "shadow" }?.value != "0", to: URL(fileURLWithPath: path))
            }
        #endif
        default:
            Log.app.error("알 수 없는 URL: \(url.absoluteString, privacy: .public)")
        }
    }

    // ?path= 값을 ~ 확장해 돌려준다
    private static func queryPath(_ url: URL) -> String? {
        queryValue(url, "path").map { ($0 as NSString).expandingTildeInPath }
    }

    // 쿼리 값 하나를 돌려준다
    private static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
