import AppKit
import Combine
import MCaptureCore
import SwiftUI

/// 설정 "제스처" 탭의 상태. 제스처 설정은 바꾸는 즉시 Preferences에 저장하고, 서비스는 UserDefaults KVO로 따라온다.
/// 편집기 상태(Draft)도 @State 대신 여기 두어 뷰가 두 번 만들어져도 값이 유지된다
@MainActor
final class GestureSettingsModel: ObservableObject {
    /// 동작 Picker의 선택지
    enum ActionChoice: Hashable {
        case unselected
        case app(AppAction)
        case sendKeys
        /// 이 버전이 모르는 동작 이름 (다른 버전이 저장). 보여 주기만 하고 실행하지 않는다
        case unknown(String)
    }

    /// 편집 중인 초안의 키 입력 대상
    enum KeyTarget: Hashable {
        case draft
    }

    enum Tint {
        case ok, warning, secondary
    }

    /// 새 제스처 설정(또는 편집 중인 제스처 설정)의 편집기 값
    struct Draft: Equatable {
        var device: InputDeviceKind? = .magicMouse
        var fingers = 3
        var kind: GestureKind = .tap
        var direction: SwipeDirection = .left
        var button: MouseButton = .left
        var choice: ActionChoice = .unselected
        var gestureSelected = false
        var chord: KeyChord?

        init() {}

        /// 기존 제스처 설정을 편집기에 싣는다
        init(_ binding: GestureBinding) {
            gestureSelected = true
            device = binding.spec.device
            fingers = binding.spec.gesture.fingers
            kind = binding.spec.gesture.kind
            direction = binding.spec.gesture.direction ?? .left
            button = binding.spec.gesture.button ?? .left
            switch binding.action {
            case .app(let name):
                choice = AppAction(rawValue: name).map { .app($0) } ?? .unknown(name)
            case .sendKeys(let chord):
                choice = .sendKeys
                self.chord = chord
            }
        }

        /// 피커 값으로 만든 조건. 만들 수 없으면 nil
        var spec: GestureSpec? {
            let gesture: InputGesture = switch kind {
            case .swipe: .swipe(fingers: fingers, direction: direction)
            case .click: .click(fingers: fingers, button: button)
            case .longPress: .longPress(fingers: fingers)
            case .tap, .move, .hold: .tap(fingers: fingers)
            }
            return GestureSpec(device: device, gesture: gesture)
        }

        /// 고른 동작. 키 조합 보내기인데 아직 키가 없으면 nil
        var action: GestureBinding.Action? {
            switch choice {
            case .unselected: nil
            case .app(let action): .app(action.rawValue)
            case .sendKeys: chord.map { .sendKeys($0) }
            case .unknown(let name): .app(name)
            }
        }
    }

    @Published private(set) var bindings: [GestureBinding] = []
    @Published private(set) var statusText = ""
    @Published private(set) var statusTint: Tint = .secondary
    @Published private(set) var lastGestureText = "없음"
    @Published private(set) var accessibilityGranted = false
    @Published var draft = Draft()
    @Published var manualExpanded = false
    @Published var diagnosticsExpanded = false {
        didSet {
            if diagnosticsExpanded != oldValue { layoutChanged() }
        }
    }
    /// 편집 중인 기존 제스처 설정의 조건. nil이면 새 제스처 설정
    @Published private(set) var editing: GestureSpec?
    @Published private(set) var recordingGesture = false
    @Published private(set) var keyTarget: KeyTarget?
    @Published private(set) var pressedModifiers = ""
    @Published private(set) var message: String?
    /// 제스처 설정 수가 바뀌어 창 높이를 다시 맞춰야 할 때 (설정 창이 건다)
    var onLayoutChange: (() -> Void)?
    var onConfirmDelete: ((GestureBinding) -> Void)?
    var onPresentEditor: (() -> Void)?
    var onDismissEditor: (() -> Void)?
    @Published private(set) var deviceStatuses: [String] = []
    @Published private(set) var activeKinds: Set<InputDeviceKind> = []
    var canRecordSelectedDevice: Bool {
        draft.device.map { activeKinds.contains($0) } ?? !activeKinds.isEmpty
    }
    func add() {
        cancelEditing()
        service.editingPaused = true
        onPresentEditor?()
    }
    func deviceChanged() { stopRecording() }


