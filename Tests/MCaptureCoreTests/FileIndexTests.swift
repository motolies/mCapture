import Foundation
import Testing
@testable import MCaptureCore

/// 시험용 작은 인덱스: /r 아래 proj/src/main.swift, proj/README.md, 한글문서.txt, Tools.app
private func sampleIndex() -> (index: FileIndex, ids: [String: UInt32]) {
    var index = FileIndex()
    var ids: [String: UInt32] = [:]
    let root = index.appendRoot(path: "/r")
    ids["/r"] = root
    let proj = index.append(name: "proj", parent: root, flags: .directory)
    ids["proj"] = proj
    let src = index.append(name: "src", parent: proj, flags: .directory)
    ids["src"] = src
    ids["main.swift"] = index.append(name: "main.swift", parent: src, flags: [])
    ids["README.md"] = index.append(name: "README.md", parent: proj, flags: [])
    ids["한글문서.txt"] = index.append(name: "한글문서.txt".decomposedStringWithCanonicalMapping, parent: root, flags: [])
    ids["Tools.app"] = index.append(name: "Tools.app", parent: root, flags: [.directory, .package, .unindexed])
    return (index, ids)
}

@Suite("FileIndex")
struct FileIndexTests {
    @Test func 경로를_부모_사슬로_복원한다() {
        let (index, ids) = sampleIndex()
        #expect(index.path(of: ids["main.swift"]!) == "/r/proj/src/main.swift")
        #expect(index.path(of: ids["/r"]!) == "/r")
        #expect(index.depth(of: ids["main.swift"]!) == 3)
    }

    @Test func 루트가_슬래시여도_경로가_겹치지_않는다() {
        var index = FileIndex()
        let root = index.appendRoot(path: "/")
        let child = index.append(name: "Applications", parent: root, flags: .directory)
        #expect(index.path(of: child) == "/Applications")
        #expect(index.lookup(path: "/Applications") == child)
    }

    @Test func 이름은_NFC로_저장한다() {
        let (index, ids) = sampleIndex()
        #expect(index.name(of: ids["한글문서.txt"]!).unicodeScalars.count == 8)
        #expect(index.lookup(path: "/r/한글문서.txt".decomposedStringWithCanonicalMapping) == ids["한글문서.txt"])
    }

    @Test func 자식_목록과_경로_조회() {
        let (index, ids) = sampleIndex()
        #expect(Set(index.children(of: ids["proj"]!)) == [ids["src"]!, ids["README.md"]!])
        #expect(index.lookup(path: "/r/proj/src/main.swift") == ids["main.swift"])
        #expect(index.lookup(path: "/r/proj/none") == nil)
        #expect(index.lookup(path: "/other") == nil)
    }

    @Test func 하위_트리_삭제는_자손만_지운다() {
        var (index, ids) = sampleIndex()
        index.removeSubtree(ids["proj"]!)
        #expect(index.isRemoved(ids["proj"]!))
        #expect(index.isRemoved(ids["main.swift"]!))
        #expect(!index.isRemoved(ids["Tools.app"]!))
        #expect(index.removedCount == 4)
        #expect(index.liveCount == 3)
        #expect(index.lookup(path: "/r/proj") == nil)
        #expect(!index.children(of: ids["/r"]!).contains(ids["proj"]!))
    }

    @Test func 압축하면_번호가_바뀌어도_경로가_같다() {
        var (index, ids) = sampleIndex()
        index.removeSubtree(ids["src"]!)
        let before = Set((0..<UInt32(index.count)).filter { !index.isRemoved($0) }.map { index.path(of: $0) })
        index.compact()
        let after = Set((0..<UInt32(index.count)).map { index.path(of: $0) })
        #expect(index.removedCount == 0)
        #expect(index.count == 5)
        #expect(before == after)
        #expect(index.roots.count == 1)
        #expect(index.lookup(path: "/r/proj/README.md") != nil)
        // 부모 번호 불변식
        #expect((0..<index.count).allSatisfy { i in
            let parent = index.parent(of: UInt32(i))
            return parent == FileIndex.none || Int(parent) < i
        })
    }

    @Test func 삭제_후_다시_추가할_수_있다() {
        var (index, ids) = sampleIndex()
        index.removeSubtree(ids["README.md"]!)
        let again = index.append(name: "README.md", parent: ids["proj"]!, flags: [])
        #expect(index.lookup(path: "/r/proj/README.md") == again)
    }
}

@Suite("ExclusionRules")
struct ExclusionRulesTests {
    let home = "/Users/tester"

    @Test func 줄마다_이름_규칙과_경로_규칙을_나눈다() {
        let rules = ExclusionRules(text: "node_modules\n~/Library/Caches\n# 주석\n\n/tmp/x/", home: home, includeHidden: false)
        #expect(rules.names == ["node_modules"])
        #expect(rules.paths == ["/Users/tester/Library/Caches", "/tmp/x"])
    }

