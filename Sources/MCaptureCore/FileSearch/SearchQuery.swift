import Foundation

/// 파일 찾기 검색어를 항으로 나눈 결과
///
/// 문법 (공백은 AND, 따옴표로 공백 포함):
/// - 일반 항: 파일 이름과 맞춘다 (퍼지·초성)
/// - `/`가 들어간 항: 전체 경로에 들어 있는지 본다. `~/`로 시작하면 홈 경로로 바꾼다
/// - `ext:pdf;png` (쉼표도 허용, 앞의 점 무시): 확장자 중 하나
/// - `folder:` / `file:` (뒤에 일반 항을 붙일 수 있음): 종류만 남긴다
/// - `regex:패턴`: 이름에 정규식(대소문자 무시)
/// - 모르는 접두어(`foo:bar`)는 일반 항으로 본다
public struct SearchQuery: Sendable {
    public enum Kind: Sendable, Equatable {
        case any, file, folder
    }

    public struct NameTerm: Sendable, Equatable {
        public let text: String
        /// 한글 입력을 조합하는 중인 마지막 항
        public let composing: Bool
    }

    public private(set) var nameTerms: [NameTerm] = []
    /// NFC로 맞춘 경로 항 (~는 홈으로 확장)
    public private(set) var pathTerms: [String] = []
    /// 소문자, 점 없는 확장자 목록. 비어 있으면 거르지 않는다
    public private(set) var extensions: [String] = []
    public private(set) var kind: Kind = .any
    public private(set) var regexes: [RegexTerm] = []
    /// 정규식 오류 등 검색할 수 없는 이유
    public private(set) var error: String?

    /// 거를 조건이 하나도 없으면 true
    public var isEmpty: Bool {
        nameTerms.isEmpty && pathTerms.isEmpty && extensions.isEmpty && kind == .any && regexes.isEmpty
    }

    /// 검색어를 파싱한다. composing이면 마지막 항이 한글 조합 중이다
    public init(_ text: String, home: String, composing: Bool = false) {
        let tokens = Self.tokenize(text)
        let tailOpen = composing && text.last.map { !$0.isWhitespace && $0 != "\"" } == true
        for (index, token) in tokens.enumerated() where !token.text.isEmpty {
            let composingTerm = tailOpen && index == tokens.count - 1
            if !token.quoted, let colon = token.text.firstIndex(of: ":") {
                let prefix = token.text[..<colon].lowercased()
                let value = String(token.text[token.text.index(after: colon)...])
                switch prefix {
                case "ext":
                    extensions += value.split(whereSeparator: { $0 == ";" || $0 == "," })
                        .map { HangulText.nfc(String($0.drop(while: { $0 == "." }))).lowercased() }
                        .filter { !$0.isEmpty }
                    continue
                case "folder", "dir", "file":
                    kind = prefix == "file" ? .file : .folder
                    if !value.isEmpty { addTerm(value, composing: composingTerm, home: home) }
                    continue
                case "regex":
                    if !value.isEmpty { addRegex(value) }
                    continue
                default:
                    break
                }
            }
            addTerm(token.text, composing: composingTerm, home: home)
        }
    }

    // 일반 항 또는 경로 항을 추가한다
    private mutating func addTerm(_ text: String, composing: Bool, home: String) {
        let text = HangulText.nfc(text)
        if text.contains("/") {
            pathTerms.append(text.hasPrefix("~/") ? home + text.dropFirst() : text)
        } else {
            nameTerms.append(NameTerm(text: text, composing: composing))
        }
    }

    // 정규식 항을 추가한다. 잘못된 패턴이면 오류를 남긴다
    private mutating func addRegex(_ pattern: String) {
        if let term = RegexTerm(pattern: HangulText.nfc(pattern)) {
            regexes.append(term)
        } else {
            error = "정규식 오류: \(pattern)"
        }
    }

    struct Token: Equatable {
        var text: String
        /// 따옴표로 시작한 항은 접두어를 해석하지 않는다
        var quoted: Bool
    }

    /// 공백으로 나누되 따옴표 안의 공백은 유지한다. 따옴표 자체는 지운다
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var started = false
        var quoted = false
        var inQuote = false
        for character in text {
            if character == "\"" {
                if !started { quoted = true }
                started = true
                inQuote.toggle()
            } else if character.isWhitespace && !inQuote {
                if started { tokens.append(Token(text: current, quoted: quoted)) }
                current = ""
                started = false
                quoted = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { tokens.append(Token(text: current, quoted: quoted)) }
        return tokens
    }
}

/// 컴파일한 정규식 항
/// NSRegularExpression은 불변이고 여러 스레드에서 써도 안전하다(Apple 문서)고 되어 있어 병렬 검색에 넘긴다.
/// 다만 한 객체를 여러 스레드가 함께 쓰면 내부 잠금 경합으로 10배 넘게 느려져(110만 개에서 500ms → 54ms) 청크마다 `copy()`를 쓴다
public struct RegexTerm: @unchecked Sendable {
    public let pattern: String
    let expression: NSRegularExpression

    /// 대소문자를 무시하는 정규식으로 컴파일한다. 잘못된 패턴이면 nil
    public init?(pattern: String) {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        self.pattern = pattern
        self.expression = expression
    }

    /// 같은 패턴으로 새로 컴파일한 사본. 병렬 청크마다 따로 쓰면 내부 잠금 경합을 피한다
    func copy() -> RegexTerm {
        RegexTerm(pattern: pattern) ?? self
    }

    /// 이름에 패턴이 들어 있는지
    public func matches(_ name: String) -> Bool {
        expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// UTF-8 이름 바이트에 패턴이 들어 있는지. Swift 문자열을 거치지 않고 복사 없는 NSString으로 바로 맞춘다
    public func matches(utf8 name: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = name.baseAddress,
              let text = NSString(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), length: name.count,
                                  encoding: String.Encoding.utf8.rawValue, freeWhenDone: false)
        else { return false }
        return expression.rangeOfFirstMatch(in: text as String, range: NSRange(location: 0, length: text.length)).location != NSNotFound
    }
}
