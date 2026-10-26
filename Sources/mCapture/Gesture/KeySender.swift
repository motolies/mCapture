import AppKit
import MCaptureCore

/// 키 조합을 지금 앞에 있는 앱으로 보낸다 (CGEvent를 HID 이벤트 탭에 post). 손쉬운 사용 권한이 필요하다
@MainActor
enum KeySender {
    /// 보냈거나 보내기로 예약했으면 true. 권한이 없으면 보내지 않는다 (보내도 시스템이 조용히 버린다).
    /// 마우스 버튼이 눌려 있으면 떨어진 뒤에 보낸다 (앞 앱이 마우스 추적 중에 키를 받지 않게).
    /// 클릭 제스처(afterClick)는 발화 순간 시스템에 아직 눌림이 안 보이므로 눌림이 보일 때까지 기다린다 (MouseReleaseGate)
    @discardableResult
    static func send(_ chord: KeyChord, afterClick: Bool = false) -> Bool {
        guard AccessibilityPermission.isGranted else { return false }
        var gate = MouseReleaseGate.forGesture(isClick: afterClick)
        switch gate.update(pressed: NSEvent.pressedMouseButtons != 0, elapsed: .zero) {
        case .send:
            post(chord)
        case .wait:
            postWhenReleased(chord, gate: gate)
        case .abandon:
            break
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

    // 16ms마다 버튼 상태를 판정기에 넣어 보낼 때가 되면 보낸다. 한도를 넘기면(드래그) 보내지 않고 로그만 남긴다.
    // 기다린 시간과 눌림을 봤는지 남겨, 실기기에서 대기 경로를 탔는지 확인한다
    private static func postWhenReleased(_ chord: KeyChord, gate: MouseReleaseGate) {
        let start = ContinuousClock.now
        Task { @MainActor in
            var gate = gate
            while true {
                try? await Task.sleep(for: .milliseconds(16))
                let elapsed = ContinuousClock.now - start
                switch gate.update(pressed: NSEvent.pressedMouseButtons != 0, elapsed: elapsed) {
                case .wait:
                    continue
                case .send:
                    post(chord)
                    let ms = Int(elapsed / .milliseconds(1))
                    Log.gesture.info("키 보냄: \(chord.stringValue, privacy: .public) (\(ms)ms 대기, 눌림 \(gate.sawPress ? "확인" : "못 봄", privacy: .public))")
                case .abandon:
                    Log.gesture.info("마우스 버튼이 1초 넘게 눌려 있어 키를 보내지 않음: \(chord.stringValue, privacy: .public)")
                }
                return
            }
        }
    }
}
