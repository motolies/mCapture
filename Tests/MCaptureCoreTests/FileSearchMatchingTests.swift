import Foundation
import Testing
@testable import MCaptureCore

@Suite("HangulText")
struct HangulTextTests {
    @Test func NFD_한글을_NFC로_맞춘다() {
        let nfd = "한글".decomposedStringWithCanonicalMapping
        #expect(nfd.unicodeScalars.count == 6)
        #expect(HangulText.nfc(nfd).unicodeScalars.count == 2)
        #expect(HangulText.nfc(nfd) == "한글")
    }

    @Test func ASCII는_그대로_돌려준다() {
        #expect(HangulText.nfc("README.md") == "README.md")
    }

    @Test func 음절의_초성을_구한다() {
        #expect(HangulText.choseong(of: "한글.txt") == "ㅎㄱ.txt")
        #expect(HangulText.choseong(of: "까치") == "ㄲㅊ")
        #expect(HangulText.choseongIndex(syllable: 0x1F600) == nil)
    }

    @Test func 받침_전용_자모는_초성이_아니다() {
        #expect(HangulText.choseongIndex(jamo: "ㄱ".unicodeScalars.first!.value) == 0)
        #expect(HangulText.choseongIndex(jamo: "ㅎ".unicodeScalars.first!.value) == 18)
        #expect(HangulText.choseongIndex(jamo: "ㄳ".unicodeScalars.first!.value) == nil)
        #expect(HangulText.choseongIndex(jamo: "ㅏ".unicodeScalars.first!.value) == nil)
    }

    @Test func 받침_여부를_판별한다() {
        #expect(HangulText.hasNoJongseong("하".unicodeScalars.first!.value))
        #expect(!HangulText.hasNoJongseong("한".unicodeScalars.first!.value))
        #expect(!HangulText.hasNoJongseong("a".unicodeScalars.first!.value))
    }
}

@Suite("SearchQuery")
struct SearchQueryTests {
    let home = "/Users/tester"

    private func query(_ text: String, composing: Bool = false) -> SearchQuery {
        SearchQuery(text, home: home, composing: composing)
    }

    @Test func 공백은_AND로_나눈다() {
        #expect(query("foo  bar").nameTerms.map(\.text) == ["foo", "bar"])
    }

    @Test func 따옴표_안_공백은_한_항() {
        #expect(query("\"my file\" x").nameTerms.map(\.text) == ["my file", "x"])
    }

    @Test func ext는_세미콜론_쉼표_점을_허용한다() {
        let q = query("ext:pdf;.PNG,jpg report")
        #expect(q.extensions == ["pdf", "png", "jpg"])
        #expect(q.nameTerms.map(\.text) == ["report"])
    }

    @Test func folder만_쓰면_종류만_거른다() {
        let q = query("folder:")
        #expect(q.kind == .folder)
        #expect(q.nameTerms.isEmpty)
        #expect(!q.isEmpty)
    }

    @Test func file에_항을_붙일_수_있다() {
        let q = query("file:readme")
        #expect(q.kind == .file)
        #expect(q.nameTerms.map(\.text) == ["readme"])
    }

    @Test func regex_따옴표_패턴() {
        let q = query("regex:\"^IMG \\d+\"")
        #expect(q.regexes.map(\.pattern) == ["^IMG \\d+"])
        #expect(q.regexes[0].matches("img 123.png"))
        #expect(!q.regexes[0].matches("IMG_123.png"))
    }

    @Test func 잘못된_정규식은_오류() {
        let q = query("regex:([")
        #expect(q.error != nil)
        #expect(q.regexes.isEmpty)
    }

    @Test func 슬래시가_있으면_경로항() {
        let q = query("proj/src main")
        #expect(q.pathTerms == ["proj/src"])
        #expect(q.nameTerms.map(\.text) == ["main"])
    }

    @Test func 물결은_홈으로_확장한다() {
        #expect(query("~/Doc").pathTerms == ["/Users/tester/Doc"])
    }

    @Test func 모르는_접두어는_일반항() {
        #expect(query("foo:bar").nameTerms.map(\.text) == ["foo:bar"])
        #expect(query("\"ext:pdf\"").nameTerms.map(\.text) == ["ext:pdf"])
    }

