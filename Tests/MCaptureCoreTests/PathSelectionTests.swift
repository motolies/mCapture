import Foundation
import Testing
@testable import MCaptureCore

@Suite("PathSelection")
struct PathSelectionTests {
    private func file(_ path: String) -> PathSelection.Item { .init(path: path, isDirectory: false) }
    private func folder(_ path: String) -> PathSelection.Item { .init(path: path, isDirectory: true) }

    @Test func 토글은_넣고_뺀다() {
        var selection = PathSelection()
        #expect(selection.toggle(file("/a/x.txt")) == .added)
        #expect(selection.contains("/a/x.txt"))
        #expect(selection.toggle(file("/a/x.txt")) == .removed)
        #expect(selection.isEmpty)
    }

    @Test func 상한을_넘으면_넣지_않는다() {
        var selection = PathSelection(limit: 2)
        #expect(selection.toggle(file("/1")) == .added)
        #expect(selection.toggle(file("/2")) == .added)
        #expect(selection.toggle(file("/3")) == .limitReached)
        #expect(selection.count == 2)
        #expect(selection.isFull)
    }

    @Test func 여러_개를_넣다가_상한에서_자른다() {
        var selection = PathSelection(limit: 3)
        selection.insert(file("/1"))
        let result = selection.insert(contentsOf: (1...5).map { file("/\($0)") })
        #expect(result.added == 2)
        #expect(result.truncated)
        #expect(selection.orderedItems.map(\.path) == ["/1", "/2", "/3"])
    }

    @Test func 체크한_순서를_지킨다() {
        var selection = PathSelection()
        selection.insert(file("/c"))
        selection.insert(file("/a"))
        selection.insert(file("/b"))
        selection.remove("/a")
        #expect(selection.orderedItems.map(\.path) == ["/c", "/b"])
    }

    @Test func 조상만_남긴다() {
        var selection = PathSelection()
        selection.insert(file("/a/b/c.txt"))
        selection.insert(folder("/a/b"))
        selection.insert(file("/a/bc.txt"))
        selection.insert(folder("/a-b"))
        selection.insert(file("/a-b/x"))
        #expect(selection.collapsedRoots().map(\.path) == ["/a/b", "/a/bc.txt", "/a-b"])
    }

    @Test func 파일은_조상이_되지_않는다() {
        var selection = PathSelection()
        selection.insert(file("/a/b"))
        selection.insert(file("/a/b/c"))
        #expect(selection.collapsedRoots().count == 2)
    }

    @Test func 루트_슬래시_아래도_조상으로_본다() {
        var selection = PathSelection()
        selection.insert(folder("/"))
        selection.insert(file("/x"))
        #expect(selection.collapsedRoots().map(\.path) == ["/"])
    }

    @Test func 조상_폴더가_체크되면_함께_포함으로_본다() {
        var selection = PathSelection()
        selection.insert(folder("/a/b"))
        #expect(selection.coverage(of: "/a/b") == .explicit)
        #expect(selection.coverage(of: "/a/b/c/d.txt") == .implied(ancestor: "/a/b"))
        #expect(selection.coverage(of: "/a/bc") == PathSelection.Coverage.none)
        #expect(selection.coverage(of: "/a") == PathSelection.Coverage.none)
    }

    @Test func 자손까지_뺀다() {
        var selection = PathSelection()
        selection.insert(folder("/a/b"))
        selection.insert(file("/a/b/c"))
        selection.insert(file("/a/bc"))
        selection.remove(paths: ["/a/b"], includingDescendants: true)
        #expect(selection.orderedItems.map(\.path) == ["/a/bc"])
        selection.insert(folder("/x"))
        selection.insert(file("/x/y"))
        selection.remove(paths: ["/x"], includingDescendants: false)
        #expect(selection.orderedItems.map(\.path) == ["/a/bc", "/x/y"])
    }

    @Test func NFD_경로도_같은_항목() {
        var selection = PathSelection()
        selection.insert(file("/문서/보고서.pdf".decomposedStringWithCanonicalMapping))
        #expect(selection.contains("/문서/보고서.pdf"))
        #expect(selection.toggle(file("/문서/보고서.pdf")) == .removed)
    }

    @Test func 파일과_폴더_수() {
        var selection = PathSelection()
        selection.insert(file("/a"))
        selection.insert(folder("/b"))
        selection.insert(folder("/c"))
        #expect(selection.fileCount == 1)
        #expect(selection.folderCount == 2)
    }

    @Test func 조상_경로_목록() {
        #expect(PathSelection.ancestors(of: "/a/b/c") == ["/a/b", "/a", "/"])
        #expect(PathSelection.ancestors(of: "/a") == ["/"])
        #expect(PathSelection.ancestors(of: "/").isEmpty)
    }
}

@Suite("DeletionGuard")
struct DeletionGuardTests {
    let guardian = DeletionGuard(home: "/Users/tester",
                                 roots: ["/Users/tester", "/Applications", "/Users/tester/Library/CloudStorage/OneDrive-회사"],
                                 appPath: "/Users/tester/dev/cap/build/mCapture-dev.app")

    @Test(arguments: [
        ("/", DeletionGuard.Reason.topLevel),
        ("/Users", .topLevel),
        ("/Users/other", .topLevel),
        ("/Volumes/USB", .topLevel),
        ("/private/tmp", .topLevel),
        ("/System/Library/x", .system),
        ("/usr/local/bin/tool", .system),
        ("/Library/Fonts", .system),
        ("/private/var/log", .system),
        ("/Users/tester", .topLevel),
        ("/Applications", .topLevel),
        ("/Users/tester/Library/CloudStorage", .searchRoot),
        ("/Users/tester/Library/CloudStorage/OneDrive-회사", .searchRoot),
        ("/Users/tester/Documents", .standardFolder),
        ("/Users/tester/Downloads/", .standardFolder),
        ("/Users/tester/Library/Preferences", .standardFolder),
        ("/Users/tester/dev/cap/build", .selfApp),
        ("/Users/tester/dev/cap/build/mCapture-dev.app", .selfApp),
        ("/Applications/Safari.app", .appBundle),
        ("/Users/tester/Downloads/Tool.APP", .appBundle),
        ("/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/a.txt", .cloud),
        ("/Users/tester/Library/CloudStorage/OneDrive-회사/보고서.pdf", .cloud),
    ])
    func 막는_경로(path: String, reason: DeletionGuard.Reason) {
        #expect(guardian.reason(path: path) == reason, "\(path)")
    }

    @Test(arguments: [
        "/Users/tester/Downloads/old.zip",
        "/Users/tester/Documents/2026/계약서.pdf",
        "/Users/tester/Library/Preferences/com.example.plist",
        "/Users/tester/dev/cap/Sources",
        "/private/tmp/scratch/a.txt",
        "/Applications/readme.txt",
    ])
    func 허용하는_경로(path: String) {
        #expect(guardian.reason(path: path) == nil, "\(path)")
    }

    @Test func 대소문자와_NFD를_가리지_않는다() {
        #expect(guardian.reason(path: "/users/TESTER/documents") == .standardFolder)
        #expect(guardian.reason(path: "/Users/tester/Library/CloudStorage/OneDrive-회사".decomposedStringWithCanonicalMapping) == .searchRoot)
    }
}
