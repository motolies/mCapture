import Foundation
import Testing
@testable import MCaptureCore

@Suite("FilterToken")
struct FilterTokenTests {
    let home = "/Users/tester"

    private func extract(_ text: String, includeLast: Bool = false) -> FilterToken.Extraction? {
        FilterToken.extract(from: text, includeLast: includeLast)
    }

    // 비교할 수 있게 SearchQuery의 해석 결과를 값으로 펼친다
    private func fields(_ text: String) -> [String] {
        let q = SearchQuery(text, home: home)
        return [
            q.nameTerms.map(\.text).joined(separator: "|"),
            q.pathTerms.joined(separator: "|"),
            q.extensions.joined(separator: "|"),
            "\(q.kind)",
            q.regexes.map(\.pattern).joined(separator: "|"),
            q.error ?? "",
        ]
    }

    @Test func 확장자_항을_칩으로_떼어_낸다() {
        let result = extract("계약 ext:pdf;.PNG ")
        #expect(result?.tokens == [FilterToken(category: .extensions, value: "pdf·png", raw: "ext:pdf;.PNG")])
        #expect(result?.rest == "계약 ")
    }

    @Test func 공백_전의_마지막_항은_치는_중으로_남긴다() {
        #expect(extract("ext:pdf") == nil)
        #expect(extract("ext:pdf", includeLast: true)?.tokens.map(\.category) == [.extensions])
        #expect(extract("ext:pdf", includeLast: true)?.rest == "")
        #expect(extract("ext:pdf 계약")?.tokens.map(\.category) == [.extensions])
        #expect(extract("ext:pdf 계약")?.rest == "계약")
    }

    @Test func 종류_접두어는_칩과_남은_항으로_나눈다() {
        let result = extract("folder:보고서 ")
        #expect(result?.tokens == [FilterToken(category: .kind, value: "폴더만", raw: "folder:")])
        #expect(result?.rest == "보고서 ")
        #expect(extract("dir: ")?.tokens.first?.raw == "folder:")
        #expect(extract("file: ")?.tokens.first?.value == "파일만")
    }

    @Test func 종류_뒤의_경로_항도_칩이_된다() {
        let result = extract("folder:proj/src ")
        #expect(result?.tokens.map(\.category) == [.kind, .pathContains])
        #expect(result?.rest == "")
    }

    @Test func 경로_항은_위치와_경로_포함으로_나눈다() {
        let result = extract("~/Documents/ proj/src /tmp ")
        #expect(result?.tokens.map(\.category) == [.location, .pathContains, .location])
        #expect(result?.tokens.map(\.value) == ["~/Documents/", "proj/src", "/tmp"])
    }

    @Test func 따옴표_항은_접두어를_해석하지_않지만_경로는_칩이다() {
        #expect(extract("\"ext:pdf\" x ") == nil)
        let result = extract("\"~/My Docs/\" a ")
        #expect(result?.tokens == [FilterToken(category: .location, value: "~/My Docs/", raw: "\"~/My Docs/\"")])
        #expect(result?.rest == "a ")
    }

    @Test func 잘못된_정규식은_오류_칩() {
        let result = extract("regex:([ ")
        #expect(result?.tokens.first?.category == .regex)
        #expect(result?.tokens.first?.isInvalid == true)
        #expect(extract("regex:^IMG ")?.tokens.first?.isInvalid == false)
    }

    @Test func 값이_빈_접두어는_칩이_아니다() {
        #expect(extract("ext: regex: ") == nil)
        #expect(extract("foo:bar ") == nil)
    }

    @Test func 열린_따옴표_안의_공백은_항의_끝이_아니다() {
        #expect(extract("regex:\"a b") == nil)
        #expect(extract("regex:\"a b\" ")?.tokens.first?.value == "a b")
    }

    @Test func 칩과_남은_글자를_이으면_같은_검색이다() {
        let cases = [
            "계약 ext:pdf;png ~/Doc/ folder:보고서 regex:^IMG ",
            "a \"b c\" file: x/y ",
            "folder:ext:pdf ",
            "folder:\"my docs\" ext:md ",
            "\"~/My Docs/\" 한글 ",
        ]
        for text in cases {
            let result = extract(text, includeLast: true)
            #expect(result != nil, "\(text)")
            guard let result else { continue }
            #expect(fields(FilterToken.combine(result.tokens, rest: result.rest)) == fields(text), "\(text)")
        }
    }

    @Test func 메뉴용_칩을_만든다() {
        let docs = FilterToken.location("/Users/tester/My Docs", home: home)
        #expect(docs.raw == "\"~/My Docs/\"")
        #expect(docs.value == "~/My Docs/")
        #expect(FilterToken.location(home, home: home).raw == "~/")
        #expect(FilterToken.location("/Applications", home: home).raw == "/Applications/")
        #expect(FilterToken.kind(.file)?.raw == "file:")
        #expect(FilterToken.kind(.any) == nil)
        #expect(FilterToken.extensions([".PDF", "png"])?.raw == "ext:pdf;png")
        #expect(FilterToken.extensions([]) == nil)
        #expect(FilterToken.regex("a b").raw == "regex:\"a b\"")
        #expect(FilterToken.regex("([").isInvalid)
    }

    @Test func 만든_칩의_원문은_같은_칩으로_다시_읽힌다() {
        let made = [
            FilterToken.location("/Users/tester/My Docs", home: home),
            FilterToken.kind(.folder)!,
            FilterToken.extensions(["pdf", "hwp"])!,
            FilterToken.regex("^IMG \\d+"),
        ]
        for chip in made {
            #expect(extract(chip.raw, includeLast: true)?.tokens == [chip], "\(chip.raw)")
        }
    }

    @Test func 칩만_있으면_남은_글자_없이_잇는다() {
        let chips = [FilterToken.kind(.file)!, FilterToken.extensions(["pdf"])!]
        #expect(FilterToken.combine(chips, rest: "") == "file: ext:pdf")
        #expect(FilterToken.combine(chips, rest: "계약") == "file: ext:pdf 계약")
        #expect(FilterToken.combine([], rest: "계약") == "계약")
    }
}
