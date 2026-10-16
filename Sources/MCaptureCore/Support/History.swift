/// 스냅샷 방식 실행 취소 스택
public struct History<State: Equatable & Sendable>: Sendable {
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private let limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// 변경 직전 상태를 기록한다. 새 변경이 생기면 다시 실행 기록은 버린다
    public mutating func record(_ previous: State) {
        if undoStack.last == previous { return }
        undoStack.append(previous)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    /// 현재 상태를 다시 실행 스택에 넣고 이전 상태를 돌려준다
    public mutating func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// 현재 상태를 실행 취소 스택에 넣고 다음 상태를 돌려준다
    public mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