    private let service: GestureService
    private let recorder: KeyRecorder
    /// 제스처 녹음을 시작한 시각. 이 뒤 300ms 안에 온 이벤트는 버퍼 잔여나 녹음 버튼 클릭으로 보고 무시한다
    private var recordingStart: ContinuousClock.Instant?
    /// 녹음이 끝난 시각. 방금 녹음한 클릭 제스처가 녹음 버튼을 다시 누르는 것을 0.5초 동안 막는다
    private var recordingEnd: ContinuousClock.Instant?
    /// 권한이 없는 동안 1초마다 다시 읽는 Task. 허용되거나 창이 닫히면 끝난다
    private var permissionWatch: Task<Void, Never>?

    /// 프로필이 있어 다룰 수 있는 장치 종류 (피커). 편집 중인 제스처 설정의 종류는 없어도 넣는다
    var deviceChoices: [InputDeviceKind] {
        var kinds: [InputDeviceKind] = [.magicMouse, .builtInTrackpad, .magicTrackpad]
        if let device = draft.device, !kinds.contains(device) { kinds.append(device) }
        return kinds
    }

    /// 클릭 버튼 피커 값. 왼쪽·오른쪽과, 불러온 제스처 설정이 다른 버튼이면 그 버튼
    var buttonChoices: [MouseButton] {
        var buttons: [MouseButton] = [.left, .right]
        if !buttons.contains(draft.button) { buttons.append(draft.button) }
        return buttons
    }

    init(service: GestureService, recorder: KeyRecorder) {
        self.service = service
        self.recorder = recorder
    }

    /// 창을 열 때마다 제스처 설정·권한을 다시 읽고 서비스 상태를 따라간다. 창이 열려 있는 동안 서비스는 제스처 설정이 없어도 장치를 연다
    func reload() {
        bindings = Preferences.shared.gestureBindings
        message = nil
        service.onChange = { [weak self] in self?.refreshStatus() }
        service.settingsVisible = true
        refreshStatus()
        refreshPermission()
    }

    /// 창이 닫혔을 때: 녹음과 권한 감시를 끝내고 서비스에 알린다 (제스처 설정이 없으면 장치를 닫는다)
    func windowClosed() {
        cancelEditing()
        stopPermissionWatch()
        service.settingsVisible = false
    }

