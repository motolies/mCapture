import Foundation

/// 문서 사본(자동 저장·에디터·핀)이 공유하는 FIFO와 마지막 성공 경로.
@MainActor
public final class DocumentExportSession {
    private let initialURL: URL?
    private var lastSavedURL: URL?
    public var savedURL: URL? { lastSavedURL ?? initialURL }
    private var tail: Task<Void, Never>?
    private var sequence = 0

    public nonisolated init(savedURL: URL? = nil) { initialURL = savedURL }

    /// 호출 시 동기적으로 순서를 예약한다. 실패(nil)는 저장 경로를 바꾸지 않는다.
    @discardableResult
    public func enqueue(target: URL? = nil, operation: @escaping @MainActor (URL?) async -> URL?) -> Task<Void, Never> {
        let previous = tail
        sequence += 1
        let current = sequence
        let task = Task {
            await previous?.value
            if let url = await operation(target ?? self.savedURL) { self.lastSavedURL = url }
            if current == self.sequence { self.tail = nil }
        }
        tail = task
        return task
    }
}
