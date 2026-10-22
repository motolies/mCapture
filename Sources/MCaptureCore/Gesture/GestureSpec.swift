import Foundation

/// 제스처 트리거 조건. `HotKeySpec`의 제스처 판으로, 설정에는 문자열로 저장한다.
///
/// 문자열 형식은 `장치+손가락+종류[+방향|+버튼]`이고 토큰 순서는 고정이다.
/// 예: `mouse+3+swipe+left`, `any+2+tap`, `mouse+4+click+right`, `trackpad+3+longpress`.
/// 장치 토큰은 `InputDeviceKind.rawValue` 또는 `any`(모든 장치), 방향은 `SwipeDirection.rawValue`,
/// 버튼은 `left`·`right`·`buttonN`이며 클릭에서 생략하면 왼쪽이다. 진단용 종류(move·hold)는 트리거가 될 수 없다
public struct GestureSpec: Hashable, Sendable {
    /// nil이면 모든 장치
    public let device: InputDeviceKind?
    /// 정규화된 제스처: 클릭은 버튼이 항상 있고, 스와이프가 아니면 방향이 없다. 그래서 이벤트의 제스처와 그대로 비교할 수 있다
    public let gesture: InputGesture

    /// 트리거가 될 수 있는 제스처만 받는다. 진단용 종류, 손가락 0 이하, 방향 없는 스와이프, 종류에 안 맞는 방향·버튼은 nil
    public init?(device: InputDeviceKind?, gesture: InputGesture) {
        guard gesture.kind.isAssignable, gesture.fingers >= 1 else { return nil }
        var normalized = InputGesture(kind: gesture.kind, fingers: gesture.fingers)
        switch gesture.kind {
        case .swipe:
            guard let direction = gesture.direction, gesture.button == nil else { return nil }
            normalized.direction = direction
        case .click:
            guard gesture.direction == nil else { return nil }
            normalized.button = gesture.button ?? .left
        case .tap, .longPress:
            guard gesture.direction == nil, gesture.button == nil else { return nil }
        case .move, .hold:
            return nil
        }
        self.device = device
        self.gesture = normalized
    }

    /// 저장 문자열에서 복원한다. 형식이 어긋나면 nil
    public init?(string: String) {
        let tokens = string.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard tokens.count == 3 || tokens.count == 4 else { return nil }
        let device: InputDeviceKind?
        if tokens[0] == "any" {
            device = nil
        } else if let kind = InputDeviceKind(rawValue: tokens[0]) {
            device = kind
        } else {
            return nil
        }
        guard let fingers = Int(tokens[1]), let kind = GestureKind(rawValue: tokens[2]) else { return nil }
        var gesture = InputGesture(kind: kind, fingers: fingers)
        if tokens.count == 4 {
            switch kind {
            case .swipe:
                guard let direction = SwipeDirection(rawValue: tokens[3]) else { return nil }
                gesture.direction = direction
            case .click:
                guard let button = Self.button(fromToken: tokens[3]) else { return nil }
                gesture.button = button
            default:
                return nil
            }
        }
        self.init(device: device, gesture: gesture)
    }

    /// 저장 문자열. 클릭의 왼쪽 버튼은 생략한다
    public var stringValue: String {
        var tokens = [device?.rawValue ?? "any", String(gesture.fingers), gesture.kind.rawValue]
        if let direction = gesture.direction { tokens.append(direction.rawValue) }
        if let button = gesture.button, button != .left { tokens.append(Self.token(for: button)) }
        return tokens.joined(separator: "+")
    }

    /// 화면 표시용. 예: "매직마우스 3손가락 스와이프 왼쪽 ←", "모든 장치 2손가락 탭"
    public var displayName: String {
        (device?.displayName ?? "모든 장치") + " " + gesture.displayName(for: device ?? .unknown)
    }

    /// 이 이벤트가 조건에 맞는지. 장치는 nil이거나 종류가 같아야 하고, 제스처는 정확히 같아야 한다
    public func matches(_ event: GestureEvent) -> Bool {
        (device == nil || device == event.device.kind) && gesture == event.gesture
    }

    // "left"·"right"·"buttonN"
    private static func button(fromToken token: String) -> MouseButton? {
        switch token {
        case "left": .left
        case "right": .right
        default: token.hasPrefix("button") ? Int(token.dropFirst(6)).map { .other($0) } : nil
        }
    }

    // 버튼의 저장 토큰
    private static func token(for button: MouseButton) -> String {
        switch button {
        case .left: "left"
        case .right: "right"
        case .other(let n): "button\(n)"
        }
    }
}
