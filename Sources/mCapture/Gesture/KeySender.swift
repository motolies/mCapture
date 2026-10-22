import CoreGraphics
import MCaptureCore

/// 키 조합을 지금 앞에 있는 앱으로 보낸다 (CGEvent를 HID 이벤트 탭에 post). 손쉬운 사용 권한이 필요하다
@MainActor
enum KeySender {
    /// 보냈으면 true. 권한이 없으면 보내지 않는다 (보내도 시스템이 조용히 버린다)
    @discardableResult
    static func send(_ chord: KeyChord) -> Bool {
        guard AccessibilityPermission.isGranted else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = flags(for: chord)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: chord.key.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.key.keyCode, keyDown: false)
        else { return false }
        // 수식키는 별도 이벤트 없이 플래그로만 보낸다. 플래그를 무시하는 앱이 나오면 수식키 down/up을 앞뒤에 붙인다
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // 수식키 플래그와 실제 키보드가 붙이는 플래그. 탐색·F키는 Fn, 화살표는 Fn과 숫자 패드
    private static func flags(for chord: KeyChord) -> CGEventFlags {
        var flags: CGEventFlags = []
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        switch chord.key.group {
        case .navigation, .function: flags.insert(.maskSecondaryFn)
        case .arrow: flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        case .character, .control: break
        }
        return flags
    }
}
