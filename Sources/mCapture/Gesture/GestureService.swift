import AppKit
import MCaptureCore

/// 매직마우스 제스처를 받아 바인딩된 동작을 실행한다.
///
/// 켜진 바인딩이 없고 설정 창도 닫혀 있으면 장치를 열지 않는다 (비공개 MultitouchSupport를 건드리지 않음).
/// 장치가 붙고 빠지거나 잠자기에서 깨면 소스를 새로 만들고, 설정(켜짐·바인딩)은 UserDefaults KVO로 반영한다.
/// 앱에서는 `GesturePipeline.Observer`를 쓰지 않는다: 메인이 `stop()`에서 파이프라인 큐를 기다리는 동안 그 큐가 메인을 기다리면 교착한다
@MainActor
final class GestureService: NSObject {
    enum State: Equatable {
        /// 설정에서 꺼짐
        case off
        /// 켜져 있지만 켜진 바인딩이 없고 설정 창도 닫혀 있어 장치를 열지 않음
        case idle
        /// MultitouchSupport를 열 수 없음 (다시 시도하지 않음)
        case unavailable(String)
        /// 다룰 수 있는 장치가 없음. 연결 알림을 기다림
        case searching
        case running([InputDeviceDescriptor])
        /// 장치 시작 실패 (재시도 뒤에도)
        case failed(String)
        /// 잠자기 중
        case paused
    }

    /// 마지막으로 받은 제스처와 처리 결과 (설정 화면 표시용)
    struct Dispatch: Equatable {
        var event: GestureEvent
        var binding: GestureBinding?
        /// 녹음기로 보냈는지
        var recorded: Bool
    }

    private(set) var state: State = .off {
        didSet { if state != oldValue { onChange?() } }
    }
    private(set) var lastDispatch: Dispatch?
    private(set) var bindings: [GestureBinding] = []
    /// 바인딩된 동작 실행 (AppDelegate). 키 보내기가 클릭 제스처인지 알아야 해서 바인딩째 넘긴다
    var onAction: ((GestureBinding) -> Void)?
    /// true를 돌려주면 동작을 실행하지 않는다 (캡처 중·대화상자 중)
    var shouldIgnoreActions: (() -> Bool)?
    /// 키 녹화 중에는 동작을 실행하지 않는다 (보낸 키가 레코더에 들어가지 않게)
    var actionsPaused = false
    /// 상태나 마지막 제스처가 바뀌었을 때 (설정 화면 갱신)
    var onChange: (() -> Void)?
    /// 설정 화면이 제스처를 녹음하는 동안 걸린다. 걸려 있으면 바인딩 대신 여기로 보내고 동작은 실행하지 않는다
    var recordingHandler: ((GestureEvent) -> Void)? {
        didSet { applyState() }
    }
    /// 설정 창이 열려 있는 동안 true. 바인딩이 없어도 상태와 마지막 제스처를 보여 주려고 장치를 연다
    var settingsVisible = false {
        didSet { applyState() }
    }

    private let preferences: Preferences
    private var api: MultitouchAPI?
    private var source: MultitouchInputSource?
    private var eventTask: Task<Void, Never>?
    /// 소스를 만들거나 닫을 때마다 올린다. 옛 Task가 버퍼에서 늦게 꺼낸 이벤트를 버리는 기준
    private var generation = 0
    private var watcher: MultitouchDeviceWatcher?
    private var restartTask: Task<Void, Never>?
    private var asleep = false
    private var started = false
    private var unavailableReason: String?
    /// 진단용: 소스를 다시 만든 횟수
    private var restarts = 0

