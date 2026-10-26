import Foundation

/// 검색어 안에서 칩으로 따로 보일 필터 항 (위치·경로·확장자·종류·정규식)
///
/// 검색어 문자열이 원본이고 칩은 그 일부를 나눠 보여 주기만 한다.
/// 칩의 `raw`를 남은 검색 글자 앞에 이어 붙이면(`combine`) 같은 `SearchQuery`가 된다
public struct FilterToken: Sendable, Equatable {
    public enum Category: Sendable, Equatable, CaseIterable {
        /// `~/`나 `/`로 시작하는 경로 항 (그 폴더 아래)
        case location
        /// 그 밖의 `/`가 든 경로 항 (전체 경로에 포함)
        case pathContains
        case extensions
        case kind
        case regex

        /// 칩 앞에 보일 이름
        public var title: String {
            switch self {
            case .location: "위치"
            case .pathContains: "경로"
            case .extensions: "확장자"
            case .kind: "종류"
            case .regex: "정규식"
            }
        }
    }

    public let category: Category
    /// 칩에 보일 값
    public let value: String
    /// 검색어에 들어가는 원문 (따옴표 포함)
    public let raw: String
    /// 정규식이 잘못되어 검색할 수 없는 항
    public let isInvalid: Bool

    public init(category: Category, value: String, raw: String, isInvalid: Bool = false) {
        self.category = category
        self.value = value
        self.raw = raw
        self.isInvalid = isInvalid
    }

    /// 칩으로 떼어 낸 결과
    public struct Extraction: Sendable, Equatable {
        public let tokens: [FilterToken]
        /// 칩으로 옮기고 남은 검색 글자 (원래 공백으로 끝났으면 공백 하나로 끝난다)
        public let rest: String
    }

    /// 다 친 항 중 필터 항을 칩으로 떼어 낸다. 떼어 낼 항이 없으면 nil
    /// includeLast가 false면 공백으로 끝나지 않은 마지막 항은 아직 치는 중으로 보고 남긴다
    public static func extract(from text: String, includeLast: Bool) -> Extraction? {
        let (tokens, endsWithSeparator) = SearchQuery.tokenizeTracking(text)
        let completeCount = includeLast || endsWithSeparator ? tokens.count : tokens.count - 1
        var chips: [FilterToken] = []
        var rest: [String] = []
        for (index, token) in tokens.enumerated() {
            guard index < completeCount, let parsed = classify(token) else {
                rest.append(token.raw)
                continue
            }
            chips.append(parsed.chip)
            // `folder:a/b`처럼 남은 항도 경로 항이면 함께 칩으로 옮긴다
            if let leftover = parsed.leftover {
                if let token = SearchQuery.tokenize(leftover).first, let nested = classify(token) {
                    chips.append(nested.chip)
                } else {
                    rest.append(leftover)
                }
            }
        }
        guard !chips.isEmpty else { return nil }
        var restText = rest.joined(separator: " ")
        if endsWithSeparator, !restText.isEmpty { restText += " " }
        return Extraction(tokens: chips, rest: restText)
    }

    /// 칩 원문들과 남은 검색 글자를 이어 검색어 하나로 만든다
    public static func combine(_ tokens: [FilterToken], rest: String) -> String {
        (tokens.map(\.raw) + [rest]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - 만들기 (필터 메뉴)

    /// 종류 칩. `.any`면 nil
    public static func kind(_ kind: SearchQuery.Kind) -> FilterToken? {
        switch kind {
        case .any: nil
        case .file: FilterToken(category: .kind, value: "파일만", raw: "file:")
        case .folder: FilterToken(category: .kind, value: "폴더만", raw: "folder:")
        }
    }

    /// 확장자 칩. 목록이 비면 nil
    public static func extensions(_ list: [String]) -> FilterToken? {
        let normalized = SearchQuery.parseExtensions(list.joined(separator: ";"))
        guard !normalized.isEmpty else { return nil }
        return FilterToken(category: .extensions, value: normalized.joined(separator: "·"),
                           raw: "ext:" + normalized.joined(separator: ";"))
    }

    /// 위치 칩: 그 폴더 아래만 찾는다. 홈 아래 경로는 ~로 줄이고 끝에 /를 붙인다
    public static func location(_ path: String, home: String) -> FilterToken {
        var display = HangulText.nfc(path)
        if display == home {
            display = "~"
        } else if display.hasPrefix(home + "/") {
            display = "~" + display.dropFirst(home.count)
        }
        if !display.hasSuffix("/") { display += "/" }
        return FilterToken(category: .location, value: display, raw: quotedIfNeeded(display))
    }

    /// 정규식 칩 (이름에 맞춘다)
    public static func regex(_ pattern: String) -> FilterToken {
        FilterToken(category: .regex, value: pattern, raw: "regex:" + quotedIfNeeded(pattern),
                    isInvalid: RegexTerm(pattern: HangulText.nfc(pattern)) == nil)
    }

    // MARK: - 분류

    // 항 하나가 필터 항이면 칩과(종류 접두어 뒤에 붙은) 남은 항을 돌려준다. SearchQuery.init의 해석과 같은 규칙이다
    static func classify(_ token: SearchQuery.Token) -> (chip: FilterToken, leftover: String?)? {
        if !token.quoted, let colon = token.text.firstIndex(of: ":") {
            let prefix = token.text[..<colon].lowercased()
            let value = String(token.text[token.text.index(after: colon)...])
            switch prefix {
            case "ext":
                let list = SearchQuery.parseExtensions(value)
                guard !list.isEmpty else { return nil }
                return (FilterToken(category: .extensions, value: list.joined(separator: "·"), raw: token.raw), nil)
            case "folder", "dir", "file":
                guard let chip = kind(prefix == "file" ? .file : .folder) else { return nil }
                return (chip, value.isEmpty ? nil : leftover(afterPrefixOf: token.raw))
            case "regex":
                guard !value.isEmpty else { return nil }
                let invalid = RegexTerm(pattern: HangulText.nfc(value)) == nil
                return (FilterToken(category: .regex, value: value, raw: token.raw, isInvalid: invalid), nil)
            default:
                break
            }
        }
        guard token.text.contains("/") else { return nil }
        let category: Category = token.text.hasPrefix("~/") || token.text.hasPrefix("/") ? .location : .pathContains
        return (FilterToken(category: category, value: token.text, raw: token.raw), nil)
    }

    // `folder:보고서`의 `보고서`처럼 접두어 뒤 원문을 떼어 낸다.
    // SearchQuery는 그 값을 접두어 없는 일반 항으로 보므로, 다시 접두어로 읽히지 않게 :가 있으면 따옴표로 감싼다
    private static func leftover(afterPrefixOf raw: String) -> String? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let value = String(raw[raw.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        if !value.hasPrefix("\""), value.contains(":") { return "\"" + value + "\"" }
        return value
    }

    // 공백이 있으면 따옴표로 감싼다
    private static func quotedIfNeeded(_ text: String) -> String {
        text.contains(where: \.isWhitespace) ? "\"" + text + "\"" : text
    }
}
