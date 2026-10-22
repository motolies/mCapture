import Foundation
import MCaptureCore

/// 파이프라인 관찰자를 터미널 출력으로 잇는다.
/// main.swift 밖에 두는 이유: 최상위 변수는 MainActor 격리라 큐 위에서 도는 @Sendable 클로저가 잡을 수 없다
enum Output {
    /// 항상 이벤트 줄을, raw면 프레임·버튼 줄(재생이 읽는 형식)도 찍는다. 장치가 둘 이상이면 라벨을 붙인다
    static func observer(raw: Bool, multiDevice: Bool) -> GesturePipeline.Observer {
        var observer = GesturePipeline.Observer(event: { event, time in
            let prefix = String(format: "[%8.3fs] ", time) + (label(event.device, multiDevice: multiDevice).map { "[\($0)] " } ?? "")
            Console.line(prefix + event.description)
        })
        guard raw else { return observer }
        observer.frame = { device, frame, filtered, time in
            Console.line(TouchFrameLog.frameLine(frame, filtered: filtered, relativeTime: time, label: label(device, multiDevice: multiDevice)))
        }
        observer.button = { device, button, down, fromDevice, time in
            Console.line(TouchFrameLog.buttonLine(
                button, down: down, relativeTime: time, label: label(device, multiDevice: multiDevice), source: fromDevice ? "MT" : nil
            ))
        }
        return observer
    }

    /// 옵션의 임계값을 선택한 모든 장치에 적용한다 (진단 도구이므로 장치 종류를 가리지 않는다)
    static func profileResolver(_ options: Options) -> @Sendable (InputDeviceDescriptor) -> TouchGestureRecognizer.Profile? {
        { device in options.profile(for: device) }
    }

    /// 재생이 "마우스" 라벨만 읽으므로 매직마우스는 "마우스", 나머지는 장치 이름
    static func label(_ device: InputDeviceDescriptor, multiDevice: Bool) -> String? {
        guard multiDevice else { return nil }
        return device.kind == .magicMouse ? "마우스" : device.name
    }
}
