import Foundation

/// 수식키 묶음. 전역 단축키(HotKeySpec)와 보낼 키 조합(KeyChord)이 함께 쓴다
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// 메뉴 표기 순서의 기호 (예: ⌃⇧). 녹화 중 누른 수식키 미리보기에도 쓴다
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    /// 저장 문자열 토큰 (순서 고정: ctrl, opt, shift, cmd)
    public var tokens: [String] {
        var parts: [String] = []
        if contains(.control) { parts.append("ctrl") }
        if contains(.option) { parts.append("opt") }
        if contains(.shift) { parts.append("shift") }
        if contains(.command) { parts.append("cmd") }
        return parts
    }

    /// 소문자 토큰 하나를 수식키로 읽는다. 수식키 이름이 아니면 nil
    public static func modifier(forToken token: String) -> KeyModifiers? {
        switch token {
        case "cmd", "command": .command
        case "shift": .shift
        case "ctrl", "control": .control
        case "opt", "option", "alt": .option
        default: nil
        }
    }
}

/// 다른 앱에 보낼 키 조합. "cmd+shift+left", "space", "f5"처럼 문자열 하나로 저장한다.
/// 수식키는 없어도 되고 키는 꼭 하나다. 키 이름에 + = # : 공백이 없어 제스처 바인딩 한 줄에 그대로 들어간다
public struct KeyChord: Hashable, Sendable {
    /// 키 하나. 이름은 저장 토큰, 기호는 표시용
    public struct Key: Hashable, Sendable {
        /// 키 묶음. 보낼 때 실제 키보드가 붙이는 플래그(Fn·숫자 패드)를 정한다
        public enum Group: Sendable {
            case character, control, navigation, arrow, function
        }

        public let name: String
        /// ANSI 가상 키 코드 (CGKeyCode·NSEvent.keyCode와 같은 타입)
        public let keyCode: UInt16
        public let symbol: String
        public let group: Group
    }

    public let key: Key
    public let modifiers: KeyModifiers

    public init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 문자열을 파싱한다. 대소문자·공백·별칭(esc, enter, backspace, alt)을 받아들이고, 키가 없거나 둘이면 nil
    public init?(string: String) {
        var modifiers: KeyModifiers = []
        var key: Key?
        for token in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let modifier = KeyModifiers.modifier(forToken: token) {
                modifiers.insert(modifier)
            } else {
                guard key == nil, let found = Self.key(named: token) else { return nil }
                key = found
            }
        }
        guard let key else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// 키 코드와 수식키로 만든다 (설정의 키 녹화). 표에 없는 키면 nil
    public init?(keyCode: UInt16, modifiers: KeyModifiers) {
        guard let key = Self.keys.first(where: { $0.keyCode == keyCode }) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// 저장용 표준 문자열 (예: ctrl+opt+shift+cmd+k)
    public var stringValue: String {
        (modifiers.tokens + [key.name]).joined(separator: "+")
    }

    /// 표시 문자열 (예: ⌘⇧←, Space, F5)
    public var displayString: String {
        modifiers.symbols + key.symbol
    }

    /// 이름이나 별칭으로 키를 찾는다
    public static func key(named name: String) -> Key? {
        keysByName[aliases[name] ?? name]
    }

    /// 지원하는 키 전부. 영문자·숫자는 HotKeySpec과 같은 ANSI 키 코드
    public static let keys: [Key] = {
        let characters: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17),
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29),
            ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        let punctuation: [(String, UInt16, String)] = [
            ("minus", 27, "-"), ("equal", 24, "="), ("lbracket", 33, "["), ("rbracket", 30, "]"), ("backslash", 42, "\\"),
            ("semicolon", 41, ";"), ("quote", 39, "'"), ("comma", 43, ","), ("period", 47, "."), ("slash", 44, "/"), ("grave", 50, "`"),
        ]
        let control: [(String, UInt16, String)] = [
            ("return", 36, "↩"), ("tab", 48, "⇥"), ("space", 49, "Space"), ("delete", 51, "⌫"), ("escape", 53, "⎋"),
        ]
        let navigation: [(String, UInt16, String)] = [
            ("forwarddelete", 117, "⌦"), ("home", 115, "↖"), ("end", 119, "↘"), ("pageup", 116, "⇞"), ("pagedown", 121, "⇟"),
        ]
        let arrows: [(String, UInt16, String)] = [("left", 123, "←"), ("right", 124, "→"), ("down", 125, "↓"), ("up", 126, "↑")]
        let functionCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

        var keys = characters.map { Key(name: $0.0, keyCode: $0.1, symbol: $0.0.uppercased(), group: .character) }
        keys += punctuation.map { Key(name: $0.0, keyCode: $0.1, symbol: $0.2, group: .character) }
        keys += control.map { Key(name: $0.0, keyCode: $0.1, symbol: $0.2, group: .control) }
        keys += navigation.map { Key(name: $0.0, keyCode: $0.1, symbol: $0.2, group: .navigation) }
        keys += arrows.map { Key(name: $0.0, keyCode: $0.1, symbol: $0.2, group: .arrow) }
        keys += functionCodes.enumerated().map { Key(name: "f\($0.offset + 1)", keyCode: $0.element, symbol: "F\($0.offset + 1)", group: .function) }
        return keys
    }()

    private static let keysByName = Dictionary(uniqueKeysWithValues: keys.map { ($0.name, $0) })

    /// 읽을 때만 받아들이는 다른 이름. 저장은 항상 표준 이름으로 한다
    private static let aliases: [String: String] = [
        "esc": "escape", "enter": "return", "backspace": "delete", "del": "forwarddelete", "pgup": "pageup", "pgdn": "pagedown",
    ]
}
