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
    /// 설정 창의 모든 키 녹화가 함께 쓰는 레코더 (한 번에 하나만 녹화)
    private let recorder: KeyRecorder

    private static let recordingHint = "⌘·⌃·⌥ 중 하나 이상과 영문자·숫자를 함께 누르세요 (Esc: 취소)"

    init(recorder: KeyRecorder) {
        self.recorder = recorder
    }

    /// 창을 열 때마다 현재 값으로 다시 읽는다
    func reload() {
        stopRecording()
        hotkeys = Dictionary(uniqueKeysWithValues: HotKeyCenter.Action.allCases.map { ($0, Preferences.shared.hotkey(for: $0)) })
        hotkeyMessage = nil
        launchAtLogin = SMAppService.mainApp.status == .enabled
        permissionGranted = CGPreflightScreenCaptureAccess()
    }

    /// 단축키 녹화를 시작한다. 녹화 중인 동작을 다시 누르면 취소한다
    /// 녹화하는 동안 레코더가 전역 단축키를 해제해 같은 조합을 눌러도 캡처가 시작되지 않는다
    func toggleRecording(_ action: HotKeyCenter.Action) {
        guard recording != action else {
            hotkeyMessage = nil
            stopRecording()
            return
        }
        recording = action
        pressedModifiers = ""
        hotkeyMessage = Self.recordingHint
        recorder.start(KeyRecorder.Session(
            modifiersChanged: { [weak self] modifiers in self?.pressedModifiers = modifiers.symbols },
            keyPressed: { [weak self] keyCode, modifiers in self?.accept(keyCode: keyCode, modifiers: modifiers, for: action) ?? true },
            ended: { [weak self] cancelled in
                // 다른 동작의 녹화가 시작돼 끝난 경우에는 이미 그 동작으로 바뀌어 있다
                guard let self, self.recording == action else { return }
                self.recording = nil
                self.pressedModifiers = ""
                if cancelled { self.hotkeyMessage = nil }
            }
        ))
    }

    /// 녹화를 끝내고 전역 단축키를 다시 등록하게 한다
    func stopRecording() {
        guard recording != nil else { return }
        recorder.stop()
    }

    /// 녹화를 끝내고 안내 문구를 지운다 (탭을 바꿔 녹화 버튼이 보이지 않게 될 때)
    func resetHotkeyEditing() {
        hotkeyMessage = nil
        stopRecording()
    }

    // 녹화한 키를 검사해 저장한다. 받아들였으면 true (녹화 끝), 안내만 하고 계속 기다리면 false
    private func accept(keyCode: UInt16, modifiers: KeyModifiers, for action: HotKeyCenter.Action) -> Bool {
        guard let spec = HotKeySpec(keyCode: UInt32(keyCode), modifiers: modifiers) else {
            hotkeyMessage = "지원하지 않는 조합입니다. " + Self.recordingHint
            return false
        }
        if let other = hotkeys.first(where: { $0.key != action && $0.value == spec })?.key {
            hotkeyMessage = "\(other.title) 단축키와 겹칩니다: \(spec.displayString)"
            return false
        }
        Preferences.shared.setHotkey(spec, for: action)
        hotkeys[action] = spec
        hotkeyMessage = "\(action.title): \(spec.displayString) 적용됨"
        // 녹화 종료 알림을 받은 AppDelegate가 새 설정으로 다시 등록한다
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
    case gesture
    case monitor

    /// 탭 내용의 폭
    static let contentWidth: CGFloat = 480

    var title: String {
        switch self {
        case .general: "일반"
        case .capture: "캡처"
        case .find: "파일 찾기"
        case .gesture: "제스처"
        case .monitor: "시스템 모니터"
        }
    }

    /// 툴바 아이콘 (SF Symbol)
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .find: "magnifyingglass"
        case .gesture: "magicmouse"
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

    // 누르면 녹화를 시작하는 단축키 버튼
    private func recorder(_ action: HotKeyCenter.Action) -> some View {
        KeyRecorderButton(
            isRecording: model.recording == action,
            pressedModifiers: model.pressedModifiers,
            title: model.hotkeys[action]?.displayString ?? "",
            toggle: { model.toggleRecording(action) }
        )
    }
}
