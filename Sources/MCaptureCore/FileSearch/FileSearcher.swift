import Foundation

/// 검색 결과 한 줄
/// `id`는 이번 검색의 인덱스 번호라 인덱스가 압축되면 다른 항목을 가리킬 수 있다. 오래 들고 있을 때는 `path`를 쓴다
public struct SearchHit: Sendable, Equatable {
    public let id: UInt32
    public let name: String
    public let path: String
    /// 인덱스 플래그 (폴더·패키지·심볼릭 링크 등)
    public let flags: FileIndex.Flags
    public let score: Int
    /// 이름에서 강조할 글자 위치 (유니코드 스칼라 번호)
    public let highlights: [Int]

    public init(id: UInt32, name: String, path: String, flags: FileIndex.Flags, score: Int = 0, highlights: [Int] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.flags = flags
        self.score = score
        self.highlights = highlights
    }

    public var isDirectory: Bool { flags.contains(.directory) }
    public var isPackage: Bool { flags.contains(.package) }
}

public struct SearchResults: Sendable {
    /// 순위대로 자른 상위 결과
    public let hits: [SearchHit]
    /// 조건에 맞은 전체 항목 수
    public let totalMatches: Int

    public static let empty = SearchResults(hits: [], totalMatches: 0)
}

/// 인덱스 값을 받아 병렬로 검색한다. 인덱스를 고치지 않으므로 어느 스레드에서 불러도 된다
public enum FileSearcher {
    public static let defaultLimit = 200
    /// .app 결과를 위로 올리는 보너스 (앱 실행기처럼 쓰기)
    static let appBonus = 300
    /// 이보다 작으면 나누지 않고 한 번에 훑는다
    static let parallelThreshold = 20_000

    /// 검색한다. 취소되면 빈 결과를 돌려준다
    /// @concurrent: 메인 액터에서 불러도 협력 스레드 풀에서 돈다 (호출자 액터에서 도는 nonisolated(nonsending) 기본값을 쓰지 않는다)
    @concurrent
    public static func search(_ query: SearchQuery, in index: FileIndex, limit: Int = defaultLimit) async -> SearchResults {
        guard query.error == nil, !query.isEmpty, index.count > 0, limit > 0 else { return .empty }
        let plan = Plan(query: query)
        var pathMask: [Bool]?
        if !query.pathTerms.isEmpty {
            pathMask = pathMatches(query.pathTerms, in: index)
        }
        guard !Task.isCancelled else { return .empty }

        let count = index.count
        let chunks = count < parallelThreshold ? 1 : max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = (count + chunks - 1) / chunks
        let mask = pathMask
        let partials = await withTaskGroup(of: Partial.self) { group in
            for chunk in 0..<chunks {
                let range = (chunk * chunkSize)..<min(count, (chunk + 1) * chunkSize)
                group.addTask { scan(range, in: index, plan: plan, pathMask: mask, limit: limit) }
            }
            var partials: [Partial] = []
            for await partial in group { partials.append(partial) }
            return partials
        }
        guard !Task.isCancelled else { return .empty }

        let candidates = partials.flatMap(\.candidates).sorted(by: Candidate.isBetter).prefix(limit)
        let total = partials.reduce(0) { $0 + $1.total }
        let hits = candidates.map { hit(for: $0, in: index, plan: plan) }
            .sorted { lhs, rhs in
                if lhs.hit.score != rhs.hit.score { return lhs.hit.score > rhs.hit.score }
                if lhs.nameLength != rhs.nameLength { return lhs.nameLength < rhs.nameLength }
                if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
                return lhs.hit.path < rhs.hit.path
            }
            .map(\.hit)
        return SearchResults(hits: hits, totalMatches: total)
    }

    // MARK: - 준비

    /// 검색어를 루프에서 바로 쓸 형태로 바꾼 것
    struct Plan: Sendable {
        let matchers: [NameMatcher]
        /// 소문자 ASCII로 접은 확장자 바이트들
        let extensions: [[UInt8]]
        let kind: SearchQuery.Kind
        let regexes: [RegexTerm]

