import CoreGraphics
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

@Suite("KeyChord")
struct KeyChordTests {
    @Test func 문자열은_왕복한다() throws {
        for text in ["shift+cmd+left", "space", "f5", "ctrl+opt+shift+cmd+k", "cmd+minus", "escape"] {
            let chord = try #require(KeyChord(string: text), "\(text)")
            #expect(chord.stringValue == text)
            #expect(KeyChord(string: chord.stringValue) == chord)
        }
    }

    @Test func 대소문자_공백_별칭을_너그럽게_읽는다() {
        #expect(KeyChord(string: " Command + W ")?.stringValue == "cmd+w")
        #expect(KeyChord(string: "alt+esc")?.stringValue == "opt+escape")
        #expect(KeyChord(string: "enter")?.stringValue == "return")
        #expect(KeyChord(string: "shift+cmd+Backspace")?.stringValue == "shift+cmd+delete")
        #expect(KeyChord(string: "Control+Option+PgDn")?.stringValue == "ctrl+opt+pagedown")
    }

    @Test func 잘못된_입력은_거부한다() {
        for text in ["", "cmd", "cmd+shift", "w+e", "cmd+keypad1", "cmd+=", "cmd+#", "cmd+ w e"] {
            #expect(KeyChord(string: text) == nil, "\(text)")
        }
    }

    @Test func 녹화한_키_코드로_만들면_문자열과_같다() throws {
        let w = try #require(KeyChord(keyCode: 13, modifiers: [.command]))
        #expect(w.stringValue == "cmd+w")
        let left = try #require(KeyChord(keyCode: 123, modifiers: [.command, .shift]))
        #expect(left.stringValue == "shift+cmd+left")
        #expect(KeyChord(string: "cmd+shift+left") == left)   // 읽을 때는 순서가 자유롭다
        #expect(left == KeyChord(string: left.stringValue))
        #expect(KeyChord(keyCode: 0xFFFF, modifiers: [.command]) == nil)
    }

    @Test func 표시_문자열() throws {
        #expect(try #require(KeyChord(string: "cmd+shift+left")).displayString == "⇧⌘←")
        #expect(try #require(KeyChord(string: "space")).displayString == "Space")
        #expect(try #require(KeyChord(string: "f5")).displayString == "F5")
        #expect(try #require(KeyChord(string: "ctrl+opt+shift+cmd+k")).displayString == "⌃⌥⇧⌘K")
        #expect(try #require(KeyChord(string: "cmd+comma")).displayString == "⌘,")
    }

    @Test func HotKeySpec의_키는_같은_키_코드의_KeyChord가_된다() throws {
        for (name, code) in HotKeySpec.keyCodes {
            let key = try #require(KeyChord.key(named: name), "\(name)")
            #expect(UInt32(key.keyCode) == code)
            #expect(key.group == KeyChord.Key.Group.character)
        }
        let spec = try #require(HotKeySpec(string: "ctrl+shift+4"))
        #expect(spec.chord == KeyChord(string: "ctrl+shift+4"))
        #expect(spec.chord.displayString == spec.displayString)
    }

    @Test func 키_이름에_구분자가_없고_중복이_없다() {
        let names = KeyChord.keys.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Set(KeyChord.keys.map(\.keyCode)).count == names.count)
        for name in names {
            #expect(name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }, "\(name)")
        }
    }
}

@Suite("KeyEventSequence")
struct KeyEventSequenceTests {
    private func step(_ code: UInt16, _ down: Bool, _ flags: CGEventFlags = []) -> KeyEventStep {
        KeyEventStep(keyCode: code, isDown: down, flags: flags)
    }

    private func sequence(_ text: String) throws -> [KeyEventStep] {
        try #require(KeyChord(string: text), "\(text)").eventSequence
    }

    @Test func 수식키가_없으면_키_down_up만() throws {
        let space = try sequence("space")
        #expect(space == [step(49, true), step(49, false)])
        let f11 = try sequence("f11")
        #expect(f11 == [step(103, true, [.maskSecondaryFn]), step(103, false, [.maskSecondaryFn])])
    }

