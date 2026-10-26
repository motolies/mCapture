import Foundation
import Synchronization
import Testing
@testable import MCaptureCore

/// 메모리 안의 가짜 파일 시스템. 실제 휴지통을 쓰지 않고 실행기를 검증한다
private final class FakeRemover: FileRemoving, @unchecked Sendable {
    private let lock = Mutex<Void>(())
    var files: [String: FileIdentity] = [:]
    var cloud: Set<String> = []
    var trashErrors: [String: Error] = [:]
    var trashBin: [String: FileIdentity] = [:]
    private(set) var trashOrder: [String] = []

    func identity(of path: String) -> FileIdentity? { lock.withLock { _ in files[path] } }
    func isUbiquitous(_ path: String) -> Bool { cloud.contains(path) }
    func exists(_ path: String) -> Bool { lock.withLock { _ in files[path] != nil || trashBin[path] != nil } }

    func trash(_ path: String) throws -> String {
        if let error = trashErrors[path] { throw error }
        return lock.withLock { _ in
            let trashed = "/.Trash/" + (path as NSString).lastPathComponent
            trashBin[trashed] = files.removeValue(forKey: path)
            trashOrder.append(path)
            return trashed
        }
    }

    func move(_ source: String, to destination: String) throws {
        lock.withLock { _ in
            files[destination] = trashBin.removeValue(forKey: source)
        }
    }
}

private func identity(_ inode: UInt64, directory: Bool = false) -> FileIdentity {
    FileIdentity(device: 1, inode: inode, isDirectory: directory)
}

private func entry(_ path: String, _ inode: UInt64, contained: Int = 0) -> DeletionPlan.Entry {
    DeletionPlan.Entry(path: path, isDirectory: contained > 0, identity: identity(inode, directory: contained > 0),
                       contained: contained, hasUnindexed: false)
}

@Suite("DeletionPlan")
struct DeletionPlanTests {
    let guardian = DeletionGuard(home: "/Users/tester", roots: ["/Users/tester"], appPath: nil)

    private func selection(_ items: [(String, Bool)]) -> PathSelection {
        var selection = PathSelection()
        for (path, directory) in items { selection.insert(.init(path: path, isDirectory: directory)) }
        return selection
    }

    @Test func 조상만_남기고_막힘_없음_잠김_클라우드를_뺀다() {
        let selection = selection([
            ("/Users/tester/dl/old", true), ("/Users/tester/dl/old/a.txt", false),
            ("/Users/tester/Documents", true), ("/Users/tester/dl/gone.zip", false),
            ("/Users/tester/dl/locked.pdf", false), ("/Users/tester/dl/synced.md", false), ("/Users/tester/dl/x.log", false),
        ])
        var inode: UInt64 = 0
        let plan = DeletionPlan.make(selection: selection, guardian: guardian, probe: { path in
            inode += 1
            switch (path as NSString).lastPathComponent {
            case "gone.zip": return .missing
            case "locked.pdf": return FileProbe(identity: identity(inode), isLocked: true)
            case "synced.md": return FileProbe(identity: identity(inode), isUbiquitous: true)
            case "old": return FileProbe(identity: identity(inode, directory: true))
            default: return FileProbe(identity: identity(inode))
            }
        }, stats: { _ in FileIndex.SubtreeStats(files: 3, directories: 1) }, fromAllMatches: false)
        #expect(plan.entries.map(\.path) == ["/Users/tester/dl/old", "/Users/tester/dl/x.log"])
        #expect(plan.entries.first?.contained == 4)
        #expect(plan.excluded.map(\.reason) == [.blocked(.standardFolder), .missing, .locked, .cloud])
        #expect(plan.coveredCount == 1)
        #expect(plan.fileCount == 1)
        #expect(plan.folderCount == 1)
        #expect(!plan.requiresCountConfirmation)
    }

