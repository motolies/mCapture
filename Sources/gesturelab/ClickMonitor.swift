import CoreGraphics
import Foundation
import MCaptureCore

/// 물리 버튼 클릭을 듣는 CGEventTap (듣기 전용, 이벤트를 바꾸지 않는다).
/// 매직마우스는 윗면 전체가 버튼이라 클릭은 멀티터치 프레임이 아니라 마우스 이벤트로 온다.
/// MT 버튼 콜백이 1순위 출처이고 이것은 MT 콜백이 없는 장치를 위한 보조 경로다 (입력 모니터링 권한 필요)
@MainActor
enum ClickMonitor {
    private static var tap: CFMachPort?
    fileprivate static var handler: ((MouseButton, Bool) -> Void)?

    /// 탭을 만들어 메인 런루프에 건다. 못 만들면 false (입력 모니터링 권한이 없을 때 그렇다)
    static func start(handler: @escaping (MouseButton, Bool) -> Void) -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: clickCallback, userInfo: nil
        ) else { return false }
        Self.tap = tap
        Self.handler = handler
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 시스템이 탭을 껐을 때(콜백 지연 등) 다시 켠다
    static func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// 이벤트 탭 콜백. 버튼 종류와 누름/뗌만 핸들러에 넘기고 이벤트는 손대지 않고 돌려준다.
/// 탭을 메인 런루프에 걸었으므로 메인 스레드에서 불린다
let clickCallback: CGEventTapCallBack = { _, type, event, _ in
    // CGEvent는 Sendable이 아니라 격리 경계를 넘기기 전에 필요한 값만 읽는다
    let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    MainActor.assumeIsolated {
        switch type {
        case .leftMouseDown: ClickMonitor.handler?(.left, true)
        case .leftMouseUp: ClickMonitor.handler?(.left, false)
        case .rightMouseDown: ClickMonitor.handler?(.right, true)
        case .rightMouseUp: ClickMonitor.handler?(.right, false)
        case .otherMouseDown: ClickMonitor.handler?(.other(number), true)
        case .otherMouseUp: ClickMonitor.handler?(.other(number), false)
        case .tapDisabledByTimeout, .tapDisabledByUserInput: ClickMonitor.reenable()
        default: break
        }
    }
    return Unmanaged.passUnretained(event)
}
