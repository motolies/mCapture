import Carbon.HIToolbox
import MCaptureCore

/// Carbon 전역 단축키 등록. 손쉬운 사용 권한 없이 동작한다
@MainActor
final class HotKeyCenter {
    enum Action: UInt32, CaseIterable, Identifiable {
        case area = 1
        case fullscreen = 2
        case window = 3
        case ocr = 4
        /// 새 동작은 끝에 둔다. 등록 순서라 기본값이 바꿔 둔 단축키와 겹치면 새 동작이 꺼진다
        case color = 5

        var id: UInt32 { rawValue }

        /// 설정 화면에 보이는 이름
        var title: String {
            switch self {
            case .area: "영역 캡처"
            case .fullscreen: "전체 화면 캡처"
            case .window: "창 캡처"
            case .ocr: "텍스트 인식"
            case .color: "컬러 피커"
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    /// 단축키 이벤트 처리기를 앱 이벤트 대상에 한 번 설치한다
    func install() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Carbon은 메인 스레드에서 콜백을 호출한다
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            MainActor.assumeIsolated {
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().handle(id: id)
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }

    /// 단축키를 등록한다. 같은 동작의 기존 단축키는 먼저 해제한다
    @discardableResult
    func register(_ spec: HotKeySpec, for action: Action) -> Bool {
        unregister(action)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.app.error("단축키 등록 실패 \(spec.stringValue, privacy: .public): \(status)")
            return false
        }
        refs[action] = ref
        return true
    }

    func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    /// 모든 단축키를 해제한다. 설정에서 단축키를 녹화하는 동안 Carbon이 키를 먼저 가로채지 않게 한다
    func unregisterAll() {
        Action.allCases.forEach(unregister)
    }

    // 등록 id로 동작을 찾아 전달한다
    private func handle(id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        onAction?(action)
    }

    /// 'mCap' 네 글자 서명
    private static let signature: OSType = "mCap".utf8.reduce(0) { ($0 << 8) | OSType($1) }
}