    /// 권한 표시를 새로 읽는다 (창을 열 때, 창이 다시 키가 됐을 때).
    /// 아직 없으면 허용될 때까지 1초마다 다시 읽어, 시스템 설정에서 켠 뒤 이 창을 누르지 않아도 표시가 바뀐다
    func refreshPermission() {
        accessibilityGranted = AccessibilityPermission.isGranted
        if accessibilityGranted {
            stopPermissionWatch()
            return
        }
        guard permissionWatch == nil else { return }
        permissionWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if AccessibilityPermission.isGranted {
                    self.accessibilityGranted = true
                    self.permissionWatch = nil
                    return
                }
            }
        }
    }

    // 권한 감시를 끝낸다
    private func stopPermissionWatch() {
        permissionWatch?.cancel()
        permissionWatch = nil
    }

    func openSystemGestureSettings() {
        stopRecording()
        let pane = draft.device == .magicMouse ? "Mouse" : "Trackpad"
        // 지원 대상 macOS 15 이상은 System Settings 확장 식별자를 사용한다.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.\(pane)-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            message = "시스템 설정을 열 수 없습니다. 시스템 설정에서 마우스 또는 트랙패드를 직접 선택해 주세요."
            return
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    // MARK: - 목록

    /// 제스처 설정을 켜거나 끈다
    func setEnabled(_ enabled: Bool, for spec: GestureSpec) {
        guard let index = bindings.firstIndex(where: { $0.spec == spec }) else { return }
        bindings[index].isEnabled = enabled
        save()
    }

    /// 기존 제스처 설정을 초안에 불러온 뒤 편집 시트를 연다.
    func edit(_ spec: GestureSpec) {
        guard let binding = bindings.first(where: { $0.spec == spec }) else { return }
        stopRecording()
        editing = spec
        draft = Draft(binding)
        message = nil
        service.editingPaused = true
        onPresentEditor?()
    }

    func remove(_ spec: GestureSpec) {
        if editing == spec { cancelEditing() }
        bindings.removeAll { $0.spec == spec }
        save()
        layoutChanged()
    }

    /// 편집기 내용을 추가하거나(새 제스처 설정) 편집 중인 제스처 설정을 같은 자리에서 바꾼다
    func commitDraft() {
        guard draftProblem == nil, let spec = draft.spec, let action = draft.action else { return }
        stopRecording()
        if let editing, let index = bindings.firstIndex(where: { $0.spec == editing }) {
            bindings[index] = GestureBinding(spec: spec, action: action, isEnabled: bindings[index].isEnabled)
            message = "바꿈: \(spec.displayName) → \(title(for: action))"
        } else {
            bindings.append(GestureBinding(spec: spec, action: action))
            message = "추가됨: \(spec.displayName) → \(title(for: action))"
            layoutChanged()
        }
        save()
        cancelEditing()
    }

    func cancelEditing() {
        stopRecording()
        service.editingPaused = false
        manualExpanded = false
        onDismissEditor?()
        editing = nil
        draft = Draft()
        message = nil
    }

    /// "추가"를 누를 수 없는 이유. 없으면 nil
    var draftProblem: String? {
        guard draft.gestureSelected else { return "제스처를 입력하거나 수동으로 지정하세요" }
        guard draft.choice != .unselected else { return "실행할 동작을 선택하세요" }
        guard let spec = draft.spec else { return "만들 수 없는 조건입니다" }
        if !(2...4).contains(draft.fingers) { return "2~4손가락만 등록할 수 있습니다" }
        if let other = bindings.first(where: { $0.spec == spec }), other.spec != editing {
            return "이미 등록된 조건입니다: \(title(for: other.action))"
        }
        switch draft.choice {
        case .sendKeys where draft.chord == nil: return "보낼 키 조합을 입력하세요"
        case .unknown(let name): return "알 수 없는 동작(\(name))은 다시 고르세요"
        default: return nil
        }
    }

    /// 추가는 되지만 알아야 할 것 (macOS 제스처와 겹침, 클릭 전달, 다른 제스처 설정과 겹침, 단축키와 같은 키, 권한)
    var draftWarnings: [String] {
        guard draft.gestureSelected, let spec = draft.spec else { return [] }
        var warnings: [String] = []
        let gesture = spec.gesture
        if spec.device != .magicMouse {
            warnings.append("시스템 설정에 따라 macOS 제스처와 겹칠 수 있습니다. 시스템 동작은 차단하거나 자동 변경하지 않습니다.")
        } else if gesture.fingers == 2 {
            if gesture.kind == .swipe, gesture.direction == .left || gesture.direction == .right {
                warnings.append("두 손가락 좌우 쓸기는 macOS의 전체 화면 앱 간 쓸기와 함께 일어납니다.")
            } else if gesture.kind == .tap {
                warnings.append("두 손가락 두 번 탭은 macOS의 Mission Control입니다. 탭할 때마다 이 동작도 실행됩니다.")
            } else {
                warnings.append("두 손가락은 macOS 제스처와 겹치기 쉽습니다. 3·4손가락을 권장합니다.")
            }
        }
        if gesture.kind == .click {
            warnings.append("클릭 제스처는 클릭도 앞 앱에 그대로 전달됩니다.")
        }
        for other in GestureBindingList.overlapping(spec, in: bindings) where other.spec != editing {
            warnings.append("\(other.spec.displayName)(\(title(for: other.action))) 제스처 설정과 겹칩니다. 장치를 지정한 쪽이 실행됩니다.")
        }
        if draft.choice == .sendKeys, let chord = draft.chord {
            if let action = HotKeyCenter.Action.allCases.first(where: { Preferences.shared.hotkey(for: $0).chord == chord }) {
                warnings.append("\(AppVariant.current.displayName)의 \(action.title) 단축키와 같습니다. 동작에서 \(action.title)를 직접 고르세요.")
            }
            if !accessibilityGranted {
                warnings.append("\(AccessibilityPermission.settingsItemName) 권한이 없어 키를 보낼 수 없습니다. 위 권한에서 허용하세요.")
            }
        }
        return warnings
    }

    // MARK: - 녹음·녹화

    /// 제스처 녹음을 켜거나 끈다. 켜면 다음 2~4손가락 제스처로 편집기 피커를 채운다 (그동안 제스처 설정은 실행되지 않는다)
    func toggleGestureRecording() {
        if recordingGesture {
            stopGestureRecording()
            message = nil
            return
        }
        // 방금 녹음한 클릭 제스처의 클릭이 이 버튼에 떨어져 다시 켜지는 것을 막는다
        if let end = recordingEnd, end.duration(to: .now) < .milliseconds(500) { return }
        guard canRecordSelectedDevice else { return }
        stopKeyRecording()
        draft.gestureSelected = false
        recordingGesture = true
        recordingStart = .now
        message = "선택한 장치에서 제스처를 입력하세요 (다시 누르면 취소)"
        service.recordingHandler = { [weak self] event in self?.recorded(event) }
    }

    // 녹음 중 들어온 제스처. 시작 직후 300ms 안(버퍼 잔여·녹음 버튼 클릭)은 버리고 2~4손가락만 받는다
    private func recorded(_ event: GestureEvent) {
        guard let start = recordingStart, start.duration(to: .now) >= .milliseconds(300) else { return }
        guard draft.device == nil || draft.device == event.device.kind else { return }
        guard (2...4).contains(event.gesture.fingers) else {
            message = "2~4손가락 제스처만 등록할 수 있습니다 (\(event.gesture.fingers)손가락)"
            return
        }
        draft.gestureSelected = true
        draft.fingers = event.gesture.fingers
        draft.kind = event.gesture.kind
        if let direction = event.gesture.direction { draft.direction = direction }
        if let button = event.gesture.button { draft.button = button }
        stopGestureRecording()
        if let spec = draft.spec, let existing = bindings.first(where: { $0.spec == spec }), existing.spec != editing {
            message = "이미 등록된 조건입니다: \(spec.displayName) → \(title(for: existing.action))"
        } else {
            message = "입력됨: \(draft.spec?.displayName ?? "")"
        }
    }

    // 녹음 핸들러를 떼고 끝난 시각을 적는다
    private func stopGestureRecording() {
        guard recordingGesture else { return }
        recordingGesture = false
        recordingStart = nil
        recordingEnd = .now
        service.recordingHandler = nil
    }

    /// 초안의 키 조합 입력을 켜거나 끈다.
    func toggleKeyRecording(_ target: KeyTarget) {
        if keyTarget == target {
            stopKeyRecording()
            return
        }
        stopGestureRecording()
        keyTarget = target
        pressedModifiers = ""
        message = "보낼 키 조합을 누르세요 (Esc: 취소)"
        recorder.start(KeyRecorder.Session(
            modifiersChanged: { [weak self] modifiers in self?.pressedModifiers = modifiers.symbols },
            keyPressed: { [weak self] keyCode, modifiers in self?.acceptKey(keyCode: keyCode, modifiers: modifiers, for: target) ?? true },
            ended: { [weak self] cancelled in
                guard let self, self.keyTarget == target else { return }
                self.keyTarget = nil
                self.pressedModifiers = ""
                if cancelled { self.message = nil }
            }
        ))
    }

    // 녹화한 키를 대상에 넣는다. 표에 없는 키면 안내하고 계속 기다린다
    private func acceptKey(keyCode: UInt16, modifiers: KeyModifiers, for target: KeyTarget) -> Bool {
        guard let chord = KeyChord(keyCode: keyCode, modifiers: modifiers) else {
            message = "지원하지 않는 키입니다. 영문자·숫자·문장부호·화살표·F1~F20·Space·Return 등을 누르세요"
            return false
        }
        switch target {
        case .draft:
            draft.chord = chord
            draft.choice = .sendKeys
            message = "키 조합: \(chord.displayString)"

        }
        return true
    }

    // 키 녹화만 끝낸다 (레코더의 ended가 keyTarget을 지운다)
    private func stopKeyRecording() {
        guard keyTarget != nil else { return }
        recorder.stop()
    }

    /// 녹음·녹화를 모두 끝낸다 (탭 전환·창 닫힘·비활성)
    func stopRecording() {
        stopGestureRecording()
        stopKeyRecording()
    }

    /// 동작의 표시 이름
    func title(for action: GestureBinding.Action) -> String {
        switch action {
        case .app(let name): AppAction(rawValue: name)?.title ?? "알 수 없는 동작 (\(name))"
        case .sendKeys(let chord): "키 보내기 \(chord.displayString)"
        }
    }

    // 서비스 상태와 마지막 제스처를 문구로 바꾼다
    private func refreshStatus() {
        switch service.state {
        case .off:
            (statusText, statusTint) = ("꺼짐", .secondary)
        case .idle:
            (statusText, statusTint) = ("대기 (켜진 제스처 설정 없음)", .secondary)
        case .unavailable(let reason):
            (statusText, statusTint) = ("사용할 수 없음 — \(reason)", .warning)
        case .searching:
            (statusText, statusTint) = ("지원 장치를 찾는 중 (연결되면 자동 시작)", .secondary)
        case .running(let devices):
            (statusText, statusTint) = ("동작 중 · " + devices.map(\.name).joined(separator: ", "), .ok)
        case .failed(let reason):
            (statusText, statusTint) = ("시작 실패 — \(reason)", .warning)
        case .paused:
            (statusText, statusTint) = ("잠자기 중", .secondary)
        }
        if case .running(let devices) = service.state { activeKinds = Set(devices.map(\.kind)) }
        else { activeKinds = [] }
        deviceStatuses = [InputDeviceKind.magicMouse, .builtInTrackpad, .magicTrackpad].map { kind in
            let found = service.detectedDevices.filter { $0.kind == kind }
            let reason = activeKinds.contains(kind) ? "연결됨 · 인식 중" : found.isEmpty ? "연결되지 않음" :
                found.contains { TouchGestureRecognizer.Profile.default(for: kind, surface: $0.surface) == nil } ? "표면 크기를 읽을 수 없음" : statusText
            return kind.displayName + ": " + reason
        }
        deviceStatuses += service.detectedDevices.filter { $0.kind == .unknown }.map { $0.name + ": 지원하지 않는 장치" }
        if let last = service.lastDispatch {
            let name = last.event.device.kind.displayName + " " + last.event.gesture.displayName(for: last.event.device.kind)
            if last.recorded {
                lastGestureText = "\(name) · 입력됨"
            } else if let binding = last.binding {
                lastGestureText = "\(name) → \(title(for: binding.action))"
            } else {
                lastGestureText = "\(name) · 제스처 설정 없음"
            }
        } else {
            lastGestureText = "없음"
        }
    }

    // 제스처 설정을 저장한다. 서비스는 KVO로 따라온다
    private func save() {
        Preferences.shared.gestureBindings = bindings
    }

    // 목록이나 진단 영역이 바뀐 뒤 다음 턴에 창 높이를 다시 맞추게 한다
    private func layoutChanged() {
        Task { @MainActor [weak self] in self?.onLayoutChange?() }
    }
}

