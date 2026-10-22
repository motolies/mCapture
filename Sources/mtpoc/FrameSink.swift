import Foundation

/// 콜백 한 번 = 프레임 하나. 장치 키와 접촉 배열을 값으로 복사한 것
struct Frame: Sendable {
    let device: UInt
    let timestamp: Double
    let touches: [Touch]
}

/// 프레임워크 스레드에서 온 프레임을 직렬 큐로 옮겨 장치별 인식기에 넘기고 결과를 출력한다
final class FrameSink: @unchecked Sendable {
    // 아래 상태는 모두 queue 안에서만 읽고 쓴다
    private let queue = DispatchQueue(label: "mtpoc.frames")
    private var recognizers: [UInt: GestureRecognizer] = [:]
    private var labels: [UInt: String] = [:]
    private var raw = false
    private var firstTimestamp: Double?
    private var lastTimestamp: Double = 0
    private var frames = 0

    var frameCount: Int { queue.sync { frames } }

    /// 선택한 장치마다 인식기를 만든다. 시작 전에 한 번 부른다
    func configure(options: Options, devices: [MTDevice]) {
        queue.sync {
            raw = options.raw
            for device in devices {
                labels[device.key] = device.isMagicMouse ? "마우스" : "장치\(device.index)"
                recognizers[device.key] = GestureRecognizer(config: .init(
                    thresholds: options.thresholds,
                    countedStates: options.states,
                    filterResting: options.filter,
                    widthMM: device.widthMM,
                    heightMM: device.heightMM
                ))
            }
        }
    }

    func enqueue(_ frame: Frame) {
        queue.async { self.process(frame) }
    }

    /// 큐에 쌓인 프레임을 모두 처리할 때까지 기다린다 (종료 직전 출력 누락 방지)
    func drain() {
        queue.sync {}
    }

    // 프레임을 인식기에 넣고, 프레임이 끊길 경우를 대비해 flush 타이머를 건다
    private func process(_ frame: Frame) {
        frames += 1
        if firstTimestamp == nil { firstTimestamp = frame.timestamp }
        lastTimestamp = frame.timestamp
        guard var recognizer = recognizers[frame.device] else { return }
        let label = recognizers.count > 1 ? "[\(labels[frame.device] ?? "?")] " : ""
        if raw { printRaw(frame, config: recognizer.config, label: label) }
        let events = recognizer.process(timestamp: frame.timestamp, touches: frame.touches)
        let generation = recognizer.generation
        let tracking = recognizer.isTracking
        recognizers[frame.device] = recognizer
        emit(events, label: label)
        guard tracking else { return }
        let key = frame.device
        let delay = Int(recognizer.config.thresholds.graceSeconds * 2000)
        queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { [self] in
            guard var stale = recognizers[key] else { return }
            let flushed = stale.flush(ifGeneration: generation)
            recognizers[key] = stale
            emit(flushed, label: label)
        }
    }

    private func emit(_ events: [GestureEvent], label: String) {
        guard !events.isEmpty else { return }
        let relative = lastTimestamp - (firstTimestamp ?? lastTimestamp)
        for event in events {
            Console.line(String(format: "[%8.3fs] ", relative) + label + event.description)
        }
    }

    // 프레임의 접촉을 전부 찍는다. 걸러진 접촉은 x 표시. 앞 두 접촉의 timestamp 차가 0이면 오프셋·stride가 맞다는 뜻
    private func printRaw(_ frame: Frame, config: GestureRecognizer.Config, label: String) {
        let relative = frame.timestamp - (firstTimestamp ?? frame.timestamp)
        let filtered = GestureRecognizer.filter(frame.touches, config: config)
        let keptPaths = Set(filtered.kept.map(\.pathIndex))
        let parts = frame.touches.map { touch -> String in
            let mark = keptPaths.contains(touch.pathIndex) ? " " : "x"
            return "\(mark)p\(touch.pathIndex) \(touch.stateName) (\(Format.f3(touch.x)),\(Format.f3(touch.y))) z=\(Format.f2(touch.zTotal))"
        }
        let deltas = frame.touches.prefix(2).map { String(format: "%.3f", $0.timestamp - frame.timestamp) }
        var line = label + String(format: "t=%8.3f n=%d/%d", relative, filtered.kept.count, frame.touches.count)
        if filtered.palmFrame { line += " 손바닥→무시" }
        if !parts.isEmpty { line += " | " + parts.joined(separator: " | ") }
        if !deltas.isEmpty { line += "  dt=" + deltas.joined(separator: ",") }
        Console.line(line)
    }
}

/// 콜백은 전역 하나를 참조한다. C 함수 포인터는 컨텍스트를 캡처할 수 없고, 등록·해제에 같은 포인터를 넘겨야 한다
let sink = FrameSink()

let frameCallback: MTFrameCallback = { device, touches, count, timestamp, _ in
    sink.enqueue(Frame(
        device: UInt(bitPattern: device),
        timestamp: timestamp,
        touches: TouchRecord.copy(from: touches, count: count)
    ))
    return 0
}
