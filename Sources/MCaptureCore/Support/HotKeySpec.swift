import Foundation

/// "ctrl+shift+4" 같은 문자열로 표현하는 전역 단축키
public struct HotKeySpec: Equatable, Sendable {
    /// 수식키 묶음 (KeyChord와 같은 타입)
    public typealias Modifiers = KeyModifiers

    public let key: String
    public let keyCode: UInt32
    public let modifiers: Modifiers

    /// 문자열을 파싱한다. 키가 하나가 아니거나 ⌘·⌃·⌥ 중 하나도 없으면 nil
    public init?(string: String) {
        var modifiers: Modifiers = []
        var key: String?
        for token in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let modifier = KeyModifiers.modifier(forToken: token) {
                modifiers.insert(modifier)
            } else {
                guard key == nil, Self.keyCodes[token] != nil else { return nil }
                key = token
            }
        }
        guard let key, let keyCode = Self.keyCodes[key] else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// 키 코드와 수식키로 만든다 (설정의 단축키 녹화). 지원하지 않는 키이거나 ⌘·⌃·⌥가 하나도 없으면 nil
    public init?(keyCode: UInt32, modifiers: Modifiers) {
        guard let key = Self.keyCodes.first(where: { $0.value == keyCode })?.key,
              !modifiers.isDisjoint(with: [.command, .control, .option])
        else { return nil }
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 저장용 표준 문자열 (수식키 순서 고정)
    public var stringValue: String {
        (modifiers.tokens + [key]).joined(separator: "+")
    }

    /// 메뉴에 표시하는 기호 문자열 (예: ⌃⇧4)
    public var displayString: String {
        modifiers.symbols + key.uppercased()
    }

    /// 같은 키와 수식키의 보낼 키 조합. 제스처로 보낼 키가 mCapture 단축키와 겹치는지 비교하는 데 쓴다
    public var chord: KeyChord {
        // 단축키의 키는 모두 KeyChord 표에 있다 (테스트로 보장). 혹시 없더라도 같은 키 코드로 만들어 크래시하지 않는다
        let key = KeyChord.key(named: key) ?? KeyChord.Key(name: key, keyCode: UInt16(keyCode), symbol: key.uppercased(), group: .character)
        return KeyChord(key: key, modifiers: modifiers)
    }

    /// Carbon RegisterEventHotKey용 수식키 플래그 (cmdKey, shiftKey, optionKey, controlKey)
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 256 }
        if modifiers.contains(.shift) { flags |= 512 }
        if modifiers.contains(.option) { flags |= 2048 }
        if modifiers.contains(.control) { flags |= 4096 }
        return flags
    }

    /// ANSI 키보드 가상 키 코드
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
}
