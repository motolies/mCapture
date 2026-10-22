import AppKit
import Combine
import MCaptureCore
import SwiftUI

/// 설정 "제스처" 탭의 상태. 바인딩은 바꾸는 즉시 Preferences에 저장하고, 서비스는 UserDefaults KVO로 따라온다.
/// 편집기 상태(Draft)도 @State 대신 여기 두어 뷰가 두 번 만들어져도 값이 유지된다
@MainActor
final class GestureSettingsModel: ObservableObject {
    /// 동작 Picker의 선택지
    enum ActionChoice: Hashable {
        case app(AppAction)
        case sendKeys
        /// 이 버전이 모르는 동작 이름 (다른 버전이 저장). 보여 주기만 하고 실행하지 않는다
        case unknown(String)
    }

    /// 키 녹화 대상: 편집기의 키 조합 또는 기존 행
    enum KeyTarget: Hashable {
        case draft
        case binding(GestureSpec)
    }

    enum Tint {
        case ok, warning, secondary
    }

    /// 새 바인딩(또는 편집 중인 바인딩)의 편집기 값
    struct Draft: Equatable {
        var device: InputDeviceKind? = .magicMouse
        var fingers = 3
        var kind: GestureKind = .tap
        var direction: SwipeDirection = .left
        var button: MouseButton = .left
        var choice: ActionChoice = .app(.captureArea)
        var chord: KeyChord?

        init() {}