    @Test func 빈_검색어는_항이_없다() {
        #expect(query("   ").isEmpty)
        #expect(query("").isEmpty)
    }

    @Test func 조합_중이면_마지막_항만_표시한다() {
        let q = query("abc 하", composing: true)
        #expect(q.nameTerms.map(\.composing) == [false, true])
        #expect(query("abc 하 ", composing: true).nameTerms.map(\.composing) == [false, false])
    }
}

@Suite("NameMatcher")
struct NameMatcherTests {
    private func grade(_ term: String, _ name: String, composing: Bool = false) -> NameMatcher.Grade? {
        NameMatcher(term: term, composing: composing).match(name)?.grade
    }

    private func score(_ term: String, _ name: String) -> Int {
        NameMatcher(term: term).match(name)?.score ?? -1
    }

    @Test func 등급은_정확_접두_경계_부분_퍼지_순() {
        #expect(grade("main", "main") == .exact)
        #expect(grade("main", "mainView.swift") == .prefix)
        #expect(grade("view", "mainView.swift") == .boundary)
        #expect(grade("ain", "mainView.swift") == .substring)
        #expect(grade("mvs", "mainView.swift") == .fuzzy)
        #expect(score("main", "main") > score("main", "mainView.swift"))
        #expect(score("view", "mainView.swift") > score("ain", "mainView.swift"))
        #expect(score("ain", "mainView.swift") > score("mvs", "mainView.swift"))
    }

    @Test func 확장자를_뺀_이름도_정확_일치() {
        #expect(grade("readme", "README.md") == .exact)
        #expect(grade("readme", "README.old.md") == .prefix)
    }

    @Test func ASCII_대소문자를_무시한다() {
        #expect(grade("MCAP", "mCapture.app") == .prefix)
        #expect(grade("mcap", "MCAPTURE") == .prefix)
    }

    @Test func 초성만으로_한글_이름을_찾는다() {
        #expect(grade("ㅎㄱ", "한글.txt") == .exact)
        #expect(grade("ㅎㄱ", "하늘") == nil)
        #expect(grade("ㅂㄱㅅ", "주간 보고서.pdf") == .boundary)
    }

    @Test func 음절과_초성을_섞어도_찾는다() {
        #expect(grade("한ㄱ", "한글") == .exact)
        #expect(grade("한ㄴ", "한글") == nil)
    }

    @Test func 조합_중_마지막_음절은_받침_없이_비교한다() {
        #expect(grade("하", "한글", composing: true) == .prefix)
        #expect(grade("한그", "한글", composing: true) == .exact)
        #expect(grade("하", "한글") == nil)
    }

    @Test func NFD_이름도_찾는다() {
        #expect(grade("보고서", "보고서.pdf".decomposedStringWithCanonicalMapping) == .exact)
    }

    @Test func 경계_보너스가_순위를_가른다() {
        #expect(score("fb", "foo_bar") > score("fb", "fabric"))
        #expect(score("gc", "GitClient") > score("gc", "logic"))
    }

    @Test func 하이라이트_위치는_스칼라_기준() {
        #expect(NameMatcher(term: "ㅎㄱ").positions("한글.txt") == [0, 1])
        #expect(NameMatcher(term: "view").positions("mainView.swift") == [4, 5, 6, 7])
        #expect(NameMatcher(term: "fb").positions("foo_bar") == [0, 4])
        #expect(NameMatcher(term: "doc").positions("😀doc") == [1, 2, 3])
    }

    @Test func 일치하지_않으면_nil() {
        #expect(grade("xyz", "main.swift") == nil)
        #expect(grade("mainn", "main") == nil)
        #expect(NameMatcher(term: "xyz").positions("main.swift").isEmpty)
    }

    @Test func 바이트_사전_필터는_부분_수열만_통과시킨다() {
        let matcher = NameMatcher(term: "MVS")
        let pass = Array("mainView.swift".utf8)
        let fail = Array("main.txt".utf8)
        #expect(pass.withUnsafeBufferPointer { matcher.mayMatch(utf8: $0) })
        #expect(!fail.withUnsafeBufferPointer { matcher.mayMatch(utf8: $0) })
        // ASCII가 아닌 검색어는 바이트로 판단하지 않는다
        #expect(fail.withUnsafeBufferPointer { NameMatcher(term: "ㅎ").mayMatch(utf8: $0) })
    }
}