        init(query: SearchQuery) {
            matchers = query.nameTerms.map { NameMatcher(term: $0.text, composing: $0.composing) }.filter { !$0.isEmpty }
            extensions = query.extensions.map { Array($0.utf8).map(FileSearcher.fold) }
            kind = query.kind
            regexes = query.regexes
        }
    }

    /// 후보 (순위 비교용 최소 정보)
    struct Candidate: Sendable {
        let score: Int
        let nameLength: Int
        let id: UInt32

        /// 점수가 높고, 이름이 짧고, 번호가 작은 쪽이 앞
        static func isBetter(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.nameLength != rhs.nameLength { return lhs.nameLength < rhs.nameLength }
            return lhs.id < rhs.id
        }
    }

    /// 청크 하나의 결과
    struct Partial: Sendable {
        let candidates: [Candidate]
        let total: Int
    }

    // MARK: - 훑기

    // 범위 안의 항목을 훑어 조건에 맞는 것의 상위 limit개와 전체 개수를 구한다 (싼 조건부터 거른다)
    static func scan(_ range: Range<Int>, in index: FileIndex, plan: Plan, pathMask: [Bool]?, limit: Int) -> Partial {
        var top = TopK(limit: limit)
        var total = 0
        var scalars: [UInt32] = []
        scalars.reserveCapacity(256)
        let skip = FileIndex.Flags.removed.rawValue | FileIndex.Flags.root.rawValue
        let directory = FileIndex.Flags.directory.rawValue
        let regexes = plan.regexes.map { $0.copy() }
        index.withStorage { names, offsets, _, flags in
            for i in range {
                if i & 4095 == 0, Task.isCancelled { break }
                let flag = flags[i]
                if flag & skip != 0 { continue }
                let isDirectory = flag & directory != 0
                switch plan.kind {
                case .file where isDirectory, .folder where !isDirectory: continue
                default: break
                }
                if let pathMask, !pathMask[i] { continue }
                let start = Int(offsets[i])
                let end = Int(offsets[i + 1])
                let name = UnsafeBufferPointer(rebasing: names[start..<end])
                if !plan.extensions.isEmpty, !hasExtension(name, plan.extensions) { continue }
                if !plan.matchers.allSatisfy({ $0.mayMatch(utf8: name) }) { continue }

                var score = 0
                if !plan.matchers.isEmpty {
                    decode(name, into: &scalars)
                    let matched = scalars.withUnsafeBufferPointer { buffer in
                        for matcher in plan.matchers {
                            guard let match = matcher.match(buffer) else { return false }
                            score += match.score
                        }
                        return true
                    }
                    if !matched { continue }
                }
                if !regexes.isEmpty, !regexes.allSatisfy({ $0.matches(utf8: name) }) { continue }
                if isDirectory, hasSuffix(name, appSuffix) { score += appBonus }
                total += 1
                top.insert(Candidate(score: score, nameLength: end - start, id: UInt32(i)))
            }
        }
        return Partial(candidates: top.items, total: total)
    }

    // 후보를 결과 줄로 만든다 (이름·경로·강조 위치·정렬용 깊이)
    private static func hit(for candidate: Candidate, in index: FileIndex, plan: Plan) -> (hit: SearchHit, nameLength: Int, depth: Int) {
        let name = index.name(of: candidate.id)
        let scalars = name.unicodeScalars.map(\.value)
        let highlights = Set(plan.matchers.flatMap { $0.positions(scalars) }).sorted()
        let hit = SearchHit(id: candidate.id, name: name, path: index.path(of: candidate.id),
                            flags: index.flags(of: candidate.id).subtracting([.removed, .root]),
                            score: candidate.score, highlights: highlights)
        return (hit, candidate.nameLength, index.depth(of: candidate.id))
    }

    // MARK: - 경로 항

