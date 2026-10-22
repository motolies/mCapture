import AppKit
import MCaptureCore
import SwiftUI

/// 설정 화면의 키 조합 녹화 (전역 단축키·제스처로 보낼 키 공용). 한 번에 하나만 녹화하고,
/// 녹화하는 동안 전역 단축키를 해제하게 알린다 (같은 조합을 눌러도 캡처가 시작되지 않게)
@MainActor
final class KeyRecorder {
    struct Session {
        /// 지금 누르고 있는 수식키가 바뀌었을 때 (버튼 미리보기)
        var modifiersChanged: (KeyModifiers) -> Void
        /// 키를 눌렀을 때. true를 돌려주면 받아들인 것으로 보고 녹화를 끝내고, false면 안내만 하고 계속 기다린다
        var keyPressed: (_ keyCode: UInt16, _ modifiers: KeyModifiers) -> Bool
        /// 녹화가 끝났을 때. Esc·stop()·다른 녹화 시작으로 끝났으면 cancelled
        var ended: (_ cancelled: Bool) -> Void
    }

    private(set) var isRecording = false
    private var session: Session?
    private var monitor: Any?

    /// 녹화를 시작한다. 진행 중이던 세션은 취소로 끝낸다 (단축키 해제 알림은 처음 시작할 때 한 번만)
    func start(_ session: Session) {
        let wasRecording = self.session != nil
        end(cancelled: true, notify: false)
        self.session = session
        isRecording = true
        if !wasRecording {
            NotificationCenter.default.post(name: .mcaptureHotKeyRecording, object: true)
        }
        // 메뉴 단축키(⌘Q 등)보다 먼저 받도록 로컬 모니터로 가로챈다
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    /// 녹화를 취소한다 (창 닫힘·비활성·탭 전환)
    func stop() {
        end(cancelled: true, notify: true)
    }

    // 키 이벤트를 처리한다. 삼켰으면 true. 수식키 없이 Esc만 누르면 취소
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        let modifiers = KeyModifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            session.modifiersChanged(modifiers)
            return false
        }
        if event.keyCode == 53, modifiers.isEmpty {
            end(cancelled: true, notify: true)
            return true
        }
        if session.keyPressed(UInt16(event.keyCode), modifiers) {
            end(cancelled: false, notify: true)
        }
        return true
    }

    // 모니터를 떼고 세션을 끝낸다. notify면 전역 단축키를 다시 등록하게 알린다
    private func end(cancelled: Bool, notify: Bool) {
        guard let session else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        self.session = nil
        isRecording = false
        if notify {
            NotificationCenter.default.post(name: .mcaptureHotKeyRecording, object: false)
        }
        session.ended(cancelled)
    }
}

/// 키 조합 녹화 버튼. 녹화 중에는 강조하고 지금 누른 수식키를 보여 준다 (단축키·보낼 키 공용)
struct KeyRecorderButton: View {
    let isRecording: Bool
    let pressedModifiers: String
    /// 녹화 중이 아닐 때 보이는 현재 값
    let title: String
    let toggle: () -> Void

    var body: some View {
        if isRecording {
            Button(action: toggle) {
                Text(pressedModifiers.isEmpty ? "키 조합을 누르세요…" : pressedModifiers + " …")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .help("다시 누르면 취소")
        } else {
            Button(action: toggle) {
                Text(title)
                    .monospaced()
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)
            .help("눌러서 새 키 조합 입력")
        }
    }
}

extension KeyModifiers {
    /// NSEvent 수식키 플래그에서 만든다 (Caps Lock·Fn 등은 무시)
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
