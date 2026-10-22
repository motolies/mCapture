import Foundation

/// 제스처 종류. rawValue는 트리거 문자열에 들어가므로 바꾸지 않는다
public enum GestureKind: String, CaseIterable, Sendable {
    case tap
    case longPress = "longpress"
    case click
    case swipe
    /// 진단용: 탭 범위는 벗어났지만 스와이프에는 못 미친 이동
    case move
    /// 진단용: 너무 오래 눌려 쉬는 손가락으로 버린 묶음
    case hold

    /// 트리거로 등록할 수 있는 종류인지. 진단용은 설정 화면에서 숨긴다
    public var isAssignable: Bool { self != .move && self != .hold }

    /// 화면 표시용 이름
    public var displayName: String {
        switch self {
        case .tap: "탭"
        case .longPress: "길게 탭"
        case .click: "클릭"
        case .swipe: "스와이프"
        case .move: "이동(미분류)"
        case .hold: "길게 누름"
        }
    }
}

/// 스와이프 방향. y는 0이 손바닥 쪽, 1이 손끝 쪽이라 +y가 up이다 (매직마우스 실측: 앞으로 밀면 dy > 0)
public enum SwipeDirection: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    /// 장치에 맞는 표시 이름. 마우스는 앞·뒤, 트랙패드는 위·아래가 자연스럽다
    public func displayName(for kind: InputDeviceKind) -> String {
        switch self {
        case .left: "왼쪽 ←"
        case .right: "오른쪽 →"
        case .up: kind == .magicMouse ? "앞 ↑" : "위 ↑"
        case .down: kind == .magicMouse ? "뒤 ↓" : "아래 ↓"
        }
    }
}

/// 제스처의 정체: 종류·손가락 수·(스와이프) 방향·(클릭) 버튼. 트리거 조건과 비교하는 단위다.
/// 이름을 `Gesture`로 하지 않은 이유: 앱 쪽에서 SwiftUI의 `Gesture` 프로토콜과 이름이 겹친다
public struct InputGesture: Hashable, Sendable {
    public var kind: GestureKind
    public var fingers: Int
    public var direction: SwipeDirection?
    public var button: MouseButton?

    public init(kind: GestureKind, fingers: Int, direction: SwipeDirection? = nil, button: MouseButton? = nil) {
        self.kind = kind
        self.fingers = fingers
        self.direction = direction
        self.button = button
    }

    public static func tap(fingers: Int) -> InputGesture { .init(kind: .tap, fingers: fingers) }
    public static func longPress(fingers: Int) -> InputGesture { .init(kind: .longPress, fingers: fingers) }
    public static func click(fingers: Int, button: MouseButton) -> InputGesture { .init(kind: .click, fingers: fingers, button: button) }
    public static func swipe(fingers: Int, direction: SwipeDirection) -> InputGesture { .init(kind: .swipe, fingers: fingers, direction: direction) }
    public static func move(fingers: Int) -> InputGesture { .init(kind: .move, fingers: fingers) }
    public static func hold(fingers: Int) -> InputGesture { .init(kind: .hold, fingers: fingers) }

    /// 화면 표시용 이름. 예: "3손가락 스와이프 왼쪽 ←", "4손가락 클릭(오른쪽)"
    public func displayName(for device: InputDeviceKind) -> String {
        switch kind {
        case .tap, .longPress, .move, .hold:
            "\(fingers)손가락 \(kind.displayName)"
        case .click:
            "\(fingers)손가락 클릭(\((button ?? .left).displayName))"
        case .swipe:
            "\(fingers)손가락 스와이프" + (direction.map { " " + $0.displayName(for: device) } ?? "")
        }
    }
}

/// 분류에 쓴 측정값. 임계값을 조정할 때 근거가 된다
public struct GestureMetrics: Sendable, Equatable {
    public var dxMM: Double
    public var dyMM: Double
    public var duration: Double

    public init(dxMM: Double, dyMM: Double, duration: Double) {
        self.dxMM = dxMM
        self.dyMM = dyMM
        self.duration = duration
    }

    public static let zero = GestureMetrics(dxMM: 0, dyMM: 0, duration: 0)
}

/// 인식기의 출력. 어느 장치인지는 인식기가 모르므로 파이프라인이 `GestureEvent`로 감싼다
public struct RecognizedGesture: Sendable, Equatable {
    public var gesture: InputGesture
    public var metrics: GestureMetrics

    public init(gesture: InputGesture, metrics: GestureMetrics = .zero) {
        self.gesture = gesture
        self.metrics = metrics
    }
}

/// 장치가 붙은 제스처 이벤트. 앱의 트리거 매칭과 CLI 출력이 받는 단위다
public struct GestureEvent: Sendable, Equatable, CustomStringConvertible {
    public var device: InputDeviceDescriptor
    public var gesture: InputGesture
    public var metrics: GestureMetrics
    /// 프레임의 시각 (장치 시계, 벽시계가 아니다)
    public var deviceTime: Double

    public init(device: InputDeviceDescriptor, gesture: InputGesture, metrics: GestureMetrics, deviceTime: Double) {
        self.device = device
        self.gesture = gesture
        self.metrics = metrics
        self.deviceTime = deviceTime
    }

    /// 진단 출력 한 줄 (CLI·재생 로그 형식). 측정값까지 적는다
    public var description: String {
        let n = gesture.fingers
        switch gesture.kind {
        case .tap:
            return "\(n)손가락 탭            \(GestureFormat.seconds(metrics.duration))"
        case .longPress:
            return "\(n)손가락 길게 탭       \(GestureFormat.seconds(metrics.duration))"
        case .click:
            return "\(n)손가락 클릭(\((gesture.button ?? .left).displayName))"
        case .swipe:
            let direction = gesture.direction?.displayName(for: device.kind) ?? "?"
            return "\(n)손가락 스와이프 \(direction)  dx=\(GestureFormat.mm(metrics.dxMM)) dy=\(GestureFormat.mm(metrics.dyMM)) \(GestureFormat.seconds(metrics.duration))"
        case .move:
            return "\(n)손가락 이동(미분류)   dx=\(GestureFormat.mm(metrics.dxMM)) dy=\(GestureFormat.mm(metrics.dyMM)) \(GestureFormat.seconds(metrics.duration))"
        case .hold:
            return "\(n)손가락 길게 누름 → 쉬는 손가락으로 보고 무시"
        }
    }
}

/// 숫자 표기 도우미
enum GestureFormat {
    static func mm(_ value: Double) -> String { String(format: "%+.1fmm", value) }
    static func seconds(_ value: Double) -> String { String(format: "%.0fms", value * 1000) }
    static func f3(_ value: Float) -> String { String(format: "%.3f", Double(value)) }
    static func f2(_ value: Float) -> String { String(format: "%.2f", Double(value)) }
}