struct GestureSettingsView: View {
    @ObservedObject var model: GestureSettingsModel
    @AppStorage(Preferences.Key.gestureEnabled) private var enabled = true

    var body: some View {
        Form {
            Section("제스처") {
                Toggle("제스처 사용", isOn: $enabled)
                ForEach(model.deviceStatuses, id: \.self) { Text($0) }
            }
            Section("등록된 제스처 설정") {
                if model.bindings.isEmpty { Text("제스처를 추가해 실행할 동작을 지정하세요.") }
                ForEach(model.bindings) { binding in
                    HStack {
                        Toggle("\(binding.spec.displayName) → \(model.title(for: binding.action))", isOn: Binding(
                            get: { binding.isEnabled }, set: { model.setEnabled($0, for: binding.spec) }))
                        Button("편집") { model.edit(binding.spec) }
                            .accessibilityLabel("\(binding.spec.displayName) 편집")
                        Button("삭제") { model.onConfirmDelete?(binding) }
                            .accessibilityLabel("\(binding.spec.displayName) 삭제")
                    }
                }
                Button("제스처 추가") { model.add() }
            }
            Section {
                Button("권한 및 상세 진단", systemImage: model.diagnosticsExpanded ? "chevron.down" : "chevron.right") {
                    model.diagnosticsExpanded.toggle()
                }
                .accessibilityValue(model.diagnosticsExpanded ? "펼쳐짐" : "접힘")
                if model.diagnosticsExpanded {
                Text(model.statusText)
                LabeledContent("마지막 제스처", value: model.lastGestureText)
                Text(model.accessibilityGranted ? "손쉬운 사용 허용됨" : "키 조합 보내기와 창 이동에는 손쉬운 사용 권한이 필요합니다.")
                Button("권한 설정 열기") { model.requestAccessibility() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)

    }
}

struct GestureEditorView: View {
    @ObservedObject var model: GestureSettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.editing == nil ? "제스처 추가" : "제스처 편집").font(.headline).padding()
            Form {
                Section("1. 장치 선택") {
                    Picker("장치", selection: $model.draft.device) {
                        Text("모든 장치").tag(InputDeviceKind?.none)
                        ForEach(model.deviceChoices, id: \.self) { Text($0.displayName).tag(InputDeviceKind?.some($0)) }
                    }
                    .onChange(of: model.draft.device) { model.deviceChanged() }
                }
                Section("2. 제스처 지정") {
                    Button(model.recordingGesture ? "제스처 입력 중지" : "제스처 입력 시작") { model.toggleGestureRecording() }
                        .buttonStyle(.borderedProminent)
                        .tint(model.recordingGesture ? Color.orange : Color.accentColor)
                        .disabled(!model.canRecordSelectedDevice)
                    if !model.canRecordSelectedDevice { Text("연결되지 않았거나 인식이 꺼져 있습니다. 수동 선택으로 저장할 수 있습니다.").font(.caption) }
                    if model.draft.gestureSelected { Text(model.draft.spec?.displayName ?? "") }
                    Button("수동 선택", systemImage: model.manualExpanded ? "chevron.down" : "chevron.right") {
                        model.manualExpanded.toggle()
                    }
                    .accessibilityValue(model.manualExpanded ? "펼쳐짐" : "접힘")
                    if model.manualExpanded {
                        Picker("손가락 수", selection: $model.draft.fingers) {
                            ForEach(2...4, id: \.self) { Text("\($0)손가락").tag($0) }
                        }
                        Picker("종류", selection: $model.draft.kind) {
                            ForEach(GestureKind.allCases.filter(\.isAssignable), id: \.self) { Text($0.displayName).tag($0) }
                        }
                        if model.draft.kind == .swipe {
                            Picker("방향", selection: $model.draft.direction) {
                                ForEach(SwipeDirection.allCases, id: \.self) { Text($0.displayName(for: model.draft.device ?? .unknown)).tag($0) }
                            }
                        }
                        if model.draft.kind == .click {
                            Picker("버튼", selection: $model.draft.button) {
                                ForEach(model.buttonChoices, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        Button("이 제스처 지정") { model.stopRecording(); model.draft.gestureSelected = true }
                    }
                }
                .onChange(of: model.draft.fingers) { model.draft.gestureSelected = true }
                .onChange(of: model.draft.kind) { model.draft.gestureSelected = true }
                .onChange(of: model.draft.direction) { model.draft.gestureSelected = true }
                .onChange(of: model.draft.button) { model.draft.gestureSelected = true }
                Section("3. 실행할 동작") {
                    Picker("동작", selection: $model.draft.choice) {
                        Text("동작 선택…").tag(GestureSettingsModel.ActionChoice.unselected)
                        ForEach(AppAction.allCases) { Text($0.title).tag(GestureSettingsModel.ActionChoice.app($0)) }
                        Text("키 조합 보내기").tag(GestureSettingsModel.ActionChoice.sendKeys)
                        if case .unknown(let name) = model.draft.choice { Text(name).tag(model.draft.choice) }
                    }
                    .onChange(of: model.draft.choice) { model.stopRecording() }
                    if model.draft.choice == .sendKeys {
                        KeyRecorderButton(isRecording: model.keyTarget == .draft, pressedModifiers: model.pressedModifiers,
                            title: model.draft.chord?.displayString ?? "키 조합 입력…", toggle: { model.toggleKeyRecording(.draft) })
                    }
                }
                if let problem = model.draftProblem { Text(problem).foregroundStyle(.orange) }
                if let message = model.message { Text(message).font(.caption) }
                ForEach(model.draftWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Button("macOS 제스처 설정 열기") { model.openSystemGestureSettings() }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("취소") { model.cancelEditing() }.keyboardShortcut(.cancelAction)
                Button("저장") { model.commitDraft() }.keyboardShortcut(.defaultAction)
                    .disabled(model.draftProblem != nil || model.recordingGesture || model.keyTarget != nil)
            }.padding()
        }
        .frame(minWidth: 500)
    }
}