    /// 경로 항마다 "전체 경로가 항을 포함하는지"를 항목별로 계산한다 (여러 항은 AND)
    ///
    /// 항 t를 마지막 `/`에서 h와 s로 나눈다. 항목 i의 경로가 t를 포함하려면
    /// 부모 경로가 이미 t를 포함하거나, 부모 경로가 h로 끝나고 i의 이름이 s로 시작해야 한다.
    /// 부모가 늘 먼저 나오므로 앞에서부터 한 번 훑으면 된다
    static func pathMatches(_ terms: [String], in index: FileIndex) -> [Bool] {
        let count = index.count
        var result = [Bool](repeating: true, count: count)
        let removed = FileIndex.Flags.removed.rawValue
        let directory = FileIndex.Flags.directory.rawValue
        for term in terms {
            let t = Array(term.utf8).map(fold)
            guard let slash = t.lastIndex(of: UInt8(ascii: "/")) else { continue }
            let h = Array(t[..<slash])
            let s = Array(t[(slash + 1)...])
            var contains = [Bool](repeating: false, count: count)
            var endsWithH = [Bool](repeating: false, count: count)
            index.withStorage { names, offsets, parents, flags in
                let nameOf = { (i: Int) in UnsafeBufferPointer(rebasing: names[Int(offsets[i])..<Int(offsets[i + 1])]) }
                for i in 0..<count {
                    if i & 65535 == 0, Task.isCancelled { return }
                    let flag = flags[i]
                    if flag & removed != 0 {
                        result[i] = false
                        continue
                    }
                    let parent = parents[i]
                    let name = nameOf(i)
                    let match: Bool
                    if parent == FileIndex.none {
                        match = containsFolded(name, t)
                    } else {
                        let p = Int(parent)
                        match = contains[p] || (endsWithH[p] && hasPrefixFolded(name, s))
                    }
                    if flag & directory != 0 {
                        contains[i] = match
                        endsWithH[i] = pathEndsWith(i, h, parents: parents, nameOf: nameOf)
                    }
                    if !match { result[i] = false }
                }
            }
        }
        return result
    }

    // 항목의 전체 경로가 h로 끝나는지 (대소문자 무시). 이름을 뒤에서부터 비교하며 부모로 올라간다
    private static func pathEndsWith(_ i: Int, _ h: [UInt8], parents: UnsafeBufferPointer<UInt32>,
                                     nameOf: (Int) -> UnsafeBufferPointer<UInt8>) -> Bool {
        var k = h.count - 1
        var node = i
        while true {
            let name = nameOf(node)
            var j = name.count - 1
            while j >= 0 {
                if k < 0 { return true }
                if fold(name[j]) != h[k] { return false }
                j -= 1
                k -= 1
            }
            if k < 0 { return true }
            let parent = parents[node]
            if parent == FileIndex.none { return false }
            // 부모 경로가 /로 끝나면(루트 /) 구분자를 따로 두지 않는다
            if nameOf(Int(parent)).last != UInt8(ascii: "/") {
                if h[k] != UInt8(ascii: "/") { return false }
                k -= 1
                if k < 0 { return true }
            }
            node = Int(parent)
        }
    }

    // MARK: - 바이트 도우미

    static let appSuffix = Array(".app".utf8)

    // ASCII 대문자를 소문자로 접는다
    @inline(__always)
    static func fold(_ byte: UInt8) -> UInt8 {
        byte &- 0x41 < 26 ? byte + 32 : byte
    }

    // 이름의 확장자(앞의 점 제외 마지막 점 뒤)가 목록 중 하나인지
    static func hasExtension(_ name: UnsafeBufferPointer<UInt8>, _ extensions: [[UInt8]]) -> Bool {
        guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0 else { return false }
        let length = name.count - dot - 1
        return extensions.contains { ext in
            ext.count == length && ext.indices.allSatisfy { fold(name[dot + 1 + $0]) == ext[$0] }
        }
    }

