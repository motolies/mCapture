import Foundation

/// Derived, copy-on-write postings. Missing keys are empty only while indexing is complete;
/// evicted keys remain unavailable until a rebuild.
struct NameCandidateIndex: Sendable {
    static let initialBase: UInt32 = 0x110000
    static let prefixBase: UInt32 = 0x110100
    struct Posting: Sendable {
        var ids: [UInt32] = []
        var words: [UInt64] = []
        var bitmap = false
        var count = 0
        var bytes: Int { ids.capacity * 4 + words.capacity * 8 }
        mutating func append(_ id: UInt32) {
            count += 1
            let word = Int(id) / 64
            if !bitmap, (word + 1) * 8 < (ids.count + 1) * 4 {
                words = [UInt64](repeating: 0, count: word + 1)
                for old in ids { words[Int(old) / 64] |= 1 << (old % 64) }
                ids = []
                bitmap = true
            }
            if bitmap {
                if words.count <= word { words.append(contentsOf: repeatElement(0, count: word + 1 - words.count)) }
                words[word] |= 1 << (id % 64)
            } else { ids.append(id) }
        }
        func contains(_ id: UInt32) -> Bool {
            if bitmap { return Int(id) / 64 < words.count && words[Int(id) / 64] & (1 << (id % 64)) != 0 }
            var lo = 0, hi = ids.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if ids[mid] < id { lo = mid + 1 } else { hi = mid }
            }
            return lo < ids.count && ids[lo] == id
        }
    }
    var budget = 64 * 1024 * 1024
    private var postings: [UInt32: Posting] = [:]
    private var evicted: Set<UInt32> = []
    private var disabled = false
    private var storageBytes = 0
    var estimatedBytes: Int {
        storageBytes + postings.capacity * 96 + evicted.capacity * 16
    }

    mutating func append(_ name: String, id: UInt32) {
        guard !disabled else { return }
        var keys: Set<UInt32> = []
        for scalar in name.unicodeScalars {
            let s = scalar.value
            keys.insert(s &- 65 < 26 ? s + 32 : s)
            if let initial = HangulText.choseongIndex(syllable: s) {
                keys.insert(Self.initialBase + UInt32(initial))
                keys.insert(Self.prefixBase + HangulText.choseongJungseong(s)!)
            } else if let initial = HangulText.choseongIndex(jamo: s) {
                keys.insert(Self.initialBase + UInt32(initial))
            }
        }
        for key in keys where !evicted.contains(key) {
            let before = postings[key]?.bytes ?? 0
            postings[key, default: Posting()].append(id)
            storageBytes += postings[key]!.bytes - before
        }
        if estimatedBytes > budget {
            for key in postings.keys.sorted(by: { postings[$0]!.bytes > postings[$1]!.bytes }) {
                guard estimatedBytes > budget else { break }
                storageBytes -= postings.removeValue(forKey: key)!.bytes
                evicted.insert(key)
            }
            // Bound even adversarial Unicode key metadata. Disable filtering safely.
            if estimatedBytes > budget {
                postings = [:]; evicted = []; disabled = true; storageBytes = 0
            }
        }
    }

    func candidates(for matchers: [NameMatcher]) -> [UInt32]? {
        guard !disabled else { return nil }
        var keys: Set<UInt32> = []
        for matcher in matchers {
            for (position, unit) in matcher.units.enumerated() {
                if position & 1023 == 0, Task.isCancelled { return [] }
                switch unit.kind {
                case .literal: keys.insert(unit.value)
                case .choseong: keys.insert(Self.initialBase + unit.choseong)
                case .syllablePrefix: keys.insert(Self.prefixBase + unit.value)
                }
            }
        }
        var available: [Posting] = []
        for key in keys where !evicted.contains(key) {
            guard let posting = postings[key] else { return [] }
            available.append(posting)
        }
        available.sort { $0.count < $1.count }
        guard let first = available.first else { return nil }
        var result: [UInt32] = []
        if first.bitmap {
            for (i, value) in first.words.enumerated() {
                if i & 1023 == 0, Task.isCancelled { return [] }
                var word = value
                for posting in available.dropFirst() where posting.bitmap {
                    word &= i < posting.words.count ? posting.words[i] : 0
                }
                while word != 0 {
                    result.append(UInt32(i * 64 + word.trailingZeroBitCount))
                    word &= word - 1
                }
            }
        } else { result = first.ids }
        for posting in available.dropFirst() where !first.bitmap || !posting.bitmap {
            var write = 0
            for i in result.indices {
                if i & 1023 == 0, Task.isCancelled { return [] }
                if posting.contains(result[i]) { result[write] = result[i]; write += 1 }
            }
            result.removeLast(result.count - write)
            if result.isEmpty { break }
        }
        return result
    }
}
