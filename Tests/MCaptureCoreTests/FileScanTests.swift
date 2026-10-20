import Foundation
import Testing
@testable import MCaptureCore

/// 테스트마다 새 임시 폴더를 만들고 끝나면 지운다
private final class TempTree {
    let root: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mcapture-scan-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit {
        // chmod 000으로 막은 폴더가 있어도 지울 수 있게 권한을 되돌린다
        if let enumerator = FileManager.default.enumerator(atPath: root) {
            for case let path as String in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/" + path)
            }
        }
        try? FileManager.default.removeItem(atPath: root)
    }

    /// 상대 경로에 파일을 만든다 (중간 폴더 포함)
    func file(_ relative: String) throws {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    /// 상대 경로에 폴더를 만든다
    func directory(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: root + "/" + relative, withIntermediateDirectories: true)
    }

    func path(_ relative: String) -> String { root + "/" + relative }
}

private func paths(_ index: FileIndex) -> Set<String> {
    Set((0..<UInt32(index.count)).filter { !index.isRemoved($0) }.map { index.path(of: $0) })
}

@Suite("FileTreeScanner")
struct FileTreeScannerTests {
    let noRules = ExclusionRules(text: "", home: "/nonexistent", includeHidden: false)

    @Test func 트리를_깊이_우선으로_색인한다() throws {
        let tree = try TempTree()
        try tree.file("a/b/c.txt")
        try tree.file("a/d.txt")
        try tree.file("e.txt")
        let (index, report) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        #expect(paths(index) == [tree.root, tree.path("a"), tree.path("a/b"), tree.path("a/b/c.txt"), tree.path("a/d.txt"), tree.path("e.txt")])
        #expect(report.entries == 5)
        #expect(report.directories == 2)
        #expect(index.flags(of: index.lookup(path: tree.path("a/b"))!).contains(.directory))
    }