    // 이름이 접미사(소문자)로 끝나는지
    static func hasSuffix(_ name: UnsafeBufferPointer<UInt8>, _ suffix: [UInt8]) -> Bool {
        guard name.count >= suffix.count else { return false }
        let start = name.count - suffix.count
        return suffix.indices.allSatisfy { fold(name[start + $0]) == suffix[$0] }
    }

    // 이름이 접두사(소문자)로 시작하는지
    static func hasPrefixFolded(_ name: UnsafeBufferPointer<UInt8>, _ prefix: [UInt8]) -> Bool {
        guard name.count >= prefix.count else { return false }
        return prefix.indices.allSatisfy { fold(name[$0]) == prefix[$0] }
    }

    // 바이트열이 needle(소문자)을 포함하는지
    static func containsFolded(_ bytes: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard needle.count <= bytes.count else { return false }
        if needle.isEmpty { return true }
        for start in 0...(bytes.count - needle.count) where needle.indices.allSatisfy({ fold(bytes[start + $0]) == needle[$0] }) {
            return true
        }
        return false
    }

    // UTF-8 바이트를 스칼라 값으로 풀어 버퍼에 담는다 (이름은 Swift 문자열에서 왔으므로 올바른 UTF-8이다)
    @inline(__always)
    static func decode(_ bytes: UnsafeBufferPointer<UInt8>, into scalars: inout [UInt32]) {
        scalars.removeAll(keepingCapacity: true)
        var i = 0
        let n = bytes.count
        while i < n {
            let b0 = UInt32(bytes[i])
            if b0 < 0x80 {
                scalars.append(b0)
                i += 1
            } else if b0 < 0xE0, i + 1 < n {
                scalars.append((b0 & 0x1F) << 6 | (UInt32(bytes[i + 1]) & 0x3F))
                i += 2
            } else if b0 < 0xF0, i + 2 < n {
                scalars.append((b0 & 0x0F) << 12 | (UInt32(bytes[i + 1]) & 0x3F) << 6 | (UInt32(bytes[i + 2]) & 0x3F))
                i += 3
            } else if i + 3 < n {
                scalars.append((b0 & 0x07) << 18 | (UInt32(bytes[i + 1]) & 0x3F) << 12
                    | (UInt32(bytes[i + 2]) & 0x3F) << 6 | (UInt32(bytes[i + 3]) & 0x3F))
                i += 4
            } else {
                scalars.append(0xFFFD)
                i += 1
            }
        }
    }
}

/// 상위 K개만 남기는 힙. 루트에 가장 못한 후보를 둔다
struct TopK {
    let limit: Int
    private(set) var items: [FileSearcher.Candidate] = []

    init(limit: Int) {
        self.limit = limit
        items.reserveCapacity(limit)
    }

    /// 후보를 넣는다. 꽉 찼으면 가장 못한 후보보다 나을 때만 바꾼다
    mutating func insert(_ candidate: FileSearcher.Candidate) {
        if items.count < limit {
            items.append(candidate)
            siftUp(items.count - 1)
        } else if FileSearcher.Candidate.isBetter(candidate, items[0]) {
            items[0] = candidate
            siftDown(0)
        }
    }

    // 새로 넣은 후보를 위로 올린다 (부모가 더 나으면 자리를 바꾼다)
    private mutating func siftUp(_ index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard FileSearcher.Candidate.isBetter(items[parent], items[child]) else { return }
            items.swapAt(parent, child)
            child = parent
        }
    }

    // 루트를 아래로 내린다 (자식 중 더 못한 쪽과 자리를 바꾼다)
    private mutating func siftDown(_ index: Int) {
        var parent = index
        let count = items.count
        while true {
            var worst = parent
            let left = parent * 2 + 1
            let right = left + 1
            if left < count, FileSearcher.Candidate.isBetter(items[worst], items[left]) { worst = left }
            if right < count, FileSearcher.Candidate.isBetter(items[worst], items[right]) { worst = right }
            if worst == parent { return }
            items.swapAt(parent, worst)
            parent = worst
        }
    }
}
