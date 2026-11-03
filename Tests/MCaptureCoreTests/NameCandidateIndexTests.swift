import Foundation
import Testing
@testable import MCaptureCore

@Suite struct NameCandidateIndexTests {
    func verify(_ index: FileIndex) async {
        for text in ["한승우", "ㅎㅅㅇ", "ㅎ", "하", "한", "한승우".decomposedStringWithCanonicalMapping,
                     "MAIN", "mn", "aa", "ab", "ba", "한 😀", "😀", "é", "ㄳ", "ㅏ", "없는결과",
                     "한 ext:pdf", "folder: 한", "file: main", "/root/ 한", "regex:^main", "ext:pdf", "main regex:.*pdf"] {
            for composing in [false, true] {
                let query = SearchQuery(text, home: "/root", composing: composing)
                for limit in [200, 10_000] {
                    let full = await FileSearcher.search(query, in: index, limit: limit, useCandidateIndex: false)
                    let filtered = await FileSearcher.search(query, in: index, limit: limit, useCandidateIndex: true)
                    #expect(full.totalMatches == filtered.totalMatches, "\(text)")
                    #expect(full.hits == filtered.hits, "\(text)")
                }
            }
        }
    }

    @Test func equivalenceAcrossLifecycle() async throws {
        var index = FileIndex()
        let root = index.appendRoot(path: "/root")
        let names = ["한승우.pdf", "한--승--우.txt", "우승한", "ㅎㅅㅇ", "하늘", "main.pdf", "MainView.swift",
                     "aab", "aba", "baa", "한😀.pdf", "éㅏㄳ", "한승우".decomposedStringWithCanonicalMapping]
        for i in 0..<600 { index.append(name: names[i % names.count], parent: root, flags: i % 9 == 0 ? [.directory] : []) }
        await verify(index)
        let copy = index
        let before = await FileSearcher.search(SearchQuery("한", home: "/root"), in: copy)
        index.removeSubtree(1)
        index.append(name: "한새이름.pdf", parent: root, flags: [])
        var sub = FileIndex()
        let subRoot = sub.appendRoot(path: "/sub")
        sub.append(name: "한승우main😀.pdf", parent: subRoot, flags: [])
        index.graft(sub, onto: root)
        await verify(index)
        let after = await FileSearcher.search(SearchQuery("한", home: "/root"), in: copy)
        #expect(before.hits == after.hits)
        #expect(before.totalMatches == after.totalMatches)
        index.compact()
        await verify(index)
        let data = FileIndexSnapshot(index: index, configHash: 1, lastEventId: 0, deviceUUIDs: []).encoded()
        let restored = try #require(FileIndexSnapshot.decode(data, expectedConfigHash: 1))
        await verify(restored.index)
        for budget in [0, 256, 4096] {
            index.rebuildCandidates(budget: budget)
            index.append(name: "한승우main😀", parent: 0, flags: [])
            #expect(index.candidateIndex.estimatedBytes <= budget)
            await verify(index)
        }
    }

    @Test func partialEvictionAndRandomSubsequences() async {
        var index = FileIndex()
        index.rebuildCandidates(budget: 24_000)
        let root = index.appendRoot(path: "/root")
        var seed: UInt64 = 12345
        let alphabet = Array("abcXYZ한승우하ㅎㅅㅇ😀éㄳㅏ".unicodeScalars)
        var queries: [String] = []
        for i in 0..<10_000 {
            var scalars = String.UnicodeScalarView()
            for _ in 0..<12 {
                seed = seed &* 6364136223846793005 &+ 1
                scalars.append(alphabet[Int(seed >> 32) % alphabet.count])
            }
            let name = String(scalars)
            index.append(name: name, parent: root, flags: [])
            if i % 100 == 0 { queries.append(String(String.UnicodeScalarView(scalars.enumerated().filter { $0.offset % 4 == 0 }.map(\.element)))) }
        }
        #expect(index.candidateIndex.estimatedBytes <= 24_000)
        let availability = alphabet.map { index.candidateIndex.candidates(for: [NameMatcher(term: String($0))]) != nil }
        #expect(availability.contains(true))
        #expect(availability.contains(false))
        for text in queries {
            let query = SearchQuery(text, home: "/root", composing: true)
            let full = await FileSearcher.search(query, in: index, limit: 20_000, useCandidateIndex: false)
            let filtered = await FileSearcher.search(query, in: index, limit: 20_000, useCandidateIndex: true)
            #expect(full.hits == filtered.hits)
            #expect(full.totalMatches == filtered.totalMatches)
        }
    }

    @Test func cancelledSearchReturnsNoPartialResults() async {
        var index = FileIndex()
        let root = index.appendRoot(path: "/root")
        for i in 0..<30_000 { index.append(name: "main\(i)", parent: root, flags: []) }
        let snapshot = index
        let task = Task { await FileSearcher.search(SearchQuery("main", home: "/root"), in: snapshot) }
        task.cancel()
        #expect(await task.value.totalMatches == 0)
    }
}
