import Foundation

/// 프레임을 직렬 큐로 옮겨 장치별 인식기에 넣고, 나온 제스처를 관찰자에게 전한다.
///
/// C 콜백이 넘겨주는 값을 큐로 옮기는 박스라 Sendable 검사를 할 수 없다.
/// 가변 상태(recognizers·devices·시각·최근 장치·frames)는 모두 queue 안에서만 읽고 쓴다 (FileEventWatcher와 같은 구조).
/// 버튼 시각은 항상 마지막 프레임의 장치 시각이다: MT 콜백과 이벤트 탭이 같은 클릭을 둘 다 알려 주므로
/// 인식기의 150ms 중복 제거가 같은 시계를 전제한다. 벽시계를 넘기면 깨진다.
/// addDevice·removeDevice·drain은 큐를 기다리므로 관찰자 안에서 부르면 안 된다
public final class GesturePipeline: @unchecked Sendable {
    /// 큐 위에서 동기로 불리는 관찰자. 프레임 줄·버튼 줄·이벤트 줄의 순서가 보존되므로 CLI 기록에 쓴다.
    /// 앱은 소스의 AsyncStream을 쓴다. sessionTime은 첫 프레임 기준 상대 초
    public struct Observer: Sendable {
        public typealias FrameHook = @Sendable (InputDeviceDescriptor, TouchFrame, TouchGestureRecognizer.Filtered, _ sessionTime: Double) -> Void
        public typealias ButtonHook = @Sendable (InputDeviceDescriptor, MouseButton, _ down: Bool, _ fromDevice: Bool, _ sessionTime: Double) -> Void
        public typealias EventHook = @Sendable (GestureEvent, _ sessionTime: Double) -> Void

        /// 프레임마다. 걸러낸 결과를 함께 주므로 raw 출력이 필터를 다시 돌리지 않는다. 없으면 필터 결과를 만들지 않는다
        public var frame: FrameHook?
        /// 버튼 누름·뗌마다. fromDevice는 장치가 알려 준 버튼(MT 콜백)인지, 장치를 모르는 경로(이벤트 탭)인지
        public var button: ButtonHook?
        /// 인식된 제스처마다
        public var event: EventHook?

        public init(frame: FrameHook? = nil, button: ButtonHook? = nil, event: EventHook? = nil) {
            self.frame = frame
            self.button = button
            self.event = event
        }
    }

    private let queue = DispatchQueue(label: "MCaptureCore.GesturePipeline")
    private let observer: Observer
    private var recognizers: [UInt64: TouchGestureRecognizer] = [:]
    private var devices: [UInt64: InputDeviceDescriptor] = [:]
    private var firstDeviceTime: Double?
    private var lastDeviceTime: Double = 0
    /// 가장 최근에 프레임을 보낸 장치. CGEvent는 어느 장치가 클릭됐는지 알려 주지 않아 이것으로 대신한다
    private var lastFrameDevice: UInt64?
    private var frames = 0

    public init(observer: Observer = Observer()) {
        self.observer = observer
    }

    /// 지금까지 받은 프레임 수 (권한 안내 등 진단용)
    public var frameCount: Int { queue.sync { frames } }

    /// 등록된 장치들
    public var deviceList: [InputDeviceDescriptor] { queue.sync { Array(devices.values) } }

    /// 장치와 그 인식기를 등록한다. 같은 id면 교체한다
    public func addDevice(_ device: InputDeviceDescriptor, recognizer: TouchGestureRecognizer) {
        queue.sync {
            devices[device.id] = device
            recognizers[device.id] = recognizer
        }
    }

    /// 장치를 뺀다. 이후 그 장치의 프레임은 세기만 하고 무시한다
    public func removeDevice(_ id: UInt64) {
        queue.sync {
            devices[id] = nil
            recognizers[id] = nil
            if lastFrameDevice == id { lastFrameDevice = nil }
        }
    }

    /// 장치의 프레임 하나. 어느 스레드에서 불러도 된다
    public func ingest(_ frame: TouchFrame, from id: UInt64) {
        queue.async { self.process(frame, from: id) }
    }

    /// 장치가 알려 준 물리 버튼 (MT 버튼 콜백)
    public func buttonChanged(_ button: MouseButton, down: Bool, device id: UInt64) {
        queue.async { self.handleButton(button, down: down, device: id, fromDevice: true) }
    }

    /// 장치를 모르는 물리 버튼 (CGEventTap, CLI 보조 경로). 최근에 프레임을 보낸 장치(없으면 유일한 장치)로 보낸다
    public func buttonChanged(_ button: MouseButton, down: Bool) {
        queue.async {
            guard let id = self.lastFrameDevice ?? (self.recognizers.count == 1 ? self.recognizers.keys.first : nil) else { return }
            self.handleButton(button, down: down, device: id, fromDevice: false)
        }
    }

    /// 큐에 쌓인 프레임을 모두 처리할 때까지 기다린다 (종료 직전 출력 누락 방지)
    public func drain() {
        queue.sync {}
    }

    // 프레임을 인식기에 넣고, 프레임이 오래 끊길 경우를 대비해 정리 타이머를 건다 (떨어짐 판정은 프레임 내용으로 하므로 타이머는 안전장치일 뿐이다)
    private func process(_ frame: TouchFrame, from id: UInt64) {
        frames += 1
        if firstDeviceTime == nil { firstDeviceTime = frame.timestamp }
        lastDeviceTime = frame.timestamp
        lastFrameDevice = id
        guard let device = devices[id], let profile = recognizers[id]?.profile else { return }
        if let hook = observer.frame {
            hook(device, frame, TouchGestureRecognizer.filter(frame.contacts, profile: profile), sessionTime(frame.timestamp))
        }
        // 사전 안에서 제자리 변경한다 (복사 후 재대입하면 추적 사전이 프레임마다 복사된다)
        guard let events = recognizers[id]?.process(frame) else { return }
        let generation = recognizers[id]?.generation ?? 0
        emit(events, device: device)
        guard recognizers[id]?.isTracking == true else { return }
        let delay = Int(profile.thresholds.staleSeconds * 1000)
        queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
            guard let self, let device = devices[id], let flushed = recognizers[id]?.flush(ifGeneration: generation) else { return }
            emit(flushed, device: device)
        }
    }

    // 버튼을 관찰자에게 알리고, 누름이면 인식기에 넘긴다
    private func handleButton(_ button: MouseButton, down: Bool, device id: UInt64, fromDevice: Bool) {
        guard let device = devices[id] else { return }
        observer.button?(device, button, down, fromDevice, sessionTime(lastDeviceTime))
        guard down, let events = recognizers[id]?.buttonDown(button, at: lastDeviceTime) else { return }
        emit(events, device: device)
    }

    // 인식 결과를 장치가 붙은 이벤트로 바꿔 관찰자에게 준다
    private func emit(_ events: [RecognizedGesture], device: InputDeviceDescriptor) {
        guard let hook = observer.event, !events.isEmpty else { return }
        let time = sessionTime(lastDeviceTime)
        for recognized in events {
            hook(GestureEvent(device: device, gesture: recognized.gesture, metrics: recognized.metrics, deviceTime: lastDeviceTime), time)
        }
    }

    // 첫 프레임 기준 상대 시각
    private func sessionTime(_ deviceTime: Double) -> Double {
        deviceTime - (firstDeviceTime ?? deviceTime)
    }
}
