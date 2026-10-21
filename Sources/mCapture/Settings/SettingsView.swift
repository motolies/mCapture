import AppKit
import Combine
import MCaptureCore
import ServiceManagement
import SwiftUI

/// 설정 화면의 편집 중 상태. Command Line Tools에는 SwiftUI @State 매크로 플러그인이 없어 ObservableObject로 둔다
@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotkeys: [HotKeyCenter.Action: HotKeySpec] = [:]
    /// 키 입력을 기다리는 동작. nil이면 녹화 중이 아니다
    @Published var recording: HotKeyCenter.Action?
    /// 녹화 중 지금 누르고 있는 수식키 기호 (예: ⌃⇧)
    @Published var pressedModifiers = ""
    @Published var hotkeyMessage: String?
    @Published var launchAtLogin = false
    @Published var permissionGranted = false
    private var monitor: Any?

    private static let recordingHint = "⌘·⌃·⌥ 중 하나 이상과 영문자·숫자를 함께 누르세요 (Esc: 취소)"

    /// 창을 열 때마다 현재 값으로 다시 읽는다
    func reload() {
        stopRecording()
        hotkeys = Dictionary(uniqueKeysWithValues: HotKeyCenter.Action.allCases.map { ($0, Preferences.shared.hotkey(for: $0)) })
        hotkeyMessage = nil
        launchAtLogin = SMAppService.mainApp.status == .enabled
        permissionGranted = CGPreflightScreenCaptureAccess()
    }

    /// 단축키 녹화를 시작한다. 녹화 중인 동작을 다시 누르면 취소한다
    /// 녹화하는 동안 전역 단축키를 해제해야 같은 조합을 눌러도 캡처가 시작되지 않는다
    func toggleRecording(_ action: HotKeyCenter.Action) {
        guard recording != action else {
            hotkeyMessage = nil
            stopRecording()
            return
        }
        stopRecording()
        recording = action
        hotkeyMessage = Self.recordingHint
        NotificationCenter.default.post(name: .mcaptureHotKeyRecording, object: true)
        // 메뉴 단축키(⌘Q 등)보다 먼저 받도록 로컬 모니터로 가로챈다
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.handleRecording(event) else { return event }
            return nil
        }
    }

    /// 녹화를 끝내고 전역 단축키를 다시 등록하게 한다
    func stopRecording() {
        guard recording != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        pressedModifiers = ""
        NotificationCenter.default.post(name: .mcaptureHotKeyRecording, object: false)
    }

    /// 녹화를 끝내고 안내 문구를 지운다 (탭을 바꿔 녹화 버튼이 보이지 않게 될 때)
    func resetHotkeyEditing() {
        hotkeyMessage = nil
        stopRecording()
    }

    // 녹화 중 키 이벤트를 처리한다. 이벤트를 삼켰으면 true
    private func handleRecording(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        let modifiers = HotKeySpec.Modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            pressedModifiers = modifiers.symbols
            return false
        }
        if event.keyCode == 53, modifiers.isEmpty {
            hotkeyMessage = nil
            stopRecording()
            return true
        }
        guard let spec = HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            hotkeyMessage = "지원하지 않는 조합입니다. " + Self.recordingHint
            return true
        }
        if let other = hotkeys.first(where: { $0.key != action && $0.value == spec })?.key {
            hotkeyMessage = "\(other.title) 단축키와 겹칩니다: \(spec.displayString)"
            return true
        }
        Preferences.shared.setHotkey(spec, for: action)
        hotkeys[action] = spec
        hotkeyMessage = "\(action.title): \(spec.displayString) 적용됨"
        // 녹화 종료 알림을 받은 AppDelegate가 새 설정으로 다시 등록한다
        stopRecording()
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("로그인 항목 변경 실패: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// 설정 창의 탭. rawValue는 URL(`settings?tab=`)에 쓴다
enum SettingsTab: String, CaseIterable {
    case general
    case capture
    case find
    case monitor

    /// 탭 내용의 폭
    static let contentWidth: CGFloat = 480

    var title: String {
        switch self {
        case .general: "일반"
        case .capture: "캡처"
        case .find: "파일 찾기"
        case .monitor: "시스템 모니터"
        }
    }

    /// 툴바 아이콘 (SF Symbol)
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .find: "magnifyingglass"
        case .monitor: "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

/// 일반 탭: 여러 기능이 함께 쓰는 설정과 앱 정보
struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 실행", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }

            Section("권한") {
                LabeledContent("화면 기록") {
                    HStack {
                        Text(model.permissionGranted ? "허용됨" : "허용 필요")
                            .foregroundStyle(model.permissionGranted ? .green : .orange)
                        Button("시스템 설정 열기") { ScreenRecordingPermission.openSystemSettings() }
                    }
                }
                Text("캡처, 텍스트 인식, 컬러 피커에 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("정보") {
                LabeledContent("버전") {
                    Text(AppVersion.current.displayString)
                        .textSelection(.enabled)
                }
                LabeledContent("GitHub") {
                    Link(Self.repository, destination: URL(string: "https://" + Self.repository)!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
    }

    /// 소스 저장소 (화면 표시용, 누르면 https로 기본 브라우저에서 연다)
    private static let repository = "github.com/motolies/mCapture"
}

/// 캡처 탭: 저장, 캡처 후 동작, 에디터, 캡처 단축키. 단순 값은 Preferences와 같은 UserDefaults 키에 바로 저장된다
struct CaptureSettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.saveFolder) private var saveFolder = Preferences.Default.saveFolder
    @AppStorage(Preferences.Key.fileNameTemplate) private var fileNameTemplate = FileNaming.defaultTemplate
    @AppStorage(Preferences.Key.afterCaptureCopy) private var afterCopy = true
    @AppStorage(Preferences.Key.afterCaptureSave) private var afterSave = true
    @AppStorage(Preferences.Key.afterCaptureOpenEditor) private var afterOpenEditor = true
    @AppStorage(Preferences.Key.escAction) private var escAction = EscAction.copy.rawValue
    @AppStorage(Preferences.Key.ocrJoinLines) private var ocrJoinLines = false
    @AppStorage(Preferences.Key.windowShadow) private var windowShadow = true

    var body: some View {
        Form {
            Section("저장") {
                LabeledContent("저장 폴더") {
                    HStack {
                        Text(saveFolder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("변경…", action: chooseFolder)
                        Button("열기") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: (saveFolder as NSString).expandingTildeInPath))
                        }
                    }
                }
                LabeledContent("파일 이름") {
                    HStack {
                        TextField("파일 이름", text: $fileNameTemplate, prompt: Text(FileNaming.defaultTemplate))
                            .labelsHidden()
                        Button("기본값") { fileNameTemplate = FileNaming.defaultTemplate }
                            .disabled(fileNameTemplate == FileNaming.defaultTemplate)
                    }
                }
                fileNamePreview
            }

            Section("캡처 후") {
                Toggle("클립보드에 복사", isOn: $afterCopy)
                Toggle("파일로 저장", isOn: $afterSave)
                Toggle("에디터 열기", isOn: $afterOpenEditor)
            }

            Section("에디터") {
                Picker("Esc로 닫을 때", selection: $escAction) {
                    ForEach(EscAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            Section("창 캡처") {
                Toggle("그림자 포함 (배경은 투명)", isOn: $windowShadow)
            }

            Section("텍스트 인식") {
                Toggle("줄바꿈 제거 (줄을 공백으로 이어 붙임)", isOn: $ocrJoinLines)
            }

            // 파일 찾기 외의 동작은 모두 이 탭에 둔다 (새 동작도 따로 정하지 않으면 여기에 나온다)
            HotKeySettingsSection(model: model, actions: HotKeyCenter.Action.allCases.filter { $0 != .findFile })
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
    }

    // 지금 시각으로 만든 파일 이름 미리보기와 쓸 수 있는 토큰
    private var fileNamePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("미리보기: \(FileNaming.baseName(template: fileNameTemplate, date: Date(), appName: "Safari")).png")
                .textSelection(.enabled)
            Text("{date} 2026-10-16 · {time} 11-05-32 · {app} 캡처한 앱 (미리보기는 Safari)")
            Text("{yyyy} {yy} 연 · {MM} 월 · {dd} 일 · {HH} 시 · {mm} 분 · {ss} 초")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (saveFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

/// 단축키 섹션. 탭마다 그 기능의 동작만 보여 주고, 겹침 검사는 모델이 모든 단축키를 대상으로 한다
struct HotKeySettingsSection: View {
    @ObservedObject var model: SettingsModel
    let actions: [HotKeyCenter.Action]

    var body: some View {
        Section("단축키") {
            ForEach(actions) { action in
                LabeledContent(action.title) {
                    recorder(action)
                }
            }
            Text(model.hotkeyMessage ?? "버튼을 누른 뒤 새 키 조합을 누르세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // 누르면 녹화를 시작하는 단축키 버튼. 녹화 중에는 강조하고 지금 누른 수식키를 보여 준다
    @ViewBuilder
    private func recorder(_ action: HotKeyCenter.Action) -> some View {
        if model.recording == action {
            Button { model.toggleRecording(action) } label: {
                Text(model.pressedModifiers.isEmpty ? "키 조합을 누르세요…" : model.pressedModifiers + " …")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .help("다시 누르면 취소")
        } else {
            Button { model.toggleRecording(action) } label: {
                Text(model.hotkeys[action]?.displayString ?? "")
                    .monospaced()
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)
            .help("눌러서 새 단축키 입력")
        }
    }
}

extension HotKeySpec.Modifiers {
    /// NSEvent 수식키 플래그에서 만든다 (Caps Lock·Fn 등은 무시)
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
