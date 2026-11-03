import Foundation
import Darwin
import Testing
@testable import MCaptureCore

/// Opt-in release benchmark; timings are evidence, never test assertions.
@Suite struct SearchBenchmarkTests {
    func ms(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
    func cpu() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    }
    func rss() -> UInt64 {
        var info = proc_taskinfo()
        _ = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        return info.pti_resident_size
    }
    func measure(_ index: FileIndex, label: String) async {
        print("BENCH index=\(label) entries=\(index.count) estimated=\(index.estimatedBytes) rss=\(rss())")
        #if !SEARCH_BASELINE
        print("BENCH candidate_bytes=\(index.candidateIndex.estimatedBytes)")
        #endif
        for text in ["한승우", "ㅎㅅㅇ", "한", "main", "mvs", "한 ext:pdf", "ext:pdf", "/src/ main", "regex:^main"] {
            let query = SearchQuery(text, home: NSHomeDirectory())
            for _ in 0..<5 { _ = await FileSearcher.search(query, in: index) }
            var times: [Double] = []
            let cpuStart = cpu()
            var matches = 0
            for _ in 0..<30 {
                let start = ContinuousClock.now
                let result = await FileSearcher.search(query, in: index)
                times.append(ms(ContinuousClock.now - start))
                matches = result.totalMatches
            }
            let cpuMean = (cpu() - cpuStart) / 30
            times.sort()
            var count = index.count
            #if !SEARCH_BASELINE
            count = index.candidateIndex.candidates(for: FileSearcher.Plan(query: query).matchers)?.count ?? index.count
            #endif
            print("BENCH \(label) query=\(text) median_ms=\(times[15]) p95_ms=\(times[28]) cpu_ms=\(cpuMean) candidates=\(count) matches=\(matches)")
        }
        let start = ContinuousClock.now
        let data = FileIndexSnapshot(index: index, configHash: 1, lastEventId: 0, deviceUUIDs: []).encoded()
        let load = ContinuousClock.now
        let restored = FileIndexSnapshot.decode(data, expectedConfigHash: 1)!
        print("BENCH \(label) encode_ms=\(ms(load - start)) load_ms=\(ms(ContinuousClock.now - load)) restored=\(restored.index.count)")
        let before = rss()
        let mutate = ContinuousClock.now
        var changed = index
        for i in 0..<100 { changed.append(name: "한승우-change-\(i).pdf", parent: 0, flags: []) }
        print("BENCH \(label) snapshot_100_changes_ms=\(ms(ContinuousClock.now - mutate)) rss_delta=\(Int64(rss()) - Int64(before)) changed=\(changed.count)")
    }
    @Test func releaseBenchmark() async {
        guard ProcessInfo.processInfo.environment["MCAPTURE_BENCHMARK"] == "1" else { return }
        for mixed in [false, true] {
            let before = rss()
            let start = ContinuousClock.now
            var index = FileIndex()
            index.reserveCapacity(entries: 1_000_001, nameBytes: 40_000_000)
            let root = index.appendRoot(path: "/src")
            var seed: UInt64 = 42
            for i in 0..<1_000_000 {
                seed = seed &* 6364136223846793005 &+ 1
                let name: String
                if i % (mixed ? 10 : 1000) == 0 { name = "한승우-\(i).pdf" }
                else if i % 17 == 0 { name = "mainView-\(i).swift" }
                else { name = "build-artifact-\(String(seed, radix: 16)).o" }
                index.append(name: name, parent: root, flags: [])
            }
            let label = mixed ? "mixed1m" : "ascii1m"
            print("BENCH \(label) build_ms=\(ms(ContinuousClock.now - start)) rss_delta=\(Int64(rss()) - Int64(before))")
            await measure(index, label: label)
        }
        if ProcessInfo.processInfo.environment["MCAPTURE_BENCHMARK_HOME"] == "1" {
            for expanded in [false, true] {
                let text = expanded ? ExclusionRules.defaultText.split(separator: "\n").filter {
                    !["target", "build", "~/Library/Application Support/Google/Chrome"].contains(String($0))
                }.joined(separator: "\n") : ExclusionRules.defaultText
                let start = ContinuousClock.now
                let scanned = FileTreeScanner.scan(roots: [NSHomeDirectory()], rules: ExclusionRules(text: text, home: NSHomeDirectory(), includeHidden: false))
                let label = expanded ? "homeExpanded" : "homeDefault"
                print("BENCH \(label) scan_ms=\(ms(ContinuousClock.now - start))")
                await measure(scanned.index, label: label)
            }
        }
    }
}