    @Test func 경로_규칙은_경로가_같을_때만() {
        let rules = ExclusionRules(text: "~/Library/Caches", home: home, includeHidden: false)
        #expect(rules.excludesContents(ofDirectory: "/Users/tester/Library/Caches", name: "Caches"))
        #expect(!rules.excludesContents(ofDirectory: "/Users/tester/Library/CachesX", name: "CachesX"))
        #expect(!rules.excludesContents(ofDirectory: "/Users/tester/Library", name: "Library"))
    }

    @Test func 이름_규칙은_어느_깊이든() {
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        #expect(rules.excludesContents(ofDirectory: "/Users/tester/git/a/b/node_modules", name: "node_modules"))
        #expect(!rules.excludesContents(ofDirectory: "/Users/tester/git/a/b/src", name: "src"))
    }

    @Test func 숨김은_점_이름만() {
        let hidden = ExclusionRules(text: "", home: home, includeHidden: false)
        #expect(hidden.skipsEntry(named: ".zshrc"))
        #expect(!hidden.skipsEntry(named: "Library"))
        #expect(!ExclusionRules(text: "", home: home, includeHidden: true).skipsEntry(named: ".zshrc"))
    }

    @Test func 제외_영역_안의_이벤트_경로를_거른다() {
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        let root = home
        #expect(rules.isInsideExcludedArea("/Users/tester/git/a/node_modules/pkg/x.js", root: root))
        #expect(!rules.isInsideExcludedArea("/Users/tester/git/a/node_modules", root: root))
        #expect(rules.isInsideExcludedArea("/Users/tester/Library/Caches/com.x/y", root: root))
        #expect(rules.isInsideExcludedArea("/Users/tester/.config/fish/config.fish", root: root))
        #expect(rules.isInsideExcludedArea("/Users/tester/.zshrc", root: root))
        #expect(!rules.isInsideExcludedArea("/Users/tester/Documents/a.txt", root: root))
    }

    @Test func 겹치는_루트를_정리한다() {
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        let roots = rules.normalizedRoots(["~", "/Applications", "~/Documents", "~/", "/System/Applications"], home: home)
        #expect(roots == ["/Users/tester", "/Applications", "/System/Applications"])
    }

    @Test func 제외_영역_안에_직접_추가한_루트는_따로_색인한다() {
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        // 설정에는 열기 패널이 준 NFD 경로가 저장된다
        let oneDrive = "~/Library/CloudStorage/OneDrive-회사".decomposedStringWithCanonicalMapping
        let roots = rules.normalizedRoots(["~", oneDrive, oneDrive + "/문서", "~/git/a/node_modules/pkg", "~/.config", "~/Library/Caches"], home: home)
        // 루트 안의 하위 폴더(문서)와 제외 경로 자체(Caches 폴더는 ~에서 이름이 색인되지만 안은 아님)는 구분한다
        #expect(roots == ["/Users/tester", "/Users/tester/Library/CloudStorage/OneDrive-회사",
                          "/Users/tester/git/a/node_modules/pkg", "/Users/tester/.config", "/Users/tester/Library/Caches"])
    }

    @Test func 직접_추가한_루트의_이벤트는_바깥_제외_규칙에_걸리지_않는다() {
        let rules = ExclusionRules(text: ExclusionRules.defaultText, home: home, includeHidden: false)
        let oneDrive = "/Users/tester/Library/CloudStorage/OneDrive-회사"
        #expect(rules.isInsideExcludedArea(oneDrive + "/보고서.docx", root: home))
        #expect(!rules.isInsideExcludedArea(oneDrive + "/보고서.docx", root: oneDrive))
        #expect(rules.isInsideExcludedArea(oneDrive + "/web/node_modules/x.js", root: oneDrive))
        // FSEvents 제외 경로에서 루트를 품은 규칙만 빠진다
        let exclusions = rules.eventExclusions(roots: [home, oneDrive])
        #expect(!exclusions.contains("/Users/tester/Library/CloudStorage"))
        #expect(exclusions.contains("/Users/tester/Library/Caches"))
        #expect(rules.eventExclusions(roots: [home]).contains("/Users/tester/Library/CloudStorage"))
    }

    @Test func 설정_해시는_같은_설정이면_같다() {
        let a = ExclusionRules(text: "b\na", home: home, includeHidden: false)
        let b = ExclusionRules(text: "a\nb", home: home, includeHidden: false)
        let c = ExclusionRules(text: "a\nb", home: home, includeHidden: true)
        #expect(a.configHash(roots: ["/x"]) == b.configHash(roots: ["/x"]))
        #expect(a.configHash(roots: ["/x"]) != c.configHash(roots: ["/x"]))
        #expect(a.configHash(roots: ["/x"]) != a.configHash(roots: ["/y"]))
        // 알려진 FNV-1a 값 (빈 입력 = 오프셋)
        #expect(FNV1a.hash([]) == 0xcbf2_9ce4_8422_2325)
        #expect(FNV1a.hash(Array("a".utf8)) == 0xaf63_dc4c_8601_ec8c)
    }
}

