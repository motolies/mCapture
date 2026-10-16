import AppKit
import MCaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let hotKeys = HotKeyCenter()
    private lazy var exporter = Exporter(preferences: preferences)
    private lazy var coordinator = CaptureCoordinator(preferences: preferences, exporter: exporter)
    private lazy var settings = SettingsWindowController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DragOutFiles.clear()
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
        statusItem = StatusItemController(preferences: preferences, actions: .init(
            captureArea: { [weak self] in self?.coordinator.captureArea() },
            captureFullscreen: { [weak self] in self?.coordinator.captureFullscreen() },
            captureWindow: { [weak self] in self?.coordinator.captureWindow() },
            recognizeText: { [weak self] in self?.coordinator.recognizeText() },
            openFile: { [weak self] in self?.coordinator.openWithPanel() },
            openSaveFolder: { [weak self] in self?.exporter.openSaveFolder() },
            showSettings: { [weak self] in self?.settings.present() }
        ))

        hotKeys.onAction = { [weak self] action in
            switch action {
            case .area: self?.coordinator.captureArea()
            case .fullscreen: self?.coordinator.captureFullscreen()
            case .window: self?.coordinator.captureWindow()
            case .ocr: self?.coordinator.recognizeText()
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
        Log.app.info("mCapture 시작")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
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

    /// mcapture://grab/area, grab/fullscreen, grab/window, ocr, settings, open?path=
    private func handle(_ url: URL) {
        guard url.scheme == "mcapture" else { return }
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
        case ("settings", _):
            settings.present()
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
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
        return value.map { ($0 as NSString).expandingTildeInPath }
    }
}