    @Test func 개수_입력_확인_기준() {
        let probe: (String) -> FileProbe = { _ in FileProbe(identity: identity(1)) }
        let noStats: (String) -> FileIndex.SubtreeStats? = { _ in nil }
        let make = { (count: Int) in
            DeletionPlan.make(selection: selection((0..<count).map { ("/Users/tester/dl/f\($0)", false) }),
                              guardian: guardian, probe: probe, stats: noStats, fromAllMatches: false)
        }
        #expect(!make(99).requiresCountConfirmation)
        #expect(make(100).requiresCountConfirmation)
        let folderProbe: (String) -> FileProbe = { _ in FileProbe(identity: identity(1, directory: true)) }
        let contained = { (n: Int) in
            DeletionPlan.make(selection: selection([("/Users/tester/dl/big", true)]), guardian: guardian, probe: folderProbe,
                              stats: { _ in FileIndex.SubtreeStats(files: n) }, fromAllMatches: false)
        }
        #expect(!contained(9_999).requiresCountConfirmation)
        #expect(contained(10_000).requiresCountConfirmation)
        let all = DeletionPlan.make(selection: selection([("/Users/tester/dl/a", false)]), guardian: guardian, probe: probe,
                                    stats: noStats, fromAllMatches: true)
        #expect(all.requiresCountConfirmation)
    }

    @Test func 옮길_항목이_없으면_확인도_없다() {
        let plan = DeletionPlan.make(selection: selection([("/Users/tester/Documents", true)]), guardian: guardian,
                                     probe: { _ in FileProbe(identity: identity(1)) }, stats: { _ in nil }, fromAllMatches: true)
        #expect(plan.entries.isEmpty)
        #expect(!plan.requiresCountConfirmation)
    }

    @Test func 미리보기는_안의_항목이_많은_순() {
        let plan = DeletionPlan(entries: [entry("/a/x", 1), entry("/a/big", 2, contained: 500), entry("/b/mid", 3, contained: 20)],
                                excluded: [], coveredCount: 0, requiresCountConfirmation: false)
        #expect(plan.preview.map(\.path) == ["/a/big", "/b/mid", "/a/x"])
        #expect(plan.containedTotal == 520)
        #expect(plan.topLocations() == [.init(folder: "/a", count: 502), .init(folder: "/b", count: 21)])
    }
}

@Suite("DeletionExecutor")
struct DeletionExecutorTests {
    @Test func 순서대로_옮기고_되돌린다() {
        let remover = FakeRemover()
        remover.files = ["/d/a": identity(1), "/d/b": identity(2)]
        var steps: [Int] = []
        let report = DeletionExecutor.run([entry("/d/a", 1), entry("/d/b", 2)], remover: remover, progress: { done, _ in steps.append(done) })
        #expect(report.trashedPaths == ["/d/a", "/d/b"])
        #expect(remover.trashOrder == ["/d/a", "/d/b"])
        #expect(steps == [1, 2])
        let restored = DeletionExecutor.restore(report.trashed, remover: remover)
        #expect(restored.restored == ["/d/a", "/d/b"])
        #expect(remover.files["/d/a"] == identity(1))
    }

    @Test func 사라졌거나_바뀐_항목과_클라우드_항목은_건너뛴다() {
        let remover = FakeRemover()
        remover.files = ["/d/changed": identity(99), "/d/cloud": identity(3)]
        remover.cloud = ["/d/cloud"]
        let report = DeletionExecutor.run([entry("/d/gone", 1), entry("/d/changed", 2), entry("/d/cloud", 3)], remover: remover)
        #expect(report.trashed.isEmpty)
        #expect(report.skipped.map(\.reason) == [.missing, .changed, .cloud])
        #expect(remover.files["/d/changed"] != nil)
    }

    @Test func 일부가_실패해도_나머지를_옮긴다() {
        let remover = FakeRemover()
        remover.files = ["/d/a": identity(1), "/d/b": identity(2), "/d/c": identity(3)]
        remover.trashErrors["/d/b"] = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let report = DeletionExecutor.run([entry("/d/a", 1), entry("/d/b", 2), entry("/d/c", 3)], remover: remover)
        #expect(report.trashedPaths == ["/d/a", "/d/c"])
        #expect(report.failed == [.init(path: "/d/b", failure: .permissionDenied)])
    }

