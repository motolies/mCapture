import CoreGraphics
import Foundation
import MCaptureCore

/// 물리 버튼 클릭을 듣는 CGEventTap (듣기 전용, 이벤트를 바꾸지 않는다).
/// 매직마우스는 윗면 전체가 버튼이라 클릭은 멀티터치 프레임이 아니라 마우스 이벤트로 온다.
/// 클릭 순간의 손가락 수는 FrameSink가 최신 프레임의 접촉 수로 센다 (BTT·MiddleClick과 같은 방식)
@MainActor
enum ClickMonitor {
    private static var tap: CFMachPort?

    /// 탭을 만들어 메인 런루프에 건다. 못 만들면 false (입력 모니터링 권한이 없을 때 그렇다)
    static func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: clickCallback, userInfo: nil
        ) else { return false }
        Self.tap = tap
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

/// 이벤트 탭 콜백. 버튼 종류와 누름/뗌만 싱크에 넘기고 이벤트는 손대지 않고 돌려준다.
/// 탭을 메인 런루프에 걸었으므로 메인 스레드에서 불린다
let clickCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .leftMouseDown: sink.button(.left, down: true)
    case .leftMouseUp: sink.button(.left, down: false)
    case .rightMouseDown: sink.button(.right, down: true)
    case .rightMouseUp: sink.button(.right, down: false)
    case .otherMouseDown: sink.button(.other(Int(event.getIntegerValueField(.mouseEventButtonNumber))), down: true)
    case .otherMouseUp: sink.button(.other(Int(event.getIntegerValueField(.mouseEventButtonNumber))), down: false)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { ClickMonitor.reenable() }
    default: break
    }
    return Unmanaged.passUnretained(event)
}
