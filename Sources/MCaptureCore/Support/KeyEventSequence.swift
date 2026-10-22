import CoreGraphics

/// 보낼 키 이벤트 한 단계. KeySender가 CGEvent 하나로 바꿔 post한다
public struct KeyEventStep: Equatable, Sendable {
    public let keyCode: UInt16
    public let isDown: Bool
    public let flags: CGEventFlags

    public init(keyCode: UInt16, isDown: Bool, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.isDown = isDown
        self.flags = flags
    }
}

extension KeyModifiers {
    /// 수식키 자체의 가상 키 코드 (왼쪽 키). 누르는 순서 ⌃⌥⇧⌘는 symbols·tokens와 같다.
    /// Fn(63)은 KeyModifiers가 아니라 키 묶음 플래그로만 쓴다. KeyChord.keys 표와 따로 두어 그 표의 중복 검사와 섞이지 않는다
    static let keyCodes: [(modifier: KeyModifiers, keyCode: UInt16)] = [(.control, 59), (.option, 58), (.shift, 56), (.command, 55)]

    /// CGEvent에 붙일 수식키 플래그
    public var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}

extension KeyChord.Key.Group {
    /// 실제 키보드가 이 묶음의 키 이벤트에 붙이는 플래그. 탐색·F키는 Fn, 화살표는 Fn과 숫자 패드, 나머지는 없음
    public var eventFlags: CGEventFlags {
        switch self {
        case .navigation, .function: [.maskSecondaryFn]
        case .arrow: [.maskSecondaryFn, .maskNumericPad]
        case .character, .control: []
        }
    }
}

extension KeyChord {
    /// 실제 키보드가 내는 순서의 이벤트 열.
    /// 수식키 down(⌃→⌥→⇧→⌘, 플래그는 자기 자신까지 누적) → 키 down/up(수식키 플래그 + 묶음 플래그) → 수식키 up(역순, 뗀 뒤 남은 플래그).
    /// 플래그만 붙인 키 이벤트는 Finder가 무시하므로 수식키 이벤트를 앞뒤에 둔다. Fn·숫자 패드 플래그는 실제 키보드처럼 키 이벤트에만 붙인다
    public var eventSequence: [KeyEventStep] {
        let held = KeyModifiers.keyCodes.filter { modifiers.contains($0.modifier) }
        var steps: [KeyEventStep] = []
        var down: KeyModifiers = []
        for (modifier, code) in held {
            down.insert(modifier)
            steps.append(KeyEventStep(keyCode: code, isDown: true, flags: down.eventFlags))
        }
        let keyFlags = modifiers.eventFlags.union(key.group.eventFlags)
        steps.append(KeyEventStep(keyCode: key.keyCode, isDown: true, flags: keyFlags))
        steps.append(KeyEventStep(keyCode: key.keyCode, isDown: false, flags: keyFlags))
        for (modifier, code) in held.reversed() {
            down.remove(modifier)
            steps.append(KeyEventStep(keyCode: code, isDown: false, flags: down.eventFlags))
        }
        return steps
    }
}