    @Test func 수식키는_키를_앞뒤로_감싼다() throws {
        let steps = try sequence("cmd+w")
        #expect(steps == [
            step(55, true, [.maskCommand]),
            step(13, true, [.maskCommand]),
            step(13, false, [.maskCommand]),
            step(55, false),
        ])
    }

    @Test func 수식키_down은_순서대로_플래그가_쌓이고_up은_역순으로_줄어든다() throws {
        let steps = try sequence("ctrl+opt+shift+cmd+k")
        #expect(steps.map(\.keyCode) == [59, 58, 56, 55, 40, 40, 55, 56, 58, 59])
        let all: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        #expect(steps == [
            step(59, true, [.maskControl]),
            step(58, true, [.maskControl, .maskAlternate]),
            step(56, true, [.maskControl, .maskAlternate, .maskShift]),
            step(55, true, all),
            step(40, true, all),
            step(40, false, all),
            step(55, false, [.maskControl, .maskAlternate, .maskShift]),
            step(56, false, [.maskControl, .maskAlternate]),
            step(58, false, [.maskControl]),
            step(59, false),
        ])
    }

    @Test func Fn_숫자패드_플래그는_키_이벤트에만_붙는다() throws {
        let steps = try sequence("shift+cmd+left")
        let keyFlags: CGEventFlags = [.maskShift, .maskCommand, .maskSecondaryFn, .maskNumericPad]
        #expect(steps == [
            step(56, true, [.maskShift]),
            step(55, true, [.maskShift, .maskCommand]),
            step(123, true, keyFlags),
            step(123, false, keyFlags),
            step(55, false, [.maskShift]),
            step(56, false),
        ])
        // 수식키 이벤트에는 Fn·숫자 패드가 붙지 않는다
        #expect(steps.filter { $0.keyCode != 123 }.allSatisfy { $0.flags.isDisjoint(with: [.maskSecondaryFn, .maskNumericPad]) })
    }

    @Test func 수식키_키_코드는_키_표와_겹치지_않고_모든_수식키를_덮는다() {
        let codes = KeyModifiers.keyCodes
        #expect(codes.map(\.keyCode) == [59, 58, 56, 55])
        #expect(Set(codes.map(\.keyCode)).isDisjoint(with: KeyChord.keys.map(\.keyCode)))
        #expect(codes.reduce(KeyModifiers()) { $0.union($1.modifier) } == [.control, .option, .shift, .command])
    }

    @Test func 수식키_플래그_매핑() {
        #expect(KeyModifiers([.control, .option, .shift, .command]).eventFlags == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        #expect(KeyModifiers().eventFlags == [])
        #expect(KeyChord.Key.Group.arrow.eventFlags == [.maskSecondaryFn, .maskNumericPad])
        #expect(KeyChord.Key.Group.navigation.eventFlags == [.maskSecondaryFn])
        #expect(KeyChord.Key.Group.function.eventFlags == [.maskSecondaryFn])
        #expect(KeyChord.Key.Group.character.eventFlags == [])
        #expect(KeyChord.Key.Group.control.eventFlags == [])
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

    @Test func RGB_문자열은_HEX와_같은_값이고_반투명이면_rgba() throws {
        #expect(try #require(RGBAColor(hex: "#FF3B30")).rgbString == "rgb(255, 59, 48)")
        #expect(try #require(RGBAColor(hex: "#00000080")).rgbString == "rgba(0, 0, 0, 0.5)")
        #expect(RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.25).rgbString == "rgba(255, 255, 255, 0.25)")
        #expect(RGBAColor(red: 0, green: 0, blue: 0, alpha: 0).rgbString == "rgba(0, 0, 0, 0)")
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
        let keys = ["4", "1", "3", "5", "6", "f"]
        let production = try keys.map { try #require(HotKeySpec(string: AppVariant.production.defaultHotkey(key: $0))) }
        let dev = try keys.map { try #require(HotKeySpec(string: AppVariant.dev.defaultHotkey(key: $0))) }
        #expect(production.map(\.displayString) == ["⌃⇧4", "⌃⇧1", "⌃⇧3", "⌃⇧5", "⌃⇧6", "⌃⇧F"])
        #expect(Set(production.map(\.stringValue)).isDisjoint(with: dev.map(\.stringValue)))
    }
}

@Suite("AppVersion")
struct AppVersionTests {
    @Test func 버전과_빌드_번호를_함께_보여_준다() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "1"]
        #expect(AppVersion(infoDictionary: info).displayString == "0.1.1 (1)")
    }

    @Test func 커밋이_있으면_빌드_번호_대신_보여_준다() {
        var info: [String: Any] = ["CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "1", AppVersion.commitKey: "344637f"]
        #expect(AppVersion(infoDictionary: info).displayString == "0.1.1 (344637f)")
        info[AppVersion.commitKey] = "344637f-dirty"
        #expect(AppVersion(infoDictionary: info).displayString == "0.1.1 (344637f-dirty)")
    }

    @Test func 한쪽만_있으면_있는_값만_보여_준다() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.2.0"]).displayString == "0.2.0")
        #expect(AppVersion(infoDictionary: ["CFBundleVersion": "7"]).displayString == "빌드 7")
    }

    @Test func 번들_없이_실행하면_알_수_없음() {
        #expect(AppVersion(infoDictionary: nil).displayString == "알 수 없음")
        // 빈 문자열이나 문자열이 아닌 값은 없는 것으로 본다
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": " ", "CFBundleVersion": 3]).displayString == "알 수 없음")
    }
}