    private static let observedKeys = [Preferences.Key.gestureEnabled, Preferences.Key.gestureBindings]

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    /// 설정 KVO와 잠자기·세션 알림을 걸고 지금 설정대로 장치를 연다
    func start() {
        guard !started else { return }
        started = true
        for key in Self.observedKeys {
            preferences.defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        // 잠자기·세션 알림은 기본 센터가 아니라 NSWorkspace의 센터로 온다
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.asleep = true
                self?.applyState()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.asleep = false
                self?.scheduleRestart(after: .seconds(2))
            }
        }
        // 다른 사용자 세션에서 돌아왔을 때. 비활성이 될 때는 닫지 않는다 (복귀 알림을 못 받으면 죽은 채 남는 쪽이 더 나쁘다)
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRestart(after: .seconds(1)) }
        }
        applyState()
    }

    /// 종료 때 소스와 워처를 멈춘다. 콜백 밖(메인)에서만 부른다
    func stop() {
        restartTask?.cancel()
        restartTask = nil
        close()
        watcher?.stop()
        watcher = nil
    }

    // MARK: - 상태 전이

    // 설정·창·녹음 상태로 소스를 열어야 하는지 정하고 지금 상태를 맞춘다. 바인딩도 여기서 다시 읽는다
    private func applyState() {
        guard started else { return }
        let decoded = GestureBindingList.decode(preferences.defaults.stringArray(forKey: Preferences.Key.gestureBindings) ?? [])
        bindings = decoded.bindings
        for line in decoded.rejected {
            Log.gesture.error("바인딩 줄을 읽을 수 없음: \(line, privacy: .public)")
        }
        let enabled = preferences.gestureEnabled
        let wantsSource = enabled && !asleep && (bindings.contains(where: \.isEnabled) || settingsVisible || recordingHandler != nil)
        if wantsSource {
            if source == nil, unavailableReason == nil { open() }
            if watcher == nil, unavailableReason == nil { startWatcher() }
        } else {
            close()
            if !enabled {
                watcher?.stop()
                watcher = nil
            }
            state = !enabled ? .off : asleep ? .paused : .idle
        }
    }

    // 프레임워크 로드 → 장치 열거 → 소스 생성·시작 → 이벤트 소비 Task. 실패 사유는 상태에 남긴다
    private func open() {
        close()
        if api == nil {
            do {
                api = try MultitouchAPI.load()
            } catch {
                unavailableReason = String(describing: error)
                state = .unavailable(String(describing: error))
                Log.gesture.error("MultitouchSupport를 열 수 없음: \(String(describing: error), privacy: .public)")
                return
            }
        }
        guard let api else { return }
        let outcome = MultitouchDeviceEnumerator.enumerate(api: api)
        for note in outcome.notes {
            Log.gesture.debug("\(note, privacy: .public)")
        }
        // 프로필이 없는 장치(내장 트랙패드 등)는 소스가 스스로 뺀다
        let candidate = MultitouchInputSource(api: api, devices: outcome.devices)
        guard !candidate.devices.isEmpty else {
            state = .searching
            Log.gesture.info("다룰 수 있는 멀티터치 장치가 없음 (열거 \(outcome.devices.count)개)")
            return
        }
        do {
            try candidate.start()
        } catch {
            state = .failed(String(describing: error))
            Log.gesture.error("장치 시작 실패: \(String(describing: error), privacy: .public)")
            return
        }
        generation += 1
        let current = generation
        source = candidate
        // 취소되거나 소스가 끝나도 버퍼에 남은 이벤트가 먼저 나오므로 세대와 취소 여부를 매번 확인한다
        eventTask = Task { @MainActor [weak self] in
            for await event in candidate.events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event, generation: current)
            }
        }
        state = .running(candidate.devices)
        Log.gesture.info("제스처 소스 시작: \(candidate.devices.map(\.name).joined(separator: ", "), privacy: .public)")
    }

    // 이벤트 Task를 취소하고 소스를 멈춘다. 세대를 올려 늦은 이벤트를 버린다. 참조를 바로 놓아 deinit에 맡기지 않는다
    private func close() {
        generation += 1
        eventTask?.cancel()
        eventTask = nil
        source?.stop()
        source = nil
    }

    // 장치가 붙고 빠질 때 소스를 다시 만들도록 IOKit 알림을 건다
    private func startWatcher() {
        let watcher = MultitouchDeviceWatcher { change in
            Task { @MainActor [weak self] in
                Log.gesture.info("멀티터치 장치 \(change == .attached ? "연결" : "해제", privacy: .public)")
                self?.scheduleRestart(after: .seconds(1))
            }
        }
        guard watcher.start() else {
            Log.gesture.error("장치 연결 알림을 걸 수 없음")
            return
        }
        self.watcher = watcher
    }

    /// 잠시 뒤 소스를 다시 만든다 (디바운스: 먼저 잡힌 예약은 취소). 장치가 없거나 시작에 실패하면 1초 간격으로 최대 3회 더 시도
    private func scheduleRestart(after delay: Duration, attempt: Int = 0) {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.restart(attempt: attempt)
        }
    }

    // 소스를 닫고 설정대로 다시 연다. 열려야 하는데 못 열었으면 재시도를 예약한다
    private func restart(attempt: Int) {
        close()
        restarts += 1
        applyState()
        switch state {
        case .searching, .failed:
            if attempt < 3 {
                scheduleRestart(after: .seconds(1), attempt: attempt + 1)
            } else {
                Log.gesture.error("장치를 다시 열지 못함: \(String(describing: self.state), privacy: .public)")
            }
        default:
            break
        }
    }

    // MARK: - 이벤트

    // 세대가 지난 이벤트는 버리고, 녹음 중이면 녹음기로, 아니면 바인딩을 찾아 실행한다. 진단용 종류(이동·길게 누름)는 보여 주지 않는다
    private func handle(_ event: GestureEvent, generation: Int) {
        guard generation == self.generation, event.gesture.kind.isAssignable else { return }
        if let recordingHandler {
            lastDispatch = Dispatch(event: event, binding: nil, recorded: true)
            onChange?()
            recordingHandler(event)
            return
        }
        let binding = GestureBindingList.match(event, in: bindings)
        lastDispatch = Dispatch(event: event, binding: binding, recorded: false)
        onChange?()
        guard let binding else { return }
        if actionsPaused || shouldIgnoreActions?() == true {
            Log.gesture.debug("무시: \(binding.spec.stringValue, privacy: .public) (키 녹화·캡처·대화상자 중)")
            return
        }
        Log.gesture.info("\(binding.spec.stringValue, privacy: .public) → \(binding.action.stringValue, privacy: .public)")
        onAction?(binding)
    }

    // UserDefaults KVO. 바뀐 스레드와 무관하게 메인에서 반영한다
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in self?.applyState() }
    }

    #if DEBUG
    /// 합성 이벤트를 넣는다 (mcapture-dev://debug/gesture?spec=). 장치가 없으면 가짜 서술자를 쓴다
    func debugInject(_ spec: GestureSpec) {
        let device = source?.devices.first { spec.device == nil || $0.kind == spec.device }
            ?? InputDeviceDescriptor(id: 0, kind: spec.device ?? .magicMouse, name: "debug", surface: .magicMouse2)
        handle(GestureEvent(device: device, gesture: spec.gesture, metrics: .zero, deviceTime: 0), generation: generation)
    }

    /// 상태 요약 (mcapture-dev://debug/gesture-stats?path=)
    func debugStats() -> [String: Any] {
        var last: [String: Any] = [:]
        if let lastDispatch {
            last = [
                "gesture": lastDispatch.event.gesture.displayName(for: lastDispatch.event.device.kind),
                "binding": lastDispatch.binding?.stringValue ?? "",
                "recorded": lastDispatch.recorded,
            ]
        }
        return [
            "enabled": preferences.gestureEnabled,
            "state": String(describing: state),
            "devices": (source?.devices ?? []).map { ["id": String($0.id, radix: 16), "name": $0.name, "kind": $0.kind.rawValue] },
            "bindings": GestureBindingList.encode(bindings),
            "lastDispatch": last,
            "generation": generation,
            "restarts": restarts,
            "accessibility": AccessibilityPermission.isGranted,
            "settingsVisible": settingsVisible,
            "recording": recordingHandler != nil,
        ]
    }
    #endif
}
