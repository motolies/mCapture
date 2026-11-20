import Foundation
import Testing
@testable import MCaptureCore

@Suite("SubtreeRescanQueue")
struct SubtreeRescanQueueTests {
    private let t0 = ContinuousClock.now

    // t0 기준 초 단위 시각
    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        t0 + .milliseconds(Int(seconds * 1000))
    }

    @Test func 같은_루트의_알림_여러_건은_작업_하나로_합친다() {
        var queue = SubtreeRescanQueue()
        for i in 0..<5 {
            let accepted = queue.note(path: "/h", root: "/h", receivedAt: at(Double(i) * 0.1))
            #expect(accepted)
        }
        let taken = queue.takeJobs()
        #expect(taken.jobs == [.init(path: "/h", root: "/h")])
        #expect(taken.notes == 5)
        #expect(queue.isEmpty)
    }

    @Test func 같은_루트_트리의_자손은_빠지고_중첩_루트는_따로_남는다() {
        var queue = SubtreeRescanQueue()
        _ = queue.note(path: "/h/a/b", root: "/h", receivedAt: at(0))
        _ = queue.note(path: "/h", root: "/h", receivedAt: at(0.1))
        _ = queue.note(path: "/h/a", root: "/h", receivedAt: at(0.2))
        _ = queue.note(path: "/h/.nested", root: "/h/.nested", receivedAt: at(0.3))
        #expect(queue.takeJobs().jobs == [.init(path: "/h", root: "/h"), .init(path: "/h/.nested", root: "/h/.nested")])
    }

    @Test func 대기_중인_경로_아래는_개별_반영이_필요_없다() {
        var queue = SubtreeRescanQueue()
        _ = queue.note(path: "/h/a", root: "/h", receivedAt: at(0))
        #expect(queue.isPending(path: "/h/a/x", root: "/h"))
        #expect(queue.isPending(path: "/h/a", root: "/h"))
        #expect(!queue.isPending(path: "/h/ab", root: "/h"))
        #expect(!queue.isPending(path: "/h/a/x", root: "/h/a"))
    }

    @Test func 마감은_조용한_시간과_최대_지연_중_이른_쪽이다() {
        var queue = SubtreeRescanQueue()
        #expect(queue.deadline(quiet: .seconds(3), maxDelay: .seconds(30)) == nil)
        _ = queue.note(path: "/h", root: "/h", receivedAt: at(0))
        _ = queue.note(path: "/h", root: "/h", receivedAt: at(2))
        #expect(queue.deadline(quiet: .seconds(3), maxDelay: .seconds(30)) == at(5))
        _ = queue.note(path: "/h", root: "/h", receivedAt: at(29))
        #expect(queue.deadline(quiet: .seconds(3), maxDelay: .seconds(30)) == at(30))
    }

    @Test func 재스캔_시작_전에_받은_알림은_반영된_것으로_본다() {
        var queue = SubtreeRescanQueue()
        _ = queue.note(path: "/h", root: "/h", receivedAt: at(0))
        let job = queue.takeJobs().jobs[0]
        queue.complete(job, startedAt: at(5))
        // 스캔 전에 받았지만 처리가 늦은 알림·변경은 무시
        let late = queue.note(path: "/h", root: "/h", receivedAt: at(4))
        #expect(!late)
        #expect(queue.isCovered(path: "/h/a/b", root: "/h", receivedAt: at(4.9)))
        #expect(queue.isEmpty)
        // 스캔을 시작한 뒤에 받은 것은 다시 필요
        #expect(!queue.isCovered(path: "/h/a", root: "/h", receivedAt: at(5)))
        let fresh = queue.note(path: "/h", root: "/h", receivedAt: at(6))
        #expect(fresh)
        #expect(queue.count == 1)
    }

    @Test func 루트가_다르면_덮지_않고_슬래시_루트도_처리한다() {
        var queue = SubtreeRescanQueue()
        queue.complete(.init(path: "/h", root: "/h"), startedAt: at(5))
        #expect(!queue.isCovered(path: "/h/.nested/x", root: "/h/.nested", receivedAt: at(1)))
        queue.complete(.init(path: "/", root: "/"), startedAt: at(5))
        #expect(queue.isCovered(path: "/Applications/X.app", root: "/", receivedAt: at(1)))
        #expect(SubtreeRescanQueue.contains("/", "/a"))
        #expect(!SubtreeRescanQueue.contains("/a", "/ab"))
    }
}
