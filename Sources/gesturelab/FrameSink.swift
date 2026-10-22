import Foundation
import MCaptureCore

/// 프레임워크 스레드에서 온 프레임을 직렬 큐로 옮겨 장치별 인식기에 넘기고 결과를 출력한다
final class FrameSink: @unchecked Sendable {
    // 아래 상태는 모두 queue 안에서만 읽고 쓴다
    private let queue = DispatchQueue(label: "gesturelab.frames")
    private var recognizers: [UInt: TouchGestureRecognizer] = [:]
    private var descriptors: [UInt: InputDeviceDescriptor] = [:]
    private var labels: [UInt: String] = [:]
    private var raw = false
    private var firstTimestamp: Double?
    private var lastTimestamp: Double = 0
    private var frames = 0
    /// 가장 최근에 프레임을 보낸 장치. CGEvent는 어느 장치가 클릭됐는지 알려 주지 않아 이것으로 대신한다
    private var lastFrameDevice: UInt?

    var frameCount: Int { queue.sync { frames } }

    /// 선택한 장치마다 인식기를 만든다. 시작 전에 한 번 부른다
    func configure(options: Options, devices: [MTDevice]) {
        queue.sync {
            raw = options.raw
            for device in devices {
                labels[device.key] = device.isMagicMouse ? "마우스" : "장치\(device.index)"
                descriptors[device.key] = device.descriptor
                recognizers[device.key] = TouchGestureRecognizer(profile: options.profile(for: device.descriptor))
            }
        }
    }

    func enqueue(device: UInt, frame: TouchFrame) {
        queue.async { self.process(device: device, frame: frame) }
    }

    /// 큐에 쌓인 프레임을 모두 처리할 때까지 기다린다 (종료 직전 출력 누락 방지)
    func drain() {
        queue.sync {}
    }

    // 프레임을 인식기에 넣고, 프레임이 오래 끊길 경우를 대비해 정리 타이머를 건다 (떨어짐 판정은 프레임 내용으로 하므로 타이머는 안전장치일 뿐이다)
    private func process(device key: UInt, frame: TouchFrame) {
        frames += 1
        if firstTimestamp == nil { firstTimestamp = frame.timestamp }
        lastTimestamp = frame.timestamp
        lastFrameDevice = key
        guard let profile = recognizers[key]?.profile else { return }
        if raw {
            let filtered = TouchGestureRecognizer.filter(frame.contacts, profile: profile)
            Console.line(TouchFrameLog.frameLine(frame, filtered: filtered, relativeTime: relative(frame.timestamp), label: label(for: key)))
        }
        // 사전 안에서 제자리 변경한다 (복사 후 재대입하면 추적 사전이 프레임마다 복사된다)
        guard let events = recognizers[key]?.process(frame) else { return }
        let generation = recognizers[key]?.generation ?? 0
        emit(events, device: key)
        guard recognizers[key]?.isTracking == true else { return }
        let delay = Int(profile.thresholds.staleSeconds * 1000)
        queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
            guard let self, let flushed = recognizers[key]?.flush(ifGeneration: generation) else { return }
            emit(flushed, device: key)
        }
    }

    /// 이벤트 탭이 알려 준 물리 버튼. 최근에 프레임을 보낸 장치(없으면 유일한 장치)의 인식기에 넘긴다.
    /// raw 모드에서는 재생이 읽을 수 있는 "t=… 버튼=왼쪽 누름" 줄을 남긴다
    func button(_ button: MouseButton, down: Bool) {
        queue.async { [self] in
            let key = lastFrameDevice ?? (recognizers.count == 1 ? recognizers.keys.first : nil)
            guard let key, recognizers[key] != nil else {
                if raw { Console.line("버튼=\(button.displayName) \(down ? "누름" : "뗌") (프레임을 보낸 장치가 아직 없음)") }
                return
            }
            handleButton(button, down: down, device: key, source: nil)
        }
    }

    /// 비공개 MT 버튼 콜백. 실측으로 (버튼, 이전 버튼)이며 1=왼쪽, 2=오른쪽, 0=뗌이다 (누름 1·0, 뗌 0·1, 오른쪽 누름 2·0).
    /// 장치를 알려 주고 이벤트 탭보다 11~22ms 먼저 오므로 클릭의 1순위 출처다. raw에서는 재생용 "t=… 버튼=왼쪽 누름 MT" 줄을 남긴다
    func mtButton(device: UInt, state: Int32, previous: Int32) {
        queue.async { [self] in
            guard recognizers[device] != nil else { return }
            let code = state != 0 ? state : previous
            let button: MouseButton = code == 1 ? .left : code == 2 ? .right : .other(Int(code))
            handleButton(button, down: state != 0 && previous == 0, device: device, source: "MT")
        }
    }

    // 버튼 줄을 남기고 누름이면 인식기에 넘긴다. 시각은 마지막 프레임 시각이다 (두 경로의 중복 제거가 같은 시계를 전제한다)
    private func handleButton(_ button: MouseButton, down: Bool, device key: UInt, source: String?) {
        if raw {
            Console.line(TouchFrameLog.buttonLine(button, down: down, relativeTime: relative(lastTimestamp), label: label(for: key), source: source))
        }
        guard down, let events = recognizers[key]?.buttonDown(button, at: lastTimestamp) else { return }
        emit(events, device: key)
    }

    private func emit(_ events: [RecognizedGesture], device key: UInt) {
        guard !events.isEmpty, let descriptor = descriptors[key] else { return }
        let prefix = String(format: "[%8.3fs] ", relative(lastTimestamp)) + (label(for: key).map { "[\($0)] " } ?? "")
        for event in events {
            let gestureEvent = GestureEvent(device: descriptor, gesture: event.gesture, metrics: event.metrics, deviceTime: lastTimestamp)
            Console.line(prefix + gestureEvent.description)
        }
    }

    // 장치가 둘 이상일 때만 라벨을 붙인다
    private func label(for key: UInt) -> String? {
        recognizers.count > 1 ? (labels[key] ?? "?") : nil
    }

    // 첫 프레임 기준 상대 시각
    private func relative(_ timestamp: Double) -> Double {
        timestamp - (firstTimestamp ?? timestamp)
    }
}

/// 콜백은 전역 하나를 참조한다. C 함수 포인터는 컨텍스트를 캡처할 수 없고, 등록·해제에 같은 포인터를 넘겨야 한다
let sink = FrameSink()

/// 비공개 MTRegisterButtonStateCallback용. 실측: (장치, 새 상태, 이전 상태). 세 번째 정수는 쓰레기 값(-8 고정)이라 버린다
let mtButtonCallback: MTButtonCallback = { device, state, previous, _ in
    sink.mtButton(device: UInt(bitPattern: device), state: state, previous: previous)
    return 0
}

let frameCallback: MTFrameCallback = { device, touches, count, timestamp, _ in
    sink.enqueue(
        device: UInt(bitPattern: device),
        frame: TouchFrame(timestamp: timestamp, contacts: TouchRecord.copy(from: touches, count: count))
    )
    return 0
}
