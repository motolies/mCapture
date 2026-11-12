import Foundation
import Testing
@testable import MCaptureCore

@Suite("DisplayAutoRecoveryPolicy")
struct DisplayAutoRecoveryPolicyTests {
    @Test func 인식_실패한_연결은_한_번만_시도한다() {
        var policy = DisplayAutoRecoveryPolicy()
        #expect(policy.evaluate(unrecognized: [7], now: 0) == .init(attempts: [7], limited: false))
        // 복구가 화면 구성을 바꿔 다시 확인해도 같은 연결은 건너뛴다
        #expect(policy.evaluate(unrecognized: [7], now: 1) == .init(attempts: [], limited: false))
        #expect(policy.evaluate(unrecognized: [7], now: 1000) == .init(attempts: [], limited: false))
    }

    @Test func 인식_실패한_연결이_없으면_아무것도_하지_않는다() {
        var policy = DisplayAutoRecoveryPolicy()
        #expect(policy.evaluate(unrecognized: [], now: 0) == .init(attempts: [], limited: false))
    }

    @Test func 여러_연결이_함께_실패하면_번호_순으로_모두_시도한다() {
        var policy = DisplayAutoRecoveryPolicy()
        #expect(policy.evaluate(unrecognized: [9, 4], now: 0) == .init(attempts: [4, 9], limited: false))
    }

    @Test func 정상_인식됐다가_다시_실패하면_다시_시도한다() {
        var policy = DisplayAutoRecoveryPolicy()
        #expect(policy.evaluate(unrecognized: [7], now: 0).attempts == [7])
        // 복구돼 인식 실패 목록에서 빠졌다가 (잠자기에서 깨어난 뒤 등) 다시 실패
        #expect(policy.evaluate(unrecognized: [], now: 5).attempts == [])
        #expect(policy.evaluate(unrecognized: [7], now: 60).attempts == [7])
    }

    @Test func 케이블을_다시_꽂아_새_연결이_되면_다시_시도한다() {
        var policy = DisplayAutoRecoveryPolicy()
        #expect(policy.evaluate(unrecognized: [7], now: 0).attempts == [7])
        #expect(policy.evaluate(unrecognized: [], now: 10).attempts == [])
        #expect(policy.evaluate(unrecognized: [8], now: 20).attempts == [8])
    }

    @Test func 연결이_계속_새로_생겨도_정해진_횟수까지만_시도한다() {
        var policy = DisplayAutoRecoveryPolicy(maxAttempts: 3, window: 300)
        // 복구할 때마다 연결 번호가 바뀌고 계속 인식 실패로 남는 경우
        #expect(policy.evaluate(unrecognized: [1], now: 0) == .init(attempts: [1], limited: false))
        #expect(policy.evaluate(unrecognized: [2], now: 3) == .init(attempts: [2], limited: false))
        #expect(policy.evaluate(unrecognized: [3], now: 6) == .init(attempts: [3], limited: false))
        #expect(policy.evaluate(unrecognized: [4], now: 9) == .init(attempts: [], limited: true))
        #expect(policy.evaluate(unrecognized: [5], now: 299) == .init(attempts: [], limited: true))
    }

    @Test func 시간이_지나면_다시_시도할_수_있다() {
        var policy = DisplayAutoRecoveryPolicy(maxAttempts: 2, window: 100)
        #expect(policy.evaluate(unrecognized: [1], now: 0).attempts == [1])
        #expect(policy.evaluate(unrecognized: [2], now: 10).attempts == [2])
        #expect(policy.evaluate(unrecognized: [3], now: 20) == .init(attempts: [], limited: true))
        // 첫 시도가 100초를 넘겨 빠지면 한 자리가 난다
        #expect(policy.evaluate(unrecognized: [3], now: 100) == .init(attempts: [3], limited: false))
    }

    @Test func 한_번에_제한을_넘는_수가_실패하면_일부만_시도하고_알린다() {
        var policy = DisplayAutoRecoveryPolicy(maxAttempts: 2, window: 100)
        #expect(policy.evaluate(unrecognized: [1, 2, 3], now: 0) == .init(attempts: [1, 2], limited: true))
    }

    @Test func 직접_복구한_연결은_자동으로_다시_시도하지_않고_횟수에도_넣지_않는다() {
        var policy = DisplayAutoRecoveryPolicy(maxAttempts: 1, window: 100)
        policy.markAttempted(7)
        #expect(policy.evaluate(unrecognized: [7], now: 0) == .init(attempts: [], limited: false))
        // 직접 복구는 횟수 제한을 쓰지 않았으므로 다른 연결은 자동으로 시도한다
        #expect(policy.evaluate(unrecognized: [7, 8], now: 1) == .init(attempts: [8], limited: false))
    }
}