@Suite("FileIndexSnapshot")
struct FileIndexSnapshotTests {
    private func snapshot() -> FileIndexSnapshot {
        var (index, ids) = sampleIndex()
        index.removeSubtree(ids["README.md"]!)
        return FileIndexSnapshot(index: index, configHash: 42, lastEventId: 123_456, deviceUUIDs: ["UUID-A"],
                                 savedAt: Date(timeIntervalSince1970: 1_792_116_332))
    }

    @Test func 저장하고_읽으면_같다() throws {
        let original = snapshot()
        let decoded = try #require(FileIndexSnapshot.decode(original.encoded(), expectedConfigHash: 42))
        #expect(decoded.lastEventId == 123_456)
        #expect(decoded.deviceUUIDs == ["UUID-A"])
        #expect(decoded.savedAt == original.savedAt)
        #expect(decoded.index.count == original.index.count)
        #expect(decoded.index.removedCount == 1)
        #expect(decoded.index.lookup(path: "/r/proj/src/main.swift") != nil)
        #expect(decoded.index.lookup(path: "/r/proj/README.md") == nil)
        #expect(decoded.index.roots == original.index.roots)
    }

    @Test func 설정_해시가_다르면_nil() {
        #expect(FileIndexSnapshot.decode(snapshot().encoded(), expectedConfigHash: 43) == nil)
    }

    @Test func 잘린_파일은_nil() {
        let data = snapshot().encoded()
        #expect(FileIndexSnapshot.decode(data.prefix(data.count - 20), expectedConfigHash: 42) == nil)
        #expect(FileIndexSnapshot.decode(Data(), expectedConfigHash: 42) == nil)
    }

    @Test func 바이트가_바뀌면_nil() {
        var data = snapshot().encoded()
        data[data.count / 2] ^= 0xFF
        #expect(FileIndexSnapshot.decode(data, expectedConfigHash: 42) == nil)
    }

    @Test func 부모_불변식이_깨지면_nil() {
        #expect(FileIndex(names: Array("ab".utf8), nameOffsets: [0, 1, 2], parents: [1, FileIndex.none], flags: [0, 0]) == nil)
        #expect(FileIndex(names: Array("ab".utf8), nameOffsets: [0, 1, 2], parents: [FileIndex.none, 0], flags: [0, 0]) != nil)
    }
}

@Suite("FileSearcher")
struct FileSearcherTests {
    private func search(_ text: String, in index: FileIndex? = nil, composing: Bool = false, limit: Int = 50) async -> SearchResults {
        await FileSearcher.search(SearchQuery(text, home: "/r", composing: composing), in: index ?? sampleIndex().index, limit: limit)
    }

    @Test func 여러_항은_AND() async {
        let results = await search("ma sw")
        #expect(results.hits.map(\.name) == ["main.swift"])
    }

    @Test func 초성으로_찾는다() async {
        let results = await search("ㅎㄱ")
        #expect(results.hits.map(\.name) == ["한글문서.txt"])
        #expect(results.hits.first?.highlights == [0, 1])
    }

    @Test func ext_필터() async {
        #expect(await search("ext:md").hits.map(\.name) == ["README.md"])
        #expect(await search("ext:swift;txt").totalMatches == 2)
    }

    @Test func folder_file_필터() async {
        #expect(Set(await search("folder:").hits.map(\.name)) == ["proj", "src", "Tools.app"])
        #expect(await search("file:main").hits.map(\.name) == ["main.swift"])
        #expect(await search("folder:main").hits.isEmpty)
    }

    @Test func 경로항은_자손까지_맞는다() async {
        let results = await search("proj/src")
        #expect(Set(results.hits.map(\.name)) == ["src", "main.swift"])
    }

    @Test func 경로항은_이름_앞부분까지_이어진다() async {
        #expect(await search("src/ma").hits.map(\.name) == ["main.swift"])
        #expect(await search("/r/proj/READ").hits.map(\.name) == ["README.md"])
        #expect(await search("PROJ/ main").hits.map(\.name) == ["main.swift"])
    }

    @Test func 물결_경로항은_홈에서_시작한다() async {
        // 시험 홈은 /r
        #expect(await search("~/proj/src/").hits.map(\.name) == ["main.swift"])
    }

    @Test func regex는_이름에_맞춘다() async {
        #expect(await search("regex:^read.*\\.md$").hits.map(\.name) == ["README.md"])
    }

