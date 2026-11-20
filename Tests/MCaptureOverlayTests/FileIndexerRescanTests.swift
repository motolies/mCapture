import CoreServices
import Foundation
import Testing
import MCaptureCore
@testable import mCapture

/// FSEvents 유실 알림(MustScanSubDirs)을 모아 한 번만 다시 스캔하는지 본다
/// 실제 FSEvents로는 유실을 만들 수 없어 `enqueueForTesting`으로 가짜 묶음을 넣는다
@Suite struct FileIndexerRescanTests {
    private static let dropFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped)
    /// 시험용 이벤트 ID. 실제 FSEvents ID보다 충분히 커서 섞이지 않는다
    private static let syntheticId = FSEventsGetCurrentEventId() + 1_000_000_000

    // 임시 루트 하나로 인덱서를 시작한다 (전체 스캔 후 감시 중)
    private func startedIndexer(_ timing: FileIndexer.RescanTiming) async throws -> (FileIndexer, URL, FileIndexer.Configuration) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("old.txt"))
        let config = FileIndexer.Configuration(roots: [root.path], rules: ExclusionRules(text: "", home: folder.path, includeHidden: true))
        let indexer = FileIndexer(snapshotURL: folder.appendingPathComponent("cache"), timing: timing)
        await indexer.start(config)
        return (indexer, folder, config)
    }

    // 루트 전체에 대한 유실 알림 하나
    private func drop(_ path: String, id: UInt64 = syntheticId) -> FileEvent {
        FileEvent(path: path, flags: Self.dropFlags, id: id)
    }

    // 조건이 참이 될 때까지 짧게 기다린다 (제한 시간을 넘기면 false)
    private func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test func 연달아_온_유실_알림은_재스캔_한_번으로_합친다() async throws {
        let (indexer, folder, config) = try await startedIndexer(.init(quiet: .milliseconds(200), maxDelay: .seconds(5), qos: .utility))
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = config.roots[0]
        // 재스캔이 실제로 디스크를 다시 읽는지: 알림 전에 만든 파일이 재스캔 뒤 보여야 한다
        let added = URL(fileURLWithPath: root).appendingPathComponent("sub/new.txt")
        try Data().write(to: added)
        for _ in 0..<5 {
            await indexer.enqueueForTesting([drop(root), drop(root + "/sub")])
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await waitUntil { await indexer.stats().subtreeRescans == 1 })
        try await Task.sleep(for: .milliseconds(500))
        let stats = await indexer.stats()
        #expect(stats.subtreeRescans == 1)
        #expect(stats.pendingRescans == 0)
        #expect(await indexer.snapshot().lookup(path: added.path) != nil)
        await indexer.stop(deleteSnapshot: true)
    }

    @Test func 재스캔_시작_전에_받은_알림은_다시_스캔하지_않는다() async throws {
        let (indexer, folder, config) = try await startedIndexer(.init(quiet: .milliseconds(100), maxDelay: .seconds(5), qos: .utility))
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = config.roots[0]
        let early = ContinuousClock.now
        await indexer.enqueueForTesting([drop(root)], receivedAt: early)
        #expect(await waitUntil { await indexer.stats().subtreeRescans == 1 })
        // 첫 재스캔보다 먼저 받았지만 늦게 처리된 알림 (폭주 중 밀려 있던 묶음)
        await indexer.enqueueForTesting([drop(root)], receivedAt: early)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await indexer.stats().subtreeRescans == 1)
        #expect(await indexer.stats().pendingRescans == 0)
        // 재스캔 뒤에 받은 알림은 다시 필요하다
        await indexer.enqueueForTesting([drop(root)])
        #expect(await waitUntil { await indexer.stats().subtreeRescans == 2 })
        await indexer.stop(deleteSnapshot: true)
    }

    @Test func 알림이_계속_와도_최대_지연이_지나면_재스캔한다() async throws {
        let (indexer, folder, config) = try await startedIndexer(.init(quiet: .seconds(10), maxDelay: .milliseconds(300), qos: .utility))
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = config.roots[0]
        let began = ContinuousClock.now
        let feeding = Task {
            while ContinuousClock.now - began < .seconds(2) {
                await indexer.enqueueForTesting([drop(root)])
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #expect(await waitUntil(.seconds(1.5)) { await indexer.stats().subtreeRescans >= 1 })
        feeding.cancel()
        await indexer.stop(deleteSnapshot: true)
    }

    @Test func 재스캔을_기다리는_동안_저장하는_이벤트_ID는_묶인다() async throws {
        let (indexer, folder, config) = try await startedIndexer(.init(quiet: .seconds(1), maxDelay: .seconds(30), qos: .utility))
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = config.roots[0]
        let cache = folder.appendingPathComponent("cache")
        let before = await indexer.stats().lastEventId
        // 유실 알림과 더 뒤의 일반 이벤트가 함께 온 묶음
        let modified = FileEvent(path: root + "/old.txt",
                                 flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile),
                                 id: Self.syntheticId + 10)
        await indexer.enqueueForTesting([drop(root), modified])
        #expect(await waitUntil { await indexer.stats().pendingRescans == 1 })
        let pending = await indexer.stats()
        #expect(pending.lastEventId == Self.syntheticId + 10)
        #expect(pending.persistedEventId == before)
        // 대기 중에 저장해도 묶인 ID로 저장된다 (refresh로 저장할 변경을 만든다)
        try Data().write(to: URL(fileURLWithPath: root).appendingPathComponent("saved.txt"))
        await indexer.refresh(directory: root)
        await indexer.saveIfNeeded()
        let frozen = try #require(FileIndexSnapshot.decode(Data(contentsOf: cache), expectedConfigHash: config.hash))
        #expect(frozen.lastEventId == before)
        // 재스캔이 끝나면 처리한 ID까지 저장한다
        #expect(await waitUntil { await indexer.stats().subtreeRescans == 1 })
        await indexer.saveIfNeeded()
        let released = try #require(FileIndexSnapshot.decode(Data(contentsOf: cache), expectedConfigHash: config.hash))
        #expect(released.lastEventId == Self.syntheticId + 10)
        await indexer.stop(deleteSnapshot: true)
    }

    @Test func 세대가_바뀌면_기다리던_재스캔은_버린다() async throws {
        let (indexer, folder, config) = try await startedIndexer(.init(quiet: .milliseconds(300), maxDelay: .seconds(5), qos: .utility))
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = config.roots[0]
        await indexer.enqueueForTesting([drop(root)])
        #expect(await waitUntil { await indexer.stats().pendingRescans == 1 })
        await indexer.rebuild()
        try await Task.sleep(for: .milliseconds(700))
        let stats = await indexer.stats()
        #expect(stats.pendingRescans == 0)
        #expect(stats.subtreeRescans == 0)
        #expect(stats.persistedEventId == stats.lastEventId)
        await indexer.stop(deleteSnapshot: true)
    }
}
