import Foundation

/// 검색 항 하나를 파일 이름과 맞춰 등급·점수를 매긴다
/// 비교 단위는 유니코드 스칼라(NFC)다. ASCII는 대소문자를 무시하고, 초성 자모(ㄱ~ㅎ)는 그 초성을 가진 음절과도 맞는다
public struct NameMatcher: Sendable {
    /// 일치 등급. 높을수록 위에 온다
    public enum Grade: Int, Comparable, Sendable {
        case fuzzy = 0
        case substring
        case boundary
        case prefix
        case exact

        public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }

        /// 등급 기본 점수. 퍼지는 0에 퍼지 점수(최대 499)를 더한다
        public var baseScore: Int {
            switch self {
            case .exact: 3000
            case .prefix: 2000
            case .boundary: 1500
            case .substring: 1000
            case .fuzzy: 0
            }
        }
    }

    public struct Match: Equatable, Sendable {
        public let grade: Grade
        /// 등급 기본 점수 + 퍼지 점수
        public let score: Int
    }

    /// 검색어 글자 하나의 비교 방식
    struct Unit: Sendable {
        enum Kind: UInt8, Sendable {
            /// 글자 그대로 (ASCII는 소문자로 접어 둠)
            case literal
            /// 초성 자모: 같은 자모 또는 그 초성을 가진 음절과 맞음
            case choseong
            /// 조합 중인 받침 없는 음절: 초성+중성이 같은 음절과 맞음 ("하"가 "한"과 맞음)
            case syllablePrefix
        }

        let kind: Kind
        /// literal·choseong은 스칼라 값, syllablePrefix는 초성+중성 번호
        let value: UInt32
        /// choseong의 초성 번호
        let choseong: UInt32
    }

    let units: [Unit]
    /// 검색어가 ASCII뿐이면 UTF-8 바이트로 사전 필터를 할 수 있다 (소문자로 접은 바이트)
    let asciiBytes: [UInt8]?

    /// 퍼지 점수 상수 (fzf v1 방식을 단순화)
    enum Score {
        static let match = 16
        static let gapStart = -3
        static let gapExtension = -1
        static let boundary = 8
        static let camelOrNumber = 7
        static let consecutive = 4
        static let firstCharMultiplier = 2
        static let fuzzyMax = 499
    }

    /// 검색 항으로 매처를 만든다. composing이면 마지막 받침 없는 음절을 초성+중성으로만 비교한다
    public init(term: String, composing: Bool = false) {
        let scalars = HangulText.nfc(term).unicodeScalars.map(\.value)
        var units: [Unit] = scalars.map { scalar in
            if scalar &- 0x41 < 26 {
                return Unit(kind: .literal, value: scalar + 32, choseong: 0)
            }
            if let index = HangulText.choseongIndex(jamo: scalar) {
                return Unit(kind: .choseong, value: scalar, choseong: UInt32(index))
            }
            return Unit(kind: .literal, value: scalar, choseong: 0)
        }
        if composing, let last = scalars.last, HangulText.hasNoJongseong(last),
           let prefix = HangulText.choseongJungseong(last) {
            units[units.count - 1] = Unit(kind: .syllablePrefix, value: prefix, choseong: 0)
        }
        self.units = units
        self.asciiBytes = units.allSatisfy({ $0.kind == .literal && $0.value < 0x80 }) ? units.map { UInt8($0.value) } : nil
    }

    public var isEmpty: Bool { units.isEmpty }

    // MARK: - 사전 필터

    /// ASCII 검색어가 이름 바이트에 부분 수열로 들어 있을 수 있는지. 아니면 match도 nil이다
    /// ASCII가 아닌 검색어는 바이트로 판단할 수 없어 늘 true
    /// UTF-8에서 ASCII 바이트는 여러 바이트 글자 안에 나타나지 않으므로 바이트 비교가 안전하다
    @inline(__always)
    public func mayMatch(utf8 name: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let bytes = asciiBytes, !bytes.isEmpty else { return true }
        var j = 0
        let m = bytes.count
        for byte in name {
            let folded = byte &- 0x41 < 26 ? byte + 32 : byte
            if folded == bytes[j] {
                j += 1
                if j == m { return true }
            }
        }
        return false
    }

    // MARK: - 매칭

    /// 이름(NFC 스칼라)과 맞춰 등급과 점수를 돌려준다. 맞지 않으면 nil
    public func match(_ name: UnsafeBufferPointer<UInt32>) -> Match? {
        let m = units.count
        let n = name.count
        guard m > 0, m <= n, let end = forwardEnd(name) else { return nil }

        if isExact(name) { return Match(grade: .exact, score: Grade.exact.baseScore) }
        if matches(name, at: 0) { return Match(grade: .prefix, score: Grade.prefix.baseScore) }
        if let start = substringStart(name) {
            let grade: Grade = Self.bonus(name, at: start) > 0 ? .boundary : .substring
            return Match(grade: grade, score: grade.baseScore)
        }
        let start = backwardStart(name, end: end)
        return Match(grade: .fuzzy, score: fuzzyScore(name, from: start, to: end).score)
    }

    /// 문자열 이름과 맞춰 본다 (테스트·결과 표시용)
    public func match(_ name: String) -> Match? {
        let scalars = HangulText.nfc(name).unicodeScalars.map(\.value)
        return scalars.withUnsafeBufferPointer { match($0) }
    }

    /// 하이라이트할 글자 위치(스칼라 번호). 맞지 않으면 빈 배열
    public func positions(_ name: [UInt32]) -> [Int] {
        name.withUnsafeBufferPointer { name in
            let m = units.count
            guard m > 0, m <= name.count, let end = forwardEnd(name) else { return [] }
            if isExact(name) || matches(name, at: 0) { return Array(0..<m) }
            if let start = substringStart(name) { return Array(start..<(start + m)) }
            return fuzzyScore(name, from: backwardStart(name, end: end), to: end).positions
        }
    }

    /// 문자열 이름의 하이라이트 위치
    public func positions(_ name: String) -> [Int] {
        positions(HangulText.nfc(name).unicodeScalars.map(\.value))
    }

    // MARK: - 내부

    // 검색어 글자 하나가 이름 글자와 같은지
    @inline(__always)
    private func equal(_ unit: Unit, _ scalar: UInt32) -> Bool {
        switch unit.kind {
        case .literal:
            return unit.value == scalar || (scalar &- 0x41 < 26 && unit.value == scalar + 32)
        case .choseong:
            return unit.value == scalar
                || (HangulText.isSyllable(scalar) && (scalar - HangulText.syllableFirst) / HangulText.syllablesPerChoseong == unit.choseong)
        case .syllablePrefix:
            return HangulText.isSyllable(scalar) && (scalar - HangulText.syllableFirst) / HangulText.jongseongCount == unit.value
        }
    }

    // 이름의 start 위치부터 검색어 전체가 이어서 맞는지
    private func matches(_ name: UnsafeBufferPointer<UInt32>, at start: Int) -> Bool {
        guard start + units.count <= name.count else { return false }
        for k in 0..<units.count where !equal(units[k], name[start + k]) {
            return false
        }
        return true
    }

    // 이름 전체, 또는 확장자를 뺀 이름이 검색어와 같은지 ("readme"는 "README.md"와 정확 일치)
    private func isExact(_ name: UnsafeBufferPointer<UInt32>) -> Bool {
        let m = units.count
        if name.count == m { return matches(name, at: 0) }
        guard let dot = name.lastIndex(of: 0x2E), dot == m else { return false }
        return matches(name, at: 0)
    }

    // 검색어가 처음 나오는 위치. 단어 경계에서 시작하는 위치가 있으면 그쪽을 고른다
    private func substringStart(_ name: UnsafeBufferPointer<UInt32>) -> Int? {
        let m = units.count
        var first: Int?
        var start = 0
        while start + m <= name.count {
            if matches(name, at: start) {
                if Self.bonus(name, at: start) > 0 { return start }
                if first == nil { first = start }
            }
            start += 1
        }
        return first
    }

    // 앞에서부터 검색어를 부분 수열로 찾았을 때 마지막 글자의 위치
    private func forwardEnd(_ name: UnsafeBufferPointer<UInt32>) -> Int? {
        var j = 0
        for i in 0..<name.count where equal(units[j], name[i]) {
            j += 1
            if j == units.count { return i }
        }
        return nil
    }

    // end에서 거꾸로 검색어를 찾아 가장 짧은 구간의 시작 위치를 구한다
    private func backwardStart(_ name: UnsafeBufferPointer<UInt32>, end: Int) -> Int {
        var j = units.count - 1
        var i = end
        while i >= 0 {
            if equal(units[j], name[i]) {
                if j == 0 { return i }
                j -= 1
            }
            i -= 1
        }
        return 0
    }

    // 구간 안에서 앞에서부터 맞춰 가며 퍼지 점수와 위치를 계산한다 (연속·경계 보너스, 간격 감점)
    private func fuzzyScore(_ name: UnsafeBufferPointer<UInt32>, from start: Int, to end: Int) -> (score: Int, positions: [Int]) {
        var score = 0
        var positions: [Int] = []
        positions.reserveCapacity(units.count)
        var j = 0
        var inGap = false
        var previousMatched = false
        var i = start
        while i <= end, j < units.count {
            if equal(units[j], name[i]) {
                var bonus = Self.bonus(name, at: i)
                if previousMatched { bonus = max(bonus, Score.consecutive) }
                if j == 0 { bonus *= Score.firstCharMultiplier }
                score += Score.match + bonus
                positions.append(i)
                j += 1
                inGap = false
                previousMatched = true
            } else {
                score += inGap ? Score.gapExtension : Score.gapStart
                inGap = true
                previousMatched = false
            }
            i += 1
        }
        return (min(max(score, 0), Score.fuzzyMax), positions)
    }

    /// 글자 종류 (경계 보너스 판정용)
    enum CharClass {
        case lower, upper, digit, hangul, delimiter, other
    }

    // 스칼라의 글자 종류
    @inline(__always)
    static func charClass(_ scalar: UInt32) -> CharClass {
        switch scalar {
        case 0x61...0x7A: return .lower
        case 0x41...0x5A: return .upper
        case 0x30...0x39: return .digit
        case 0xAC00...0xD7A3, 0x3131...0x318E, 0x1100...0x11FF: return .hangul
        case 0x20, 0x21, 0x22, 0x23, 0x26, 0x27, 0x28, 0x29, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
             0x40, 0x5B, 0x5D, 0x5F, 0x7B, 0x7D, 0x7E:
            return .delimiter
        default: return .other
        }
    }

    // i 위치 글자가 단어 경계에서 시작하면 보너스. 이름 시작·구분자 뒤·camelCase·숫자 전환·한글과 다른 글자 사이
    @inline(__always)
    static func bonus(_ name: UnsafeBufferPointer<UInt32>, at i: Int) -> Int {
        let current = charClass(name[i])
        if current == .delimiter { return 0 }
        guard i > 0 else { return Score.boundary }
        let previous = charClass(name[i - 1])
        switch (previous, current) {
        case (.delimiter, _):
            return Score.boundary
        case (.lower, .upper):
            return Score.camelOrNumber
        case (.lower, .digit), (.upper, .digit), (.other, .digit), (.hangul, .digit),
             (.digit, .lower), (.digit, .upper), (.digit, .other), (.digit, .hangul):
            return Score.camelOrNumber
        case (.hangul, .lower), (.hangul, .upper), (.hangul, .other),
             (.lower, .hangul), (.upper, .hangul), (.other, .hangul):
            return Score.boundary
        default:
            return 0
        }
    }
}
