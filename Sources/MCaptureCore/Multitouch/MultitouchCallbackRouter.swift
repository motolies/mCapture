import Foundation
import os

/// 비공개 프레임워크의 C 콜백을 장치별 핸들러로 보낸다.
///
/// `MTRegisterContactFrameCallback`은 컨텍스트 없는 C 함수 포인터만 받고(버튼 콜백에는 refcon 변종도 없다),
/// 등록·해제에 같은 포인터를 넘겨야 하므로 콜백은 전역 `static let` 하나씩만 둔다.
/// 핸들러 표는 잠금으로 보호하고, 콜백은 잠금 밖에서 핸들러를 부른다. 한 프로세스에서 장치 하나는 소스 하나가 맡는다
enum MultitouchCallbackRouter {
    typealias FrameHandler = @Sendable (TouchFrame) -> Void
    typealias ButtonHandler = @Sendable (_ state: Int32, _ previous: Int32) -> Void

    static let frames = OSAllocatedUnfairLock(initialState: [UInt: FrameHandler]())
    static let buttons = OSAllocatedUnfairLock(initialState: [UInt: ButtonHandler]())

    /// 장치 포인터 비트에 핸들러를 건다. 핸들러는 파이프라인을 잡아야 한다 (소스가 멈추는 중에 들어온 콜백도 살아 있는 큐에 떨어지도록)
    static func register(device key: UInt, frame: @escaping FrameHandler, button: @escaping ButtonHandler) {
        frames.withLock { $0[key] = frame }
        buttons.withLock { $0[key] = button }
    }

    /// 핸들러를 뗀다
    static func unregister(device key: UInt) {
        frames.withLock { $0[key] = nil }
        buttons.withLock { $0[key] = nil }
    }

    /// 접촉 프레임 콜백. 콜백 동안만 유효한 버퍼를 즉시 값으로 복사한다
    static let frameCallback: MTFrameCallback = { device, touches, count, timestamp, _ in
        let key = UInt(bitPattern: device)
        guard let handler = frames.withLock({ $0[key] }) else { return 0 }
        handler(TouchFrame(timestamp: timestamp, contacts: TouchRecord.copy(from: touches, count: count)))
        return 0
    }

    /// 버튼 콜백. 실측: (장치, 새 상태, 이전 상태, 쓰레기). 1=왼쪽, 2=오른쪽, 0=뗌
    static let buttonCallback: MTButtonCallback = { device, state, previous, _ in
        let key = UInt(bitPattern: device)
        guard let handler = buttons.withLock({ $0[key] }) else { return 0 }
        handler(state, previous)
        return 0
    }
}