    @Test func 중간에_취소하면_남은_항목은_그대로() {
        let remover = FakeRemover()
        remover.files = ["/d/a": identity(1), "/d/b": identity(2), "/d/c": identity(3)]
        var done = 0
        let report = DeletionExecutor.run([entry("/d/a", 1), entry("/d/b", 2), entry("/d/c", 3)], remover: remover,
                                          isCancelled: { done >= 1 }, progress: { finished, _ in done = finished })
        #expect(report.trashedPaths == ["/d/a"])
        #expect(report.cancelledRemaining == 2)
        #expect(remover.files["/d/b"] != nil)
    }

    @Test func 되돌릴_자리에_같은_이름이_있으면_휴지통에_남긴다() {
        let remover = FakeRemover()
        remover.files = ["/d/a": identity(1)]
        let report = DeletionExecutor.run([entry("/d/a", 1)], remover: remover)
        remover.files["/d/a"] = identity(7)
        let restored = DeletionExecutor.restore(report.trashed, remover: remover)
        #expect(restored.conflicts == ["/d/a"])
        #expect(restored.restored.isEmpty)
        #expect(remover.files["/d/a"] == identity(7))
    }

    @Test func 오류를_이유로_나눈다() {
        let cocoa = { (code: Int) in DeletionFailure(error: NSError(domain: NSCocoaErrorDomain, code: code)) }
        #expect(cocoa(NSFileWriteNoPermissionError) == .permissionDenied)
        #expect(cocoa(NSFileWriteVolumeReadOnlyError) == .readOnly)
        #expect(cocoa(NSFileNoSuchFileError) == .notFound)
        #expect(cocoa(NSFeatureUnsupportedError) == .noTrash)
        let posix = { (code: Int32) in DeletionFailure(error: NSError(domain: NSPOSIXErrorDomain, code: Int(code))) }
        #expect(posix(EPERM) == .permissionDenied)
        #expect(posix(EBUSY) == .inUse)
        #expect(posix(EROFS) == .readOnly)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        #expect(DeletionFailure(error: wrapped) == .permissionDenied)
        if case .other = DeletionFailure(error: NSError(domain: "x", code: 1)) {} else { Issue.record("모르는 오류는 other") }
    }
}

@Suite("FileSizeCalculator")
struct FileSizeCalculatorTests {
    // 임시 폴더에 크기가 다른 파일을 만든다
    private func makeTree() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcapture-size-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root + "/sub/.hidden", withIntermediateDirectories: true)
        for (path, size) in [("a.bin", 10_000), ("sub/b.bin", 50_000), ("sub/.hidden/c.bin", 5_000)] {
            FileManager.default.createFile(atPath: root + "/" + path, contents: Data(repeating: 1, count: size))
        }
        return root
    }

    @Test func 폴더_안까지_더한다() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let result = FileSizeCalculator.size(of: [root])
        #expect(result.isComplete)
        #expect(result.bytes >= 65_000)
        let file = FileSizeCalculator.size(of: [root + "/a.bin"])
        #expect(file.bytes >= 10_000 && file.bytes < 65_000)
    }

    @Test func 예산을_넘으면_다_세지_못했다고_알린다() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(!FileSizeCalculator.size(of: [root], itemBudget: 1).isComplete)
        #expect(!FileSizeCalculator.size(of: [root], isCancelled: { true }).isComplete)
    }
}

@Suite("SubtreeStats")
struct SubtreeStatsTests {
    @Test func 하위_트리를_세고_삭제된_항목은_뺀다() {
        var index = FileIndex()
        let root = index.appendRoot(path: "/r")
        let proj = index.append(name: "proj", parent: root, flags: .directory)
        let src = index.append(name: "src", parent: proj, flags: .directory)
        index.append(name: "a.swift", parent: src, flags: [])
        let gone = index.append(name: "b.swift", parent: src, flags: [])
        index.append(name: "node_modules", parent: proj, flags: [.directory, .unindexed])
        index.append(name: "README.md", parent: proj, flags: [])
        index.removeSubtree(gone)
        #expect(index.subtreeStats(of: proj) == FileIndex.SubtreeStats(files: 2, directories: 2, unindexedDirectories: 1))
        #expect(index.subtreeStats(of: src).total == 1)
        let app = index.append(name: "Tool.app", parent: root, flags: [.directory, .package, .unindexed])
        #expect(index.subtreeStats(of: app) == FileIndex.SubtreeStats(unindexedDirectories: 1))
    }
}