    @Test func 앱은_보너스로_위에_온다() async {
        var index = FileIndex()
        let root = index.appendRoot(path: "/a")
        index.append(name: "Tooling.txt", parent: root, flags: [])
        index.append(name: "Tools.app", parent: root, flags: [.directory, .package])
        let results = await search("tool", in: index)
        #expect(results.hits.map(\.name) == ["Tools.app", "Tooling.txt"])
    }

    @Test func 동점은_이름이_짧고_얕은_쪽이_앞() async {
        var index = FileIndex()
        let root = index.appendRoot(path: "/a")
        let deep = index.append(name: "x", parent: root, flags: .directory)
        index.append(name: "note.txt", parent: deep, flags: [])
        index.append(name: "note.txt", parent: root, flags: [])
        index.append(name: "note.text", parent: root, flags: [])
        let results = await search("note", in: index)
        #expect(results.hits.map(\.path) == ["/a/note.txt", "/a/x/note.txt", "/a/note.text"])
    }

    @Test func 상위_K개와_전체_개수() async {
        var index = FileIndex()
        let root = index.appendRoot(path: "/a")
        for i in 0..<30_000 { index.append(name: "file\(i).log", parent: root, flags: []) }
        let results = await search("file", in: index, limit: 10)
        #expect(results.totalMatches == 30_000)
        #expect(results.hits.count == 10)
        #expect(results.hits.first?.name == "file0.log")
    }

    @Test func 삭제된_항목과_루트는_결과에_없다() async {
        var (index, ids) = sampleIndex()
        index.removeSubtree(ids["src"]!)
        #expect(await search("main", in: index).hits.isEmpty)
        #expect(await search("r", in: index).hits.allSatisfy { $0.path != "/r" })
    }

    @Test func 빈_검색어나_오류는_빈_결과() async {
        #expect(await search("").hits.isEmpty)
        #expect(await search("regex:([").hits.isEmpty)
    }

    @Test func 조합_중_마지막_음절도_찾는다() async {
        #expect(await search("하", composing: true).hits.map(\.name) == ["한글문서.txt"])
    }

    @Test func UTF8을_스칼라로_푼다() {
        let text = "a한😀é"
        let bytes = Array(text.utf8)
        var scalars: [UInt32] = []
        bytes.withUnsafeBufferPointer { FileSearcher.decode($0, into: &scalars) }
        #expect(scalars == text.unicodeScalars.map(\.value))
    }

    /// MCAPTURE_PERF=1일 때만: 110만 개 합성 인덱스에서 검색 시간을 기록한다 (시간으로 실패시키지 않는다)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MCAPTURE_PERF"] == "1"))
    func 성능_합성_110만개_검색_시간을_기록한다() async {
        var index = FileIndex()
        index.reserveCapacity(entries: 1_100_000, nameBytes: 30_000_000)
        let root = index.appendRoot(path: "/Users/tester")
        let words = ["report", "invoice", "main", "View", "Controller", "보고서", "회의록", "사진", "IMG", "backup", "config", "test"]
        var directories: [UInt32] = [root]
        var generator = SystemRandomNumberGenerator()
        for i in 0..<1_100_000 {
            let parent = directories[Int.random(in: 0..<directories.count, using: &generator)]
            let isDirectory = i % 8 == 0
            let name = "\(words[i % words.count])_\(words[(i / 7) % words.count])\(i)" + (isDirectory ? "" : [".txt", ".swift", ".png", ".pdf"][i % 4])
            let id = index.append(name: name, parent: parent, flags: isDirectory ? .directory : [])
            if isDirectory { directories.append(id) }
        }
        print("항목 \(index.count)개, 이름 평균 \(index.nameByteCount / index.count)바이트, 추정 메모리 \(index.estimatedBytes / 1_000_000)MB")
        for text in ["report", "rpt", "ㅂㄱㅅ", "ext:pdf invoice", "main/ view", "regex:^IMG_.*9$"] {
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = ContinuousClock.now
                _ = await FileSearcher.search(SearchQuery(text, home: "/Users/tester"), in: index)
                let elapsed = ContinuousClock.now - start
                samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
            }
            samples.sort()
            print("검색 \"\(text)\": 중앙값 \(Int(samples[2]))ms, 최대 \(Int(samples[4]))ms")
        }
        let encodeStart = ContinuousClock.now
        let data = FileIndexSnapshot(index: index, configHash: 1, lastEventId: 1, deviceUUIDs: []).encoded()
        let encoded = ContinuousClock.now
        _ = FileIndexSnapshot.decode(data, expectedConfigHash: 1)
        print("스냅샷 \(data.count / 1_000_000)MB, 저장 \(encoded - encodeStart), 로드 \(ContinuousClock.now - encoded)")
    }
}
