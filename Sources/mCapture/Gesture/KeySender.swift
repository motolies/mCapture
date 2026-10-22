import AppKit
import MCaptureCore

/// 키 조합을 지금 앞에 있는 앱으로 보낸다 (CGEvent를 HID 이벤트 탭에 post). 손쉬운 사용 권한이 필요하다
@MainActor
enum KeySender {
    /// 마우스 버튼이 떨어지기를 기다리는 한도. 넘기면 드래그로 보고 보내지 않는다
    private static let buttonReleaseTimeout: Duration = .seconds(1)

    /// 보냈거나 보내기로 예약했으면 true. 권한이 없으면 보내지 않는다 (보내도 시스템이 조용히 버린다).
    /// 클릭 제스처는 버튼을 누르는 순간 발화하므로 마우스 버튼이 눌려 있으면 떨어진 뒤에 보낸다 (앞 앱이 마우스 추적 중에 키를 받지 않게)
    @discardableResult
    static func send(_ chord: KeyChord) -> Bool {
        guard AccessibilityPermission.isGranted else { return false }
        if NSEvent.pressedMouseButtons == 0 {
            post(chord)
        } else {
            postAfterMouseButtonsReleased(chord)
        }
        return true
    }

    // 수식키 down → 키 down/up → 수식키 up 순서(KeyChord.eventSequence)로 HID 탭에 post한다.
    // 이벤트를 전부 먼저 만들어 하나라도 못 만들면 아무것도 보내지 않는다 (수식키 down만 나가 눌린 채 남지 않게).
    // 같은 스레드에서 차례로 post하면 순서가 보존되므로 지연은 두지 않는다
    private static func post(_ chord: KeyChord) {
        let source = CGEventSource(stateID: .hidSystemState)
        let steps = chord.eventSequence
        let events = steps.compactMap { step -> CGEvent? in
            let event = CGEvent(keyboardEventSource: source, virtualKey: step.keyCode, keyDown: step.isDown)
            event?.flags = step.flags
            return event
        }
        guard events.count == steps.count else {
            Log.gesture.error("키 이벤트를 만들 수 없음: \(chord.stringValue, privacy: .public)")
            return
        }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
    }

    // 16ms마다 버튼 상태를 보고 모두 떨어지면 보낸다. 한도를 넘기면(드래그) 보내지 않고 로그만 남긴다
    private static func postAfterMouseButtonsReleased(_ chord: KeyChord) {
        Task { @MainActor in
            let deadline = ContinuousClock.now + buttonReleaseTimeout
            while NSEvent.pressedMouseButtons != 0 {
                guard ContinuousClock.now < deadline else {
                    Log.gesture.info("마우스 버튼이 1초 넘게 눌려 있어 키를 보내지 않음: \(chord.stringValue, privacy: .public)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            post(chord)
        }
    }
}
