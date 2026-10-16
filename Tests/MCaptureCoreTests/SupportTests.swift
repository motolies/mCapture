import Foundation
import Testing
@testable import MCaptureCore

@Suite("History")
struct HistoryTests {
    @Test func 실행_취소와_다시_실행() {
        var history = History<Int>()
        var current = 0
        for next in 1...3 {
            history.record(current)
            current = next
        }
        current = history.undo(current: current)!
        current = history.undo(current: current)!
        #expect(current == 1)
        current = history.redo(current: current)!
        #expect(current == 2)
        #expect(history.canRedo)
    }

    @Test func 새_변경은_다시_실행_기록을_지운다() {
        var history = History<Int>()
        history.record(0)
        _ = history.undo(current: 1)
        history.record(0)
        #expect(!history.canRedo)
    }

    @Test func 제한을_넘으면_오래된_기록부터_버린다() {
        var history = History<Int>(limit: 2)
        history.record(1)
        history.record(2)
        history.record(3)
        #expect(history.undo(current: 4) == 3)
        #expect(history.undo(current: 3) == 2)
        #expect(history.undo(current: 2) == nil)
    }
}

@Suite("FileNaming")
struct FileNamingTests {
    let date = Date(timeIntervalSince1970: 1_792_116_332)  // 2026-10-16 02:05:32 UTC
    let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func name(_ template: String, app: String? = nil) -> String {
        FileNaming.baseName(template: template, date: date, appName: app, timeZone: seoul)
    }

    @Test func 기본_형식은_예전_파일_이름과_같다() {
        #expect(name(FileNaming.defaultTemplate) == "mCapture_2026-10-16_11-05-32")
    }

    @Test func 날짜_시각_토큰을_바꾼다() {
        // {MM}은 월, {mm}은 분
        #expect(name("{yyyy}.{yy}.{MM}.{dd} {HH}.{mm}.{ss}") == "2026.26.10.16 11.05.32")
        #expect(name("캡처 {date} {time}") == "캡처 2026-10-16 11-05-32")
    }

    @Test func 앱_이름이_없으면_mCapture를_쓴다() {
        #expect(name("{app} {date}", app: "Safari") == "Safari 2026-10-16")
        #expect(name("{app} {date}") == "mCapture 2026-10-16")
        #expect(name("{app}", app: "  ") == "mCapture")
    }

    @Test func 모르는_토큰은_그대로_둔다() {
        #expect(name("{foo}_{date}") == "{foo}_2026-10-16")
    }

    @Test func 파일_이름에_곤란한_글자를_정리한다() {
        #expect(name("a/b:c\nd") == "a-b-c-d")
        #expect(name("{app}", app: "AC/DC") == "AC-DC")
        #expect(name("..hidden") == "hidden")
        #expect(name(" shot.PNG ") == "shot")
    }

    @Test func 긴_이름은_바이트_기준으로_자른다() {
        let result = name(String(repeating: "가", count: 100))  // 300바이트
        #expect(result.utf8.count <= 200)
        #expect(result == String(repeating: "가", count: 66))
    }

    @Test func 비면_기본_형식을_쓴다() {
        #expect(name("") == "mCapture_2026-10-16_11-05-32")
        #expect(name("  .png ") == "mCapture_2026-10-16_11-05-32")
    }

    @Test func 중복되면_접미사를_붙인다() {
        let folder = URL(fileURLWithPath: "/tmp/shots")
        let taken: Set<String> = ["/tmp/shots/a.png", "/tmp/shots/a_2.png"]
        let url = FileNaming.uniqueURL(in: folder, baseName: "a", ext: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "a_3.png")
    }
}

@Suite("HotKeySpec")
struct HotKeySpecTests {
    @Test func 문자열을_파싱한다() throws {
        let spec = try #require(HotKeySpec(string: "Shift + CTRL + 4"))
        #expect(spec.keyCode == 21)
        #expect(spec.modifiers == [.control, .shift])
        #expect(spec.stringValue == "ctrl+shift+4")
        #expect(spec.displayString == "⌃⇧4")
        #expect(spec.carbonModifiers == 4096 | 512)
    }

    @Test func 잘못된_입력은_거부한다() {
        #expect(HotKeySpec(string: "shift+4") == nil)        // ⌘·⌃·⌥ 없음
        #expect(HotKeySpec(string: "cmd+4+5") == nil)        // 키 두 개
        #expect(HotKeySpec(string: "cmd+f13") == nil)        // 지원하지 않는 키
        #expect(HotKeySpec(string: "") == nil)
    }

    @Test func 녹화한_키_코드로_만들면_문자열과_같다() throws {
        // ⌃⌥ + 2 (키 코드 19)
        let recorded = try #require(HotKeySpec(keyCode: 19, modifiers: [.control, .option]))
        #expect(recorded.stringValue == "ctrl+opt+2")
        #expect(recorded == HotKeySpec(string: recorded.stringValue))
        #expect(recorded.modifiers.symbols == "⌃⌥")
    }

    @Test func 녹화한_조합이_올바르지_않으면_nil() {
        #expect(HotKeySpec(keyCode: 19, modifiers: [.shift]) == nil)     // ⌘·⌃·⌥ 없음
        #expect(HotKeySpec(keyCode: 53, modifiers: [.command]) == nil)   // Esc는 지원하지 않는 키
    }
}

@Suite("RGBAColor")
struct RGBAColorTests {
    @Test func HEX_변환() throws {
        let color = try #require(RGBAColor(hex: "#FF3B30"))
        #expect(color.hex == "#FF3B30")
        #expect(RGBAColor(hex: "12345") == nil)
        #expect(RGBAColor(hex: "#00000080")?.alpha ?? 0 > 0.49)
    }
}

@Suite("AppVariant")
struct AppVariantTests {
    @Test func 원래_번들_ID일_때만_production() {
        #expect(AppVariant(bundleIdentifier: "com.motolies.mcapture") == .production)
        #expect(AppVariant(bundleIdentifier: "com.motolies.mcapture.dev") == .dev)
        #expect(AppVariant(bundleIdentifier: "com.example.other") == .dev)
        #expect(AppVariant(bundleIdentifier: nil) == .dev)   // 번들 없이 실행한 경우
    }

    @Test func 번들_ID는_판정과_왕복한다() {
        for variant in [AppVariant.production, .dev] {
            #expect(AppVariant(bundleIdentifier: variant.bundleIdentifier) == variant)
        }
    }

    @Test func 변형끼리_겹치는_값이_없다() {
        let production = AppVariant.production
        let dev = AppVariant.dev
        #expect(production.bundleIdentifier != dev.bundleIdentifier)
        #expect(production.displayName != dev.displayName)
        #expect(production.urlScheme != dev.urlScheme)
        #expect(production.defaultSaveFolder != dev.defaultSaveFolder)
        #expect(production.dragFolderName != dev.dragFolderName)
    }

    @Test func 기본_단축키는_올바르고_변형끼리_겹치지_않는다() throws {
        let keys = ["4", "1", "3", "5"]
        let production = try keys.map { try #require(HotKeySpec(string: AppVariant.production.defaultHotkey(key: $0))) }
        let dev = try keys.map { try #require(HotKeySpec(string: AppVariant.dev.defaultHotkey(key: $0))) }
        #expect(production.map(\.displayString) == ["⌃⇧4", "⌃⇧1", "⌃⇧3", "⌃⇧5"])
        #expect(Set(production.map(\.stringValue)).isDisjoint(with: dev.map(\.stringValue)))
    }
}