        /// 기존 바인딩을 편집기에 싣는다
        init(_ binding: GestureBinding) {
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
            case .app(let action): .app(action.rawValue)
            case .sendKeys: chord.map { .sendKeys($0) }
            case .unknown(let name): .app(name)
            }
        }
    }

    @Published private(set) var bindings: [GestureBinding] = []
    @Published private(set) var statusText = ""
    @Published private(set) var statusTint: Tint = .secondary
    /// 장치가 돌고 있어 녹음할 수 있는지
    @Published private(set) var canRecordGesture = false
    @Published private(set) var lastGestureText = "없음"
    @Published private(set) var accessibilityGranted = false
    @Published var draft = Draft()
    /// 편집 중인 기존 바인딩의 조건. nil이면 새 바인딩
    @Published private(set) var editing: GestureSpec?
    @Published private(set) var recordingGesture = false
    @Published private(set) var keyTarget: KeyTarget?
    @Published private(set) var pressedModifiers = ""
    @Published private(set) var message: String?
    /// 바인딩 수가 바뀌어 창 높이를 다시 맞춰야 할 때 (설정 창이 건다)
    var onLayoutChange: (() -> Void)?

    private let service: GestureService
    private let recorder: KeyRecorder
    /// 제스처 녹음을 시작한 시각. 이 뒤 300ms 안에 온 이벤트는 버퍼 잔여나 녹음 버튼 클릭으로 보고 무시한다
    private var recordingStart: ContinuousClock.Instant?
    /// 녹음이 끝난 시각. 방금 녹음한 클릭 제스처가 녹음 버튼을 다시 누르는 것을 0.5초 동안 막는다
    private var recordingEnd: ContinuousClock.Instant?
    /// 권한이 없는 동안 1초마다 다시 읽는 Task. 허용되거나 창이 닫히면 끝난다
    private var permissionWatch: Task<Void, Never>?

    /// 프로필이 있어 다룰 수 있는 장치 종류 (피커). 편집 중인 바인딩의 종류는 없어도 넣는다
    var deviceChoices: [InputDeviceKind] {
        var kinds = InputDeviceKind.allCases.filter { TouchGestureRecognizer.Profile.default(for: $0, surface: .magicMouse2) != nil }
        if let device = draft.device, !kinds.contains(device) { kinds.append(device) }
        return kinds
    }

    /// 클릭 버튼 피커 값. 왼쪽·오른쪽과, 불러온 바인딩이 다른 버튼이면 그 버튼
    var buttonChoices: [MouseButton] {
        var buttons: [MouseButton] = [.left, .right]
        if !buttons.contains(draft.button) { buttons.append(draft.button) }
        return buttons
    }

    init(service: GestureService, recorder: KeyRecorder) {
        self.service = service
        self.recorder = recorder
    }

    /// 창을 열 때마다 바인딩·권한을 다시 읽고 서비스 상태를 따라간다. 창이 열려 있는 동안 서비스는 바인딩이 없어도 장치를 연다
    func reload() {
        bindings = Preferences.shared.gestureBindings
        message = nil
        service.onChange = { [weak self] in self?.refreshStatus() }
        service.settingsVisible = true
        refreshStatus()
        refreshPermission()
    }

    /// 창이 닫혔을 때: 녹음과 권한 감시를 끝내고 서비스에 알린다 (바인딩이 없으면 장치를 닫는다)
    func windowClosed() {
        stopRecording()
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

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    // MARK: - 목록

    /// 바인딩을 켜거나 끈다
    func setEnabled(_ enabled: Bool, for spec: GestureSpec) {
        guard let index = bindings.firstIndex(where: { $0.spec == spec }) else { return }
        bindings[index].isEnabled = enabled
        save()
    }

    /// 행의 동작 Picker에 보일 값. 그 행의 키를 녹화 중이면 키 조합 보내기
    func choice(for binding: GestureBinding) -> ActionChoice {
        if keyTarget == .binding(binding.spec) { return .sendKeys }
        switch binding.action {
        case .app(let name): return AppAction(rawValue: name).map { .app($0) } ?? .unknown(name)
        case .sendKeys: return .sendKeys
        }
    }

    /// 행의 동작을 바꾼다. 키 조합 보내기를 고르면 그 행의 키 녹화만 시작하고, 키를 받을 때 저장한다
    func choose(_ choice: ActionChoice, for spec: GestureSpec) {
        guard let index = bindings.firstIndex(where: { $0.spec == spec }) else { return }
        switch choice {
        case .app(let action):
            if keyTarget == .binding(spec) { stopKeyRecording() }
            bindings[index].action = .app(action.rawValue)
            save()
        case .sendKeys:
            if case .sendKeys = bindings[index].action { return }
            toggleKeyRecording(.binding(spec))
        case .unknown:
            break
        }
    }

    /// 기존 바인딩을 편집기에 불러온다. 조건을 바꾸는 방법은 이것뿐이다 (행 안에서는 동작과 켬·끔만)
    func edit(_ spec: GestureSpec) {
        guard let binding = bindings.first(where: { $0.spec == spec }) else { return }
        stopRecording()
        editing = spec
        draft = Draft(binding)
        message = nil
    }

    func remove(_ spec: GestureSpec) {
        if editing == spec { cancelEditing() }
        if keyTarget == .binding(spec) { stopKeyRecording() }
        bindings.removeAll { $0.spec == spec }
        save()
        layoutChanged()
    }

    /// 편집기 내용을 추가하거나(새 바인딩) 편집 중인 바인딩을 같은 자리에서 바꾼다
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
        editing = nil
        draft = Draft()
    }

    func cancelEditing() {
        editing = nil
        draft = Draft()
        message = nil
    }

    /// "추가"를 누를 수 없는 이유. 없으면 nil
    var draftProblem: String? {
        guard let spec = draft.spec else { return "만들 수 없는 조건입니다" }
        if !(2...4).contains(draft.fingers) { return "2~4손가락만 등록할 수 있습니다" }
        if let other = bindings.first(where: { $0.spec == spec }), other.spec != editing {
            return "이미 등록된 조건입니다: \(title(for: other.action))"
        }
        switch draft.choice {
        case .sendKeys where draft.chord == nil: return "보낼 키 조합을 녹화하세요"
        case .unknown(let name): return "알 수 없는 동작(\(name))은 다시 고르세요"
        default: return nil
        }
    }

    /// 추가는 되지만 알아야 할 것 (macOS 제스처와 겹침, 클릭 전달, 다른 바인딩과 겹침, 단축키와 같은 키, 권한)
    var draftWarnings: [String] {
        guard let spec = draft.spec else { return [] }
        var warnings: [String] = []
        let gesture = spec.gesture
        if gesture.fingers == 2 {
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
            warnings.append("\(other.spec.displayName)(\(title(for: other.action))) 바인딩과 겹칩니다. 장치를 지정한 쪽이 실행됩니다.")
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

    /// 제스처 녹음을 켜거나 끈다. 켜면 다음 2~4손가락 제스처로 편집기 피커를 채운다 (그동안 바인딩은 실행되지 않는다)
    func toggleGestureRecording() {
        if recordingGesture {
            stopGestureRecording()
            message = nil
            return
        }
        // 방금 녹음한 클릭 제스처의 클릭이 이 버튼에 떨어져 다시 켜지는 것을 막는다
        if let end = recordingEnd, end.duration(to: .now) < .milliseconds(500) { return }
        stopKeyRecording()
        recordingGesture = true
        recordingStart = .now
        message = "등록할 제스처를 마우스에서 하세요 (다시 누르면 취소)"
        service.recordingHandler = { [weak self] event in self?.recorded(event) }
    }

    // 녹음 중 들어온 제스처. 시작 직후 300ms 안(버퍼 잔여·녹음 버튼 클릭)은 버리고 2~4손가락만 받는다
    private func recorded(_ event: GestureEvent) {
        guard let start = recordingStart, start.duration(to: .now) >= .milliseconds(300) else { return }
        guard (2...4).contains(event.gesture.fingers) else {
            message = "2~4손가락 제스처만 등록할 수 있습니다 (\(event.gesture.fingers)손가락)"
            return
        }
        draft.device = event.device.kind
        draft.fingers = event.gesture.fingers
        draft.kind = event.gesture.kind
        if let direction = event.gesture.direction { draft.direction = direction }
        if let button = event.gesture.button { draft.button = button }
        stopGestureRecording()
        if let spec = draft.spec, let existing = bindings.first(where: { $0.spec == spec }), existing.spec != editing {
            message = "이미 등록된 조건입니다: \(spec.displayName) → \(title(for: existing.action))"
        } else {
            message = "녹음됨: \(draft.spec?.displayName ?? "")"
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

    /// 키 조합 녹화를 켜거나 끈다 (편집기 또는 기존 행)
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
        case .binding(let spec):
            guard let index = bindings.firstIndex(where: { $0.spec == spec }) else { return true }
            bindings[index].action = .sendKeys(chord)
            save()
            message = "\(spec.displayName) → 키 보내기 \(chord.displayString) 적용됨"
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
            (statusText, statusTint) = ("대기 (켜진 바인딩 없음)", .secondary)
        case .unavailable(let reason):
            (statusText, statusTint) = ("사용할 수 없음 — \(reason)", .warning)
        case .searching:
            (statusText, statusTint) = ("매직마우스를 찾는 중 (연결되면 자동 시작)", .secondary)
        case .running(let devices):
            (statusText, statusTint) = ("동작 중 · " + devices.map(\.name).joined(separator: ", "), .ok)
        case .failed(let reason):
            (statusText, statusTint) = ("시작 실패 — \(reason)", .warning)
        case .paused:
            (statusText, statusTint) = ("잠자기 중", .secondary)
        }
        if case .running = service.state { canRecordGesture = true } else { canRecordGesture = false }
        if let last = service.lastDispatch {
            let name = last.event.device.kind.displayName + " " + last.event.gesture.displayName(for: last.event.device.kind)
            if last.recorded {
                lastGestureText = "\(name) · 녹음됨"
            } else if let binding = last.binding {
                lastGestureText = "\(name) → \(title(for: binding.action))"
            } else {
                lastGestureText = "\(name) · 바인딩 없음"
            }
        } else {
            lastGestureText = "없음"
        }
    }

    // 바인딩을 저장한다. 서비스는 KVO로 따라온다
    private func save() {
        Preferences.shared.gestureBindings = bindings
    }

    // 바인딩 수가 바뀐 뒤 다음 턴에 창 높이를 다시 맞추게 한다
    private func layoutChanged() {
        Task { @MainActor [weak self] in self?.onLayoutChange?() }
    }
}

/// 설정 창의 "제스처" 탭: 상태·권한, 바인딩 목록, 새 바인딩 편집기, 안내
struct GestureSettingsView: View {
    @ObservedObject var model: GestureSettingsModel
    @AppStorage(Preferences.Key.gestureEnabled) private var enabled = true

    /// 동작 Picker의 캡처 묶음과 도구 묶음
    private static let captureActions: [AppAction] = [.captureArea, .captureFullscreen, .captureWindow, .recognizeText, .pickColor]
    private static let toolActions: [AppAction] = [.findFile, .openImage, .openSaveFolder, .blankCanvas, .toggleSleepPrevention, .showSettings]

    var body: some View {
        Form {
            Section("제스처") {
                Toggle("매직마우스 제스처 사용", isOn: $enabled)
                LabeledContent("상태") {
                    Text(model.statusText)
                        .foregroundStyle(Self.color(model.statusTint))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("마지막 제스처") {
                    Text(model.lastGestureText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("권한") {
                LabeledContent(AccessibilityPermission.settingsItemName) {
                    HStack {
                        Text(model.accessibilityGranted ? "허용됨" : "허용 필요")
                            .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                        Button("시스템 설정 열기") { model.requestAccessibility() }
                    }
                }
                Text("키 조합 보내기에만 필요합니다. 제스처 인식에는 권한이 필요 없습니다. 시스템 설정에서 허용하면 다시 실행하지 않아도 바로 반영됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("바인딩") {
                if model.bindings.isEmpty {
                    Text("아직 바인딩이 없습니다. 아래에서 추가하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.bindings) { binding in
                    GestureBindingRow(model: model, binding: binding)
                }
            }

            Section(model.editing == nil ? "새 바인딩" : "바인딩 편집") {
                editor
            }

            Section("안내") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS가 쓰는 한두 손가락 제스처와 겹치지 않게 3·4손가락을 권장합니다.")
                    Text("제스처를 가로채지는 못하므로 macOS 동작과 함께 일어나고, 클릭 제스처의 클릭은 앞 앱에도 전달됩니다.")
                    Text("캡처 화면이나 대화상자가 떠 있는 동안에는 동작을 실행하지 않습니다.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
    }

    // 새 바인딩 편집기. 행 수를 고정해 편집 중에 창 높이가 바뀌지 않게 한다
    @ViewBuilder
    private var editor: some View {
        Picker("장치", selection: $model.draft.device) {
            Text("모든 장치").tag(InputDeviceKind?.none)
            ForEach(model.deviceChoices, id: \.self) { kind in
                Text(kind.displayName).tag(InputDeviceKind?.some(kind))
            }
        }
        Picker("손가락", selection: $model.draft.fingers) {
            ForEach(2...4, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("종류", selection: $model.draft.kind) {
            ForEach(GestureKind.allCases.filter(\.isAssignable), id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        LabeledContent(model.draft.kind == .click ? "버튼" : "방향") {
            switch model.draft.kind {
            case .swipe:
                Picker("방향", selection: $model.draft.direction) {
                    ForEach(SwipeDirection.allCases, id: \.self) { Text($0.displayName(for: model.draft.device ?? .magicMouse)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            case .click:
                Picker("버튼", selection: $model.draft.button) {
                    ForEach(model.buttonChoices, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            default:
                Text("없음").foregroundStyle(.secondary)
            }
        }
        LabeledContent("녹음") {
            HStack {
                if model.recordingGesture {
                    Button("제스처를 하세요…") { model.toggleGestureRecording() }
                        .buttonStyle(.borderedProminent)
                        .help("다시 누르면 취소")
                } else {
                    Button("제스처 녹음") { model.toggleGestureRecording() }
                        .disabled(!model.canRecordGesture)
                        .help("마우스에서 제스처를 직접 해 위 값을 채웁니다")
                }
                Text(model.canRecordGesture ? "마우스에서 직접 해 위 값을 채웁니다" : "장치가 동작 중일 때 쓸 수 있습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Picker("동작", selection: $model.draft.choice) {
            Self.actionItems(current: model.draft.choice)
        }
        LabeledContent("키 조합") {
            KeyRecorderButton(
                isRecording: model.keyTarget == .draft,
                pressedModifiers: model.pressedModifiers,
                title: model.draft.chord?.displayString ?? "녹화…",
                toggle: { model.toggleKeyRecording(.draft) }
            )
        }
        .disabled(model.draft.choice != .sendKeys)
        HStack {
            Text(model.draft.spec?.displayName ?? "만들 수 없는 조건")
                .font(.caption)
            Spacer()
            if model.editing != nil {
                Button("취소") { model.cancelEditing() }
            }
            Button(model.editing == nil ? "추가" : "바꾸기") { model.commitDraft() }
                .disabled(model.draftProblem != nil)
        }
        ForEach(model.draftWarnings, id: \.self) { warning in
            Text(warning)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        Text(model.message ?? model.draftProblem ?? "피커로 고르거나 제스처 녹음을 누른 뒤 마우스에서 직접 하세요.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 동작 Picker 항목 (행과 편집기 공용). 모르는 동작은 지금 값일 때만 보인다
    @ViewBuilder
    static func actionItems(current: GestureSettingsModel.ActionChoice) -> some View {
        ForEach(captureActions) { Text($0.title).tag(GestureSettingsModel.ActionChoice.app($0)) }
        Divider()
        ForEach(toolActions) { Text($0.title).tag(GestureSettingsModel.ActionChoice.app($0)) }
        Divider()
        Text("키 조합 보내기…").tag(GestureSettingsModel.ActionChoice.sendKeys)
        if case .unknown(let name) = current {
            Text("알 수 없는 동작 (\(name))").tag(current)
        }
    }

    // 상태 문구 색
    private static func color(_ tint: GestureSettingsModel.Tint) -> Color {
        switch tint {
        case .ok: .green
        case .warning: .orange
        case .secondary: .secondary
        }
    }
}

/// 바인딩 한 줄: 조건과 켬·끔, 동작 선택(키 보내기면 키 레코더), 편집·삭제
private struct GestureBindingRow: View {
    @ObservedObject var model: GestureSettingsModel
    let binding: GestureBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle(binding.spec.displayName, isOn: Binding(
                    get: { binding.isEnabled },
                    set: { model.setEnabled($0, for: binding.spec) }
                ))
                Button { model.edit(binding.spec) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("조건 바꾸기 (아래 편집기에 불러옵니다)")
                Button { model.remove(binding.spec) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("이 바인딩 빼기")
            }
            HStack {
                Picker("동작", selection: Binding(
                    get: { model.choice(for: binding) },
                    set: { model.choose($0, for: binding.spec) }
                )) {
                    GestureSettingsView.actionItems(current: model.choice(for: binding))
                }
                .labelsHidden()
                .fixedSize()
                if model.choice(for: binding) == .sendKeys {
                    KeyRecorderButton(
                        isRecording: model.keyTarget == .binding(binding.spec),
                        pressedModifiers: model.pressedModifiers,
                        title: chordTitle,
                        toggle: { model.toggleKeyRecording(.binding(binding.spec)) }
                    )
                }
                Spacer()
            }
            .disabled(!binding.isEnabled)
        }
    }

    // 키 보내기 행의 현재 키 조합
    private var chordTitle: String {
        if case .sendKeys(let chord) = binding.action { return chord.displayString }
        return "녹화…"
    }
}
