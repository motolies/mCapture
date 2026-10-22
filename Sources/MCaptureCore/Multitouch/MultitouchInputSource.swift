import Foundation
import os

/// 비공개 MultitouchSupport 장치를 `InputSource`로 감싼다: 프레임 → `GesturePipeline` → `GestureEvent`.
/// 한 번 멈추면 스트림이 끝나므로 다시 쓰려면 새로 만든다 (블루투스 재연결 때 앱이 그렇게 한다).
/// `stop()`은 콜백 안(프레임워크 스레드)에서 부르면 안 된다
public final class MultitouchInputSource: InputSource {
    /// 장치별 상태 (진단용). MTDeviceIsAlive는 실측으로 늘 false라 판단 근거로 쓸 수 없다
    public struct DeviceStatus: Sendable, Equatable {
        public var running: Bool
        public var alive: Bool
    }

    private struct Member: Sendable {
        let device: MultitouchDevice
        let profile: TouchGestureRecognizer.Profile
    }

    private enum Phase: Sendable {
        case idle, started, stopped
    }

    public let devices: [InputDeviceDescriptor]
    public let events: AsyncStream<GestureEvent>

    private let api: MultitouchAPI
    private let members: [Member]
    private let pipeline: GesturePipeline
    private let continuation: AsyncStream<GestureEvent>.Continuation
    private let useButtonCallback: Bool
    private let phase = OSAllocatedUnfairLock(initialState: Phase.idle)

    /// profile이 nil을 주는 장치는 건너뛴다 (아직 다루지 않는 종류). observer는 CLI 진단용 동기 훅이고, 이벤트는 그와 별개로 `events`에도 흐른다.
    /// useButtonCallback을 끄면 물리 클릭은 `buttonChanged(_:down:)`로 넣어 준 것만 센다
    public init(
        api: MultitouchAPI,
        devices: [MultitouchDevice],
        profile: @Sendable (InputDeviceDescriptor) -> TouchGestureRecognizer.Profile? = { .default(for: $0.kind, surface: $0.surface) },
        observer: GesturePipeline.Observer = GesturePipeline.Observer(),
        useButtonCallback: Bool = true
    ) {
        self.api = api
        members = devices.compactMap { device in profile(device.descriptor).map { Member(device: device, profile: $0) } }
        self.devices = members.map(\.device.descriptor)
        self.useButtonCallback = useButtonCallback
        let (stream, continuation) = AsyncStream.makeStream(of: GestureEvent.self, bufferingPolicy: .bufferingNewest(16))
        events = stream
        self.continuation = continuation
        var wrapped = observer
        let userEvent = observer.event
        wrapped.event = { event, sessionTime in
            userEvent?(event, sessionTime)
            continuation.yield(event)
        }
        pipeline = GesturePipeline(observer: wrapped)
    }

    deinit {
        stop()
    }

    /// 지금까지 받은 프레임 수
    public var frameCount: Int { pipeline.frameCount }

    /// 장치의 실행 상태. 모르는 id면 nil
    public func status(of id: UInt64) -> DeviceStatus? {
        members.first { $0.device.descriptor.id == id }.map {
            DeviceStatus(running: api.isRunning($0.device.ref), alive: api.isAlive($0.device.ref))
        }
    }

    /// 장치마다 인식기를 만들고 콜백을 건 뒤 MTDeviceStart. 한 장치라도 시작에 실패하면 전부 멈추고 던진다
    public func start() throws {
        let proceed = phase.withLock { phase -> Bool in
            guard phase == .idle else { return false }
            phase = .started
            return true
        }
        guard proceed else { return }
        for member in members {
            let id = member.device.descriptor.id
            let pipeline = self.pipeline
            pipeline.addDevice(member.device.descriptor, recognizer: TouchGestureRecognizer(profile: member.profile))
            MultitouchCallbackRouter.register(
                device: member.device.handle,
                frame: { frame in pipeline.ingest(frame, from: id) },
                button: { state, previous in
                    let code = state != 0 ? state : previous
                    let button: MouseButton = code == 1 ? .left : code == 2 ? .right : .other(Int(code))
                    pipeline.buttonChanged(button, down: state != 0 && previous == 0, device: id)
                }
            )
            _ = api.registerCallback(member.device.ref, MultitouchCallbackRouter.frameCallback)
            if useButtonCallback {
                _ = api.registerButtonCallback(member.device.ref, MultitouchCallbackRouter.buttonCallback)
            }
            let status = api.start(member.device.ref, 0)
            if status != 0 {
                stop()
                throw MultitouchError.deviceStartFailed(id, status)
            }
        }
    }

    /// 콜백 해제 → MTDeviceStop → 라우터 정리 → 큐 배수 → 스트림 종료 (FileEventWatcher.stop과 같은 순서)
    public func stop() {
        let proceed = phase.withLock { phase -> Bool in
            guard phase == .started else { return false }
            phase = .stopped
            return true
        }
        guard proceed else { return }
        for member in members {
            _ = api.unregisterCallback(member.device.ref, MultitouchCallbackRouter.frameCallback)
            if useButtonCallback {
                _ = api.unregisterButtonCallback(member.device.ref, MultitouchCallbackRouter.buttonCallback)
            }
            _ = api.stop(member.device.ref)
            MultitouchCallbackRouter.unregister(device: member.device.handle)
        }
        pipeline.drain()
        continuation.finish()
    }

    /// 장치를 모르는 물리 버튼 (CGEventTap 보조 경로, CLI 전용). 최근에 프레임을 보낸 장치로 간다
    public func buttonChanged(_ button: MouseButton, down: Bool) {
        pipeline.buttonChanged(button, down: down)
    }
}
