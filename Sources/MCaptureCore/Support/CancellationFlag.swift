import Synchronization

/// 다른 스레드에서 도는 긴 작업(스캔·크기 계산·휴지통 이동)이 읽는 취소 표시
public final class CancellationFlag: Sendable {
    private let flag = Atomic<Bool>(false)

    public init() {}

    public var isCancelled: Bool { flag.load(ordering: .relaxed) }

    public func cancel() {
        flag.store(true, ordering: .relaxed)
    }
}
