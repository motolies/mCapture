import Foundation
import IOKit
import os

/// IORegistry의 AppleMultitouchDevice가 붙거나 빠질 때 알린다 (블루투스 재연결·잠자기 복귀 때 소스를 새로 만드는 신호).
///
/// 알림은 전용 직렬 큐에서 오고, 시작할 때 이미 연결돼 있던 장치는 알리지 않는다.
/// `stop()`은 handler 안에서 부르면 안 된다 (진행 중인 콜백이 끝나길 기다리므로 교착한다). 한 번 멈추면 다시 쓰지 않는다
public final class MultitouchDeviceWatcher: Sendable {
    public enum Change: Sendable, Equatable {
        case attached
        case detached
    }

    /// IOKit 콜백이 refcon으로 되돌려받는 상자. 워처 자신이 아니라 이 상자를 넘겨, 콜백이 도는 동안 워처가 해제돼도 안전하다
    private final class Callbacks: Sendable {
        let handler: @Sendable (Change) -> Void

        init(handler: @Sendable @escaping (Change) -> Void) {
            self.handler = handler
        }
    }

    private enum Phase: Sendable {
        case idle, started, stopped
    }

    private struct State: Sendable {
        var phase = Phase.idle
        /// IONotificationPortRef 비트
        var port: UInt = 0
        /// Callbacks 상자의 retained 포인터 비트
        var callbacks: UInt = 0
        var iterators: [io_iterator_t] = []
    }

    private let handler: @Sendable (Change) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "MCaptureCore.MultitouchDeviceWatcher")

    public init(handler: @Sendable @escaping (Change) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// first-match·terminated 알림을 건다. 등록 직후의 이터레이터(지금 연결된 장치)는 비워서 무장만 한다. 걸 수 없으면 false
    public func start() -> Bool {
        let proceed = state.withLock { state -> Bool in
            guard state.phase == .idle else { return false }
            state.phase = .started
            return true
        }
        guard proceed else { return false }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            state.withLock { $0.phase = .stopped }
            return false
        }
        IONotificationPortSetDispatchQueue(port, queue)
        let callbacks = Unmanaged.passRetained(Callbacks(handler: handler))
        var iterators: [io_iterator_t] = []
        let registrations: [(String, IOServiceMatchingCallback)] = [
            (kIOFirstMatchNotification, Self.attachedCallback),
            (kIOTerminatedNotification, Self.detachedCallback),
        ]
        for (type, callback) in registrations {
            var iterator: io_iterator_t = 0
            // 매칭 사전은 호출마다 소비되므로 그때마다 새로 만든다
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, callbacks.toOpaque(), &iterator
            )
            guard result == KERN_SUCCESS else {
                IONotificationPortDestroy(port)
                iterators.forEach { IOObjectRelease($0) }
                callbacks.release()
                state.withLock { $0.phase = .stopped }
                return false
            }
            // 비워야 알림이 무장된다. 여기서 나오는 것은 지금 연결된 장치라 알리지 않는다
            _ = Self.drain(iterator)
            iterators.append(iterator)
        }
        // 잠금 클로저는 @Sendable이라 포인터 대신 비트와 복사본을 넘긴다
        let portBits = UInt(bitPattern: port)
        let callbackBits = UInt(bitPattern: callbacks.toOpaque())
        let registered = iterators
        state.withLock { state in
            state.port = portBits
            state.callbacks = callbackBits
            state.iterators = registered
        }
        return true
    }

    /// 포트 파괴 → 진행 중 콜백 대기 → 이터레이터 해제 → 상자 해제
    public func stop() {
        let snapshot: State? = state.withLock { state in
            guard state.phase == .started else { return nil }
            let copy = state
            state.phase = .stopped
            state.iterators = []
            return copy
        }
        guard let snapshot else { return }
        if let port = IONotificationPortRef(bitPattern: snapshot.port) {
            IONotificationPortDestroy(port)
        }
        queue.sync {}
        snapshot.iterators.forEach { IOObjectRelease($0) }
        if let pointer = UnsafeMutableRawPointer(bitPattern: snapshot.callbacks) {
            Unmanaged<Callbacks>.fromOpaque(pointer).release()
        }
    }

    private static let attachedCallback: IOServiceMatchingCallback = { refcon, iterator in
        deliver(refcon, iterator, .attached)
    }

    private static let detachedCallback: IOServiceMatchingCallback = { refcon, iterator in
        deliver(refcon, iterator, .detached)
    }

    // 이터레이터를 끝까지 비우고(다음 알림을 받으려면 꼭 필요) 장치가 하나라도 있었으면 handler를 한 번 부른다
    private static func deliver(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t, _ change: Change) {
        let count = drain(iterator)
        guard count > 0, let refcon else { return }
        Unmanaged<Callbacks>.fromOpaque(refcon).takeUnretainedValue().handler(change)
    }

    // 이터레이터의 서비스를 모두 꺼내 해제한다. 꺼낸 수를 돌려준다
    private static func drain(_ iterator: io_iterator_t) -> Int {
        var count = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            IOObjectRelease(service)
            count += 1
        }
        return count
    }
}
