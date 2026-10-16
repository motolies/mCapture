import Foundation

/// "ctrl+shift+4" 같은 문자열로 표현하는 전역 단축키
public struct HotKeySpec: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// 메뉴 표기 순서의 기호 (예: ⌃⇧). 녹화 중 누른 수식키 미리보기에도 쓴다
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    public let key: String
    public let keyCode: UInt32
    public let modifiers: Modifiers

    /// 문자열을 파싱한다. 키가 하나가 아니거나 ⌘·⌃·⌥ 중 하나도 없으면 nil
    public init?(string: String) {
        var modifiers: Modifiers = []
        var key: String?
        for token in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch token {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            default:
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
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }

    /// 메뉴에 표시하는 기호 문자열 (예: ⌃⇧4)
    public var displayString: String {
        modifiers.symbols + key.uppercased()
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
