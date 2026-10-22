import Foundation
import MCaptureCore

/// --raw 로그를 다시 읽어 인식기에 흘려 넣는다.
/// 사용자가 다시 제스처를 해 주지 않아도, 같은 프레임으로 인식기 수정의 효과를 확인하기 위한 것
enum Replay {
    /// 로그 파일의 마우스 프레임을 순서대로 인식기에 넣고 이벤트를 찍는다.
    /// 끊김 정리 타이머는 재생에서 의미가 없어 쓰지 않는다 (떨어짐 판정은 프레임 내용으로 한다)
    static func run(path: String, options: Options) {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            Console.error("로그를 읽을 수 없다: \(path)")
            exit(1)
        }
        let surface = TouchFrameLog.surfaceSize(inHeader: text) ?? .magicMouse2
        let device = InputDeviceDescriptor(id: 0, kind: .magicMouse, name: "재생", surface: surface)
        var recognizer = TouchGestureRecognizer(profile: options.profile(for: device))
        var frames = 0
        var events = 0
        for line in text.split(separator: "\n") {
            guard let entry = TouchFrameLog.parse(String(line)) else { continue }
            let produced: [RecognizedGesture]
            let time: Double
            switch entry {
            case .frame(let frame, let label):
                guard label == nil || label == "마우스" else { continue }
                frames += 1
                time = frame.timestamp
                produced = recognizer.process(frame)
            case .button(let button, let down, let deviceTime, let label):
                guard label == nil || label == "마우스" else { continue }
                time = deviceTime
                produced = down ? recognizer.buttonDown(button, at: deviceTime) : []
            }
            for recognized in produced {
                events += 1
                let event = GestureEvent(device: device, gesture: recognized.gesture, metrics: recognized.metrics, deviceTime: time)
                Console.line(String(format: "[%8.3fs] ", time) + event.description)
            }
        }
        Console.line("재생 끝: 프레임 \(frames)개, 이벤트 \(events)개, 표면 \(surface.widthMM) x \(surface.heightMM)mm (\(path))")
    }
}
