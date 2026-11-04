import Foundation
import Testing
import MCaptureCore
@testable import mCapture

private actor WriteGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func pauseFirst() async {
        calls += 1
        if calls == 1 { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@Suite struct FileIndexerPersistenceTests {
    private func fixture() throws -> (URL, URL, FileIndexer.Configuration) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("old.txt"))
        return (folder, folder.appendingPathComponent("cache"), .init(roots: [root.path], rules: ExclusionRules(text: "", home: folder.path, includeHidden: true)))
    }

    @Test func disableDuringSaveDoesNotRecreateCache() async throws {
        let (folder, url, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = WriteGate()
        let indexer = FileIndexer(snapshotURL: url, beforeSnapshotWrite: { await gate.pauseFirst() })
        let start = Task { await indexer.start(config) }
        while await gate.calls == 0 { await Task.yield() }
        await indexer.stop(deleteSnapshot: true)
        await gate.release()
        await start.value
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["root"])
    }

    @Test(arguments: [false, true]) func latestChangesSurvivePendingSave(rebuild: Bool) async throws {
        let (folder, url, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = WriteGate()
        let indexer = FileIndexer(snapshotURL: url, beforeSnapshotWrite: { await gate.pauseFirst() })
        let start = Task { await indexer.start(config) }
        while await gate.calls == 0 { await Task.yield() }
        let added = URL(fileURLWithPath: config.roots[0]).appendingPathComponent("new.txt")
        try Data().write(to: added)
        let update = Task {
            if rebuild { await indexer.rebuild() }
            else { await indexer.refresh(directory: config.roots[0]) }
        }
        while await indexer.snapshot().lookup(path: added.path) == nil { await Task.yield() }
        let quit = Task { await indexer.saveIfNeeded() }
        await gate.release()
        await start.value
        await update.value
        await quit.value
        let snapshot = try #require(FileIndexSnapshot.decode(Data(contentsOf: url), expectedConfigHash: config.hash))
        #expect(snapshot.index.lookup(path: added.path) != nil)
        #expect(await gate.calls == 2)
        await indexer.stop(deleteSnapshot: false)
    }
}