    @Test func 앱_번들은_항목만_있고_내부는_없다() throws {
        let tree = try TempTree()
        try tree.file("Tool.app/Contents/Info.plist")
        let (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        let app = try #require(index.lookup(path: tree.path("Tool.app")))
        #expect(index.flags(of: app).isSuperset(of: [.directory, .package, .unindexed]))
        #expect(index.lookup(path: tree.path("Tool.app/Contents")) == nil)
    }

    @Test func 제외_폴더는_자체만_색인한다() throws {
        let tree = try TempTree()
        try tree.file("p/node_modules/x/index.js")
        try tree.file("p/cache/y.bin")
        try tree.file("p/src/main.js")
        let rules = ExclusionRules(text: "node_modules\n\(tree.path("p/cache"))", home: "/nonexistent", includeHidden: false)
        let (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        let modules = try #require(index.lookup(path: tree.path("p/node_modules")))
        #expect(index.flags(of: modules).contains(.unindexed))
        #expect(index.lookup(path: tree.path("p/node_modules/x")) == nil)
        #expect(index.lookup(path: tree.path("p/cache")) != nil)
        #expect(index.lookup(path: tree.path("p/cache/y.bin")) == nil)
        #expect(index.lookup(path: tree.path("p/src/main.js")) != nil)
    }

    @Test func 숨김을_끄면_점_이름과_그_안을_뺀다() throws {
        let tree = try TempTree()
        try tree.file(".config/app/settings.json")
        try tree.file(".zshrc")
        try tree.file("visible.txt")
        let (hidden, _) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        #expect(paths(hidden) == [tree.root, tree.path("visible.txt")])
        let shown = ExclusionRules(text: "", home: "/nonexistent", includeHidden: true)
        let (all, _) = FileTreeScanner.scan(roots: [tree.root], rules: shown)
        #expect(all.lookup(path: tree.path(".config/app/settings.json")) != nil)
        #expect(all.flags(of: all.lookup(path: tree.path(".zshrc"))!).contains(.hidden))
    }

    @Test func 심볼릭_링크는_따라가지_않는다() throws {
        let tree = try TempTree()
        try tree.file("real/file.txt")
        try FileManager.default.createSymbolicLink(atPath: tree.path("real/loop"), withDestinationPath: tree.root)
        let (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        let link = try #require(index.lookup(path: tree.path("real/loop")))
        #expect(index.flags(of: link).contains(.symlink))
        #expect(!index.flags(of: link).contains(.directory))
        #expect(index.count == 4)
    }

    @Test func 권한_없는_폴더는_항목만_남기고_기록한다() throws {
        let tree = try TempTree()
        try tree.file("locked/secret.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: tree.path("locked"))
        let (index, report) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        #expect(index.lookup(path: tree.path("locked")) != nil)
        #expect(index.lookup(path: tree.path("locked/secret.txt")) == nil)
        #expect(report.deniedPaths.contains { $0.hasSuffix("/locked") })
    }

    @Test func NFD_이름을_NFC로_색인한다() throws {
        let tree = try TempTree()
        try tree.file("보고서.txt".decomposedStringWithCanonicalMapping)
        let (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        let id = try #require(index.lookup(path: tree.path("보고서.txt")))
        // NFC "보고서.txt"는 7스칼라, NFD면 10스칼라
        #expect(index.name(of: id).unicodeScalars.count == 7)
    }

    @Test func 제외_폴더_안에_추가한_루트는_한_번만_색인한다() throws {
        let tree = try TempTree()
        try tree.file("Library/CloudStorage/OneDrive-회사/보고서.docx")
        try tree.file("Library/CloudStorage/OneDrive-개인/사진.jpg")
        let rules = ExclusionRules(text: tree.path("Library/CloudStorage"), home: "/nonexistent", includeHidden: false)
        let roots = rules.normalizedRoots([tree.root, tree.path("Library/CloudStorage/OneDrive-회사")], home: "/nonexistent")
        let (index, _) = FileTreeScanner.scan(roots: roots, rules: rules)
        let found = paths(index).filter { $0.hasSuffix("/보고서.docx") }
        #expect(found == [tree.path("Library/CloudStorage/OneDrive-회사/보고서.docx")])
        // 추가하지 않은 다른 공급자 폴더는 그대로 제외된다
        #expect(index.lookup(path: tree.path("Library/CloudStorage/OneDrive-개인/사진.jpg")) == nil)
    }

    @Test func 없는_루트는_건너뛴다() throws {
        let tree = try TempTree()
        try tree.file("a.txt")
        let (index, report) = FileTreeScanner.scan(roots: [tree.path("none"), tree.root], rules: noRules)
        #expect(report.missingRoots == [tree.path("none")])
        #expect(index.roots.count == 1)
    }

    /// MCAPTURE_PERF=1일 때만: 실제 홈·앱 폴더를 기본 제외 규칙으로 스캔해 시간·항목 수·메모리를 기록한다 (읽기만 한다)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MCAPTURE_PERF"] == "1"))
    func 성능_실제_홈_스캔_시간을_기록한다() {
        let home = NSHomeDirectory()
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        let roots = rules.normalizedRoots(["~", "/Applications", "/System/Applications"], home: home)
        let (index, report) = FileTreeScanner.scan(roots: roots, rules: rules)
        let seconds = Double(report.elapsed.components.seconds) + Double(report.elapsed.components.attoseconds) / 1e18
        print("스캔 \(report.entries)개 (디렉터리 \(report.directories)), \(String(format: "%.1f", seconds))초, \(Int(Double(report.entries) / seconds))개/초")
        print("이름 평균 \(index.nameByteCount / max(1, index.count))바이트, 추정 메모리 \(index.estimatedBytes / 1_000_000)MB, 거부 \(report.deniedPaths.count)개")
        print("거부 예: \(report.deniedPaths.prefix(15).joined(separator: ", "))")
        // 많이 차지하는 ~/Library 하위 폴더 (제외 규칙 조정용)
        if let library = index.lookup(path: home + "/Library") {
            var sizes: [(String, Int)] = []
            for child in index.children(of: library) {
                var count = 0
                var stack = [child]
                while let current = stack.popLast() {
                    count += 1
                    stack += index.children(of: current)
                }
                sizes.append((index.name(of: child), count))
            }
            print("~/Library 상위: " + sizes.sorted { $0.1 > $1.1 }.prefix(12).map { "\($0.0) \($0.1)" }.joined(separator: ", "))
        }
    }

    @Test func 하위_트리를_따로_스캔해_붙인다() throws {
        let tree = try TempTree()
        try tree.directory("a")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: noRules)
        try tree.file("a/b/c.txt")
        let sub = FileTreeScanner.scanSubtree(path: tree.path("a"), rules: noRules)
        index.graft(sub.index, onto: index.lookup(path: tree.path("a"))!)
        #expect(index.lookup(path: tree.path("a/b/c.txt")) != nil)
    }
}

@Suite("DirectoryReconciler")
struct DirectoryReconcilerTests {
    let rules = ExclusionRules(text: "node_modules", home: "/nonexistent", includeHidden: false)

    // 디렉터리를 다시 읽어 맞추고, 새로 스캔할 디렉터리는 스캔해 붙인다 (앱 인덱서가 하는 일의 축소판)
    private func reconcile(_ path: String, in index: inout FileIndex) throws {
        let id = try #require(index.lookup(path: path))
        let listing = try DirectoryReconciler.list(directory: path, rules: rules)
        for directory in DirectoryReconciler.apply(listing, to: id, in: &index) {
            index.graft(FileTreeScanner.scanSubtree(path: index.path(of: directory), rules: rules).index, onto: directory)
        }
    }

    @Test func 새_파일과_폴더를_추가한다() throws {
        let tree = try TempTree()
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try tree.file("new.txt")
        try tree.file("dir/inner/deep.txt")
        try reconcile(tree.root, in: &index)
        #expect(index.lookup(path: tree.path("new.txt")) != nil)
        #expect(index.lookup(path: tree.path("dir/inner/deep.txt")) != nil)
    }

    @Test func 없어진_폴더는_하위_트리째_지운다() throws {
        let tree = try TempTree()
        try tree.file("gone/a/b.txt")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try FileManager.default.removeItem(atPath: tree.path("gone"))
        try reconcile(tree.root, in: &index)
        #expect(paths(index) == [tree.root])
    }

    @Test func 폴더_이름을_바꾸면_새_경로로_옮겨진다() throws {
        let tree = try TempTree()
        try tree.file("old/x.txt")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try FileManager.default.moveItem(atPath: tree.path("old"), toPath: tree.path("new"))
        try reconcile(tree.root, in: &index)
        #expect(paths(index) == [tree.root, tree.path("new"), tree.path("new/x.txt")])
    }

    @Test func 대소문자만_바꾼_이름도_하나만_남는다() throws {
        let tree = try TempTree()
        try tree.file("a.txt")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try FileManager.default.moveItem(atPath: tree.path("a.txt"), toPath: tree.path("A.txt"))
        try reconcile(tree.root, in: &index)
        #expect(paths(index) == [tree.root, tree.path("A.txt")])
    }

    @Test func 여러_번_적용해도_같다() throws {
        let tree = try TempTree()
        try tree.file("k/v.txt")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try tree.file("k/w.txt")
        try reconcile(tree.path("k"), in: &index)
        let once = paths(index)
        let count = index.liveCount
        try reconcile(tree.path("k"), in: &index)
        try reconcile(tree.root, in: &index)
        #expect(paths(index) == once)
        #expect(index.liveCount == count)
    }

    @Test func 파일이_폴더로_바뀌면_교체한다() throws {
        let tree = try TempTree()
        try tree.file("thing")
        var (index, _) = FileTreeScanner.scan(roots: [tree.root], rules: rules)
        try FileManager.default.removeItem(atPath: tree.path("thing"))
        try tree.file("thing/inside.txt")
        try reconcile(tree.root, in: &index)
        #expect(index.flags(of: index.lookup(path: tree.path("thing"))!).contains(.directory))
        #expect(index.lookup(path: tree.path("thing/inside.txt")) != nil)
    }
}
