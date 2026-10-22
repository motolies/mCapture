import Foundation

/// 트리거 조건 하나와 실행할 동작. 설정에는 한 줄 문자열로 저장한다.
///
/// 형식은 `[#]조건=동작`이다. `#`으로 시작하면 꺼진 바인딩이다. 조건은 `GestureSpec.stringValue`,
/// 동작은 앱 동작 이름(`captureArea`처럼 영문자로 시작하는 영문·숫자, 코어는 뜻을 모른다) 또는
/// `keys:키 조합`(`keys:shift+cmd+left`, 앞 앱에 키 보내기)이다.
/// 예: `mouse+3+swipe+left=captureArea`, `#any+2+tap=keys:cmd+w`
public struct GestureBinding: Hashable, Sendable, Identifiable {
    /// 실행할 동작
    public enum Action: Hashable, Sendable {
        /// 앱 동작 이름 (AppAction.rawValue). 코어는 이름만 보관한다
        case app(String)
        /// 앞 앱에 키 조합 보내기
        case sendKeys(KeyChord)

        /// 저장 문자열에서 복원한다. 이름이 영문·숫자가 아니거나 키 조합이 잘못되면 nil
        public init?(string: String) {
            let text = string.trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix(Self.keysPrefix) {
                guard let chord = KeyChord(string: String(text.dropFirst(Self.keysPrefix.count))) else { return nil }
                self = .sendKeys(chord)
            } else {
                guard let first = text.first, first.isLetter, text.lowercased() != "keys",
                      text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
                else { return nil }
                self = .app(text)
            }
        }

        /// 저장 문자열
        public var stringValue: String {
            switch self {
            case .app(let name): name
            case .sendKeys(let chord): Self.keysPrefix + chord.stringValue
            }
        }

        private static let keysPrefix = "keys:"
    }

    public var spec: GestureSpec
    public var action: Action
    public var isEnabled: Bool

    /// 같은 조건은 목록에 하나뿐이라 조건이 곧 식별자다
    public var id: GestureSpec { spec }

    public init(spec: GestureSpec, action: Action, isEnabled: Bool = true) {
        self.spec = spec
        self.action = action
        self.isEnabled = isEnabled
    }

    /// 한 줄 문자열에서 복원한다. 조건이나 동작이 잘못되면 nil
    public init?(string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        var isEnabled = true
        if text.hasPrefix("#") {
            isEnabled = false
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let spec = GestureSpec(string: String(parts[0])),
              let action = Action(string: String(parts[1]))
        else { return nil }
        self.init(spec: spec, action: action, isEnabled: isEnabled)
    }

    /// 저장용 표준 문자열. 예: `mouse+4+click=captureArea`, `#any+2+tap=keys:cmd+w`
    public var stringValue: String {
        (isEnabled ? "" : "#") + spec.stringValue + "=" + action.stringValue
    }
}

/// 바인딩 목록의 저장과 매칭 규칙
public enum GestureBindingList {
    /// 줄마다 바인딩을 읽는다. 형식이 어긋난 줄과 앞 줄과 같은 조건은 버리고 rejected로 돌려준다 (로그용)
    public static func decode(_ lines: [String]) -> (bindings: [GestureBinding], rejected: [String]) {
        var bindings: [GestureBinding] = []
        var rejected: [String] = []
        var seen: Set<GestureSpec> = []
        for line in lines {
            guard let binding = GestureBinding(string: line), !seen.contains(binding.spec) else {
                rejected.append(line)
                continue
            }
            seen.insert(binding.spec)
            bindings.append(binding)
        }
        return (bindings, rejected)
    }

    public static func encode(_ bindings: [GestureBinding]) -> [String] {
        bindings.map(\.stringValue)
    }

    /// 이벤트에 맞는 켜진 바인딩. 장치를 지정한 조건을 먼저, 없으면 모든 장치 조건을 고른다.
    /// 조건은 목록에 하나씩이라 단계마다 많아야 하나다
    public static func match(_ event: GestureEvent, in bindings: [GestureBinding]) -> GestureBinding? {
        let candidates = bindings.filter { $0.isEnabled && $0.spec.matches(event) }
        return candidates.first { $0.spec.device != nil } ?? candidates.first
    }

    /// 같은 제스처를 다른 장치 범위(모든 장치 ↔ 특정 장치)로 가진 바인딩. 편집기가 경고를 띄우는 데 쓴다
    public static func overlapping(_ spec: GestureSpec, in bindings: [GestureBinding]) -> [GestureBinding] {
        bindings.filter { other in
            other.spec != spec && other.spec.gesture == spec.gesture && (other.spec.device == nil || spec.device == nil)
        }
    }
}
