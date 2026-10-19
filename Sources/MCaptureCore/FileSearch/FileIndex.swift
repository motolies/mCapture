import Foundation

/// 파일 찾기 인덱스. 항목마다 String을 만들지 않고 배열을 나란히 두어(SoA) 100만 개 규모를 수십 MB로 담는다
///
/// - 이름은 NFC UTF-8 바이트를 한 버퍼에 이어 붙이고 오프셋으로 자른다. 루트 항목의 이름은 절대 경로다
/// - 부모 번호는 늘 자식 번호보다 작다(`parents[i] < i`). 그래서 앞에서부터 한 번 훑으면 부모 정보를 먼저 계산해 둘 수 있다
/// - 삭제는 묘비(removed)로 표시하고, 쌓이면 `compact()`로 번호를 다시 매긴다
/// - 값 타입이라 검색 쪽에 넘기면 쓰기 전까지 배열을 공유한다(COW)
public struct FileIndex: Sendable {
    public struct Flags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let directory = Flags(rawValue: 1 << 0)
        /// .app 같은 패키지. 안은 색인하지 않는다
        public static let package = Flags(rawValue: 1 << 1)
        public static let symlink = Flags(rawValue: 1 << 2)
        /// 이름이 .으로 시작
        public static let hidden = Flags(rawValue: 1 << 3)
        /// 삭제됨 (묘비)
        public static let removed = Flags(rawValue: 1 << 4)
        public static let root = Flags(rawValue: 1 << 5)
        /// 제외 규칙이나 패키지라 안을 색인하지 않은 디렉터리
        public static let unindexed = Flags(rawValue: 1 << 6)
    }

    /// 부모 없음, 자식·형제 없음
    public static let none = UInt32.max

    private(set) var names: [UInt8] = []
    private(set) var nameOffsets: [UInt32] = [0]
    private(set) var parents: [UInt32] = []
    private(set) var flagBits: [UInt8] = []
    // 아래 두 배열은 쓰기 쪽 탐색(자식 목록·경로 조회·하위 트리 삭제)용이라 파일에 저장하지 않고 로드할 때 다시 만든다
    private var firstChild: [UInt32] = []
    private var nextSibling: [UInt32] = []
    /// 살아 있는 루트 번호들 (추가한 순서)
    public private(set) var roots: [UInt32] = []
    public private(set) var removedCount = 0

    public init() {}

    /// 묘비를 포함한 전체 항목 수
    public var count: Int { parents.count }

    /// 살아 있는 항목 수
    public var liveCount: Int { count - removedCount }

    /// 이름 버퍼 바이트 수 (메모리·평균 이름 길이 측정용)
    public var nameByteCount: Int { names.count }

    /// 대략의 메모리 사용량 (배열 용량 기준)
    public var estimatedBytes: Int {
        names.capacity + (nameOffsets.capacity + parents.capacity + firstChild.capacity + nextSibling.capacity) * 4 + flagBits.capacity
    }

    // MARK: - 추가

    /// 루트를 추가한다. 이름은 절대 경로
    @discardableResult
    public mutating func appendRoot(path: String, flags: Flags = [.directory]) -> UInt32 {
        let id = append(name: path, parent: Self.none, flags: flags.union(.root))
        roots.append(id)
        return id
    }

    /// 항목을 추가하고 번호를 돌려준다. 부모는 이미 있어야 한다
    @discardableResult
    public mutating func append(name: String, parent: UInt32, flags: Flags) -> UInt32 {
        precondition(parent == Self.none || Int(parent) < count, "부모가 먼저 있어야 한다")
        let id = UInt32(count)
        names.append(contentsOf: HangulText.nfc(name).utf8)
        nameOffsets.append(UInt32(names.count))
        parents.append(parent)
        flagBits.append(flags.rawValue)
        firstChild.append(Self.none)
        if parent != Self.none {
            nextSibling.append(firstChild[Int(parent)])
            firstChild[Int(parent)] = id
        } else {
            nextSibling.append(Self.none)
        }
        return id
    }

    /// 용량을 미리 잡는다 (스캔 전에 예상 항목 수를 알 때)
    public mutating func reserveCapacity(entries: Int, nameBytes: Int) {
        names.reserveCapacity(nameBytes)
        nameOffsets.reserveCapacity(entries + 1)
        parents.reserveCapacity(entries)
        flagBits.reserveCapacity(entries)
        firstChild.reserveCapacity(entries)
        nextSibling.reserveCapacity(entries)
    }

    // MARK: - 읽기

    public func parent(of id: UInt32) -> UInt32 { parents[Int(id)] }

    public func flags(of id: UInt32) -> Flags { Flags(rawValue: flagBits[Int(id)]) }

    public func isRemoved(_ id: UInt32) -> Bool { flags(of: id).contains(.removed) }

    /// 항목 이름 (루트는 절대 경로)
    public func name(of id: UInt32) -> String {
        let range = byteRange(of: id)
        return String(decoding: names[range], as: UTF8.self)
    }

    /// 이름 바이트 범위
    func byteRange(of id: UInt32) -> Range<Int> {
        Int(nameOffsets[Int(id)])..<Int(nameOffsets[Int(id) + 1])
    }

    /// 전체 경로
    public func path(of id: UInt32) -> String {
        var components: [String] = []
        var current = id
        while current != Self.none {
            components.append(name(of: current))
            current = parents[Int(current)]
        }
        guard var path = components.popLast() else { return "" }
        for component in components.reversed() {
            if !path.hasSuffix("/") { path += "/" }
            path += component
        }
        return path
    }

    /// 루트까지의 깊이 (루트 = 0)
    public func depth(of id: UInt32) -> Int {
        var depth = 0
        var current = parents[Int(id)]
        while current != Self.none {
            depth += 1
            current = parents[Int(current)]
        }
        return depth
    }

    /// 살아 있는 자식 번호들
    public func children(of id: UInt32) -> [UInt32] {
        var result: [UInt32] = []
        var child = firstChild[Int(id)]
        while child != Self.none {
            if !isRemoved(child) { result.append(child) }
            child = nextSibling[Int(child)]
        }
        return result
    }

    /// 이름이 정확히 같은(NFC 바이트) 살아 있는 자식
    public func child(of id: UInt32, named name: String) -> UInt32? {
        let target = Array(HangulText.nfc(name).utf8)
        var child = firstChild[Int(id)]
        while child != Self.none {
            if !isRemoved(child), names[byteRange(of: child)].elementsEqual(target) { return child }
            child = nextSibling[Int(child)]
        }
        return nil
    }

    /// 절대 경로로 항목을 찾는다. 가장 긴 루트부터 맞춰 보고 구성 요소를 따라 내려간다
    public func lookup(path: String) -> UInt32? {
        let path = HangulText.nfc(path)
        let candidates = roots.map { ($0, name(of: $0)) }.sorted { $0.1.count > $1.1.count }
        for (root, rootPath) in candidates {
            let rest: Substring
            if path == rootPath {
                return root
            } else if rootPath.hasSuffix("/"), path.hasPrefix(rootPath) {
                rest = path.dropFirst(rootPath.count)
            } else if path.hasPrefix(rootPath + "/") {
                rest = path.dropFirst(rootPath.count + 1)
            } else {
                continue
            }
            var current = root
            for component in rest.split(separator: "/") {
                guard let next = child(of: current, named: String(component)) else { return nil }
                current = next
            }
            return current
        }
        return nil
    }

    // MARK: - 삭제·변경

    /// 플래그를 바꾼다 (디렉터리가 제외 규칙에 들어가게 된 경우 등)
    public mutating func setFlags(_ flags: Flags, of id: UInt32) {
        flagBits[Int(id)] = flags.rawValue
    }

    /// 항목과 모든 자손을 묘비로 표시하고 부모의 자식 목록에서 뺀다
    public mutating func removeSubtree(_ id: UInt32) {
        guard !isRemoved(id) else { return }
        unlink(id)
        roots.removeAll { $0 == id }
        var stack = [id]
        while let current = stack.popLast() {
            if !isRemoved(current) {
                flagBits[Int(current)] |= Flags.removed.rawValue
                removedCount += 1
            }
            var child = firstChild[Int(current)]
            while child != Self.none {
                stack.append(child)
                child = nextSibling[Int(child)]
            }
        }
    }

    /// 자식들만 지운다 (하위 트리를 다시 스캔하기 전)
    public mutating func removeChildren(of id: UInt32) {
        for child in children(of: id) {
            removeSubtree(child)
        }
    }

    // 부모의 자식 목록에서 항목을 뺀다
    private mutating func unlink(_ id: UInt32) {
        let parent = parents[Int(id)]
        guard parent != Self.none else { return }
        if firstChild[Int(parent)] == id {
            firstChild[Int(parent)] = nextSibling[Int(id)]
            return
        }
        var previous = firstChild[Int(parent)]
        while previous != Self.none {
            let next = nextSibling[Int(previous)]
            if next == id {
                nextSibling[Int(previous)] = nextSibling[Int(id)]
                return
            }
            previous = next
        }
    }

    /// 묘비 비율이 높으면 압축할 때다
    public var needsCompaction: Bool {
        removedCount > 50_000 || (removedCount > 1_000 && removedCount * 20 > count)
    }

    /// 묘비를 걷어 내고 번호를 다시 매긴다. 순서를 지키므로 parents[i] < i가 유지된다
    /// 이전 번호는 모두 무효가 된다
    public mutating func compact() {
        guard removedCount > 0 else { return }
        var remap = [UInt32](repeating: Self.none, count: count)
        var compacted = FileIndex()
        compacted.reserveCapacity(entries: liveCount, nameBytes: names.count)
        for i in 0..<count where flagBits[i] & Flags.removed.rawValue == 0 {
            let parent = parents[i]
            let newParent = parent == Self.none ? Self.none : remap[Int(parent)]
            remap[i] = UInt32(compacted.count)
            compacted.names.append(contentsOf: names[byteRange(of: UInt32(i))])
            compacted.nameOffsets.append(UInt32(compacted.names.count))
            compacted.parents.append(newParent)
            compacted.flagBits.append(flagBits[i])
        }
        compacted.rebuildLinks()
        compacted.roots = roots.map { remap[Int($0)] }
        self = compacted
    }

    /// parents에서 자식·형제 연결을 다시 만든다 (로드·압축 뒤)
    mutating func rebuildLinks() {
        firstChild = [UInt32](repeating: Self.none, count: count)
        nextSibling = [UInt32](repeating: Self.none, count: count)
        for i in stride(from: count - 1, through: 0, by: -1) where flagBits[i] & Flags.removed.rawValue == 0 {
            let parent = parents[i]
            guard parent != Self.none else { continue }
            nextSibling[i] = firstChild[Int(parent)]
            firstChild[Int(parent)] = UInt32(i)
        }
    }

    // MARK: - 검색·직렬화용 저수준 접근

    /// 배열을 직접 읽는다 (검색 루프와 스냅샷 저장용)
    func withStorage<R>(_ body: (_ names: UnsafeBufferPointer<UInt8>, _ offsets: UnsafeBufferPointer<UInt32>,
                                 _ parents: UnsafeBufferPointer<UInt32>, _ flags: UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try names.withUnsafeBufferPointer { names in
            try nameOffsets.withUnsafeBufferPointer { offsets in
                try parents.withUnsafeBufferPointer { parents in
                    try flagBits.withUnsafeBufferPointer { flags in
                        try body(names, offsets, parents, flags)
                    }
                }
            }
        }
    }

    /// 저장된 배열로 인덱스를 다시 만든다. 불변식이 깨졌으면 nil
    init?(names: [UInt8], nameOffsets: [UInt32], parents: [UInt32], flags: [UInt8]) {
        let count = parents.count
        guard nameOffsets.count == count + 1, flags.count == count, nameOffsets.first == 0,
              nameOffsets.last.map({ Int($0) == names.count }) == true
        else { return nil }
        var removed = 0
        for i in 0..<count {
            guard nameOffsets[i] <= nameOffsets[i + 1] else { return nil }
            let parent = parents[i]
            guard parent == Self.none || Int(parent) < i else { return nil }
            if flags[i] & Flags.removed.rawValue != 0 {
                removed += 1
            } else if flags[i] & Flags.root.rawValue != 0 {
                roots.append(UInt32(i))
            }
        }
        self.names = names
        self.nameOffsets = nameOffsets
        self.parents = parents
        self.flagBits = flags
        self.removedCount = removed
        rebuildLinks()
    }
}
