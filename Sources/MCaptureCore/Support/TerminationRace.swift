import Foundation

/// 취소를 무시하는 저장도 종료 응답을 붙잡지 않는 비구조적 경주.
@MainActor
public final class TerminationRace {
    private var started = false
    private var replied = false
    private var saveTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    public init() {}

    public func start(timeout: Duration, save: @escaping @MainActor () async -> Void,
                      reply: @escaping @MainActor () -> Void) {
        guard !started else { return }
        started = true
        saveTask = Task {
            await save()
            self.finish(reply)
        }
        timerTask = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            self.finish(reply)
        }
    }

    private func finish(_ reply: () -> Void) {
        guard !replied else { return }
        replied = true
        saveTask?.cancel()
        timerTask?.cancel()
        saveTask = nil
        timerTask = nil
        reply()
    }
}
