import Foundation

/// 파일 찾기 결과에서 체크한 항목들. 검색어가 바뀌어도 남도록 인덱스 번호가 아니라 경로(NFC)를 키로 쓴다
///
/// 인덱스 번호는 `FileIndex.compact()`가 다시 매기므로 오래 들고 있다가 쓰면 다른 파일을 가리킬 수 있다
public struct PathSelection: Sendable, Equatable {
    public struct Item: Sendable, Hashable {
        public let path: String
        public let isDirectory: Bool
        public let isPackage: Bool

        public init(path: String, isDirectory: Bool, isPackage: Bool = false) {
            self.path = HangulText.nfc(path)
            self.isDirectory = isDirectory
            self.isPackage = isPackage
        }
    }

    public enum ToggleResult: Sendable, Equatable {
        case added, removed, limitReached
    }

    /// 체크한 항목이 아닌데 체크한 조상 폴더 안에 들어 있으면 implied
    public enum Coverage: Sendable, Equatable {
        case none
        case explicit
        case implied(ancestor: String)
    }

    public static let defaultLimit = 10_000

    public let limit: Int
    private var items: [String: Item] = [:]
    /// 체크한 순서 (선택한 항목만 보기·확인 화면 순서)
    private var order: [String] = []

    public init(limit: Int = defaultLimit) {
        self.limit = limit
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var isFull: Bool { items.count >= limit }
    public var fileCount: Int { items.values.count { !$0.isDirectory } }
    public var folderCount: Int { items.values.count { $0.isDirectory } }

    /// 체크한 순서대로
    public var orderedItems: [Item] { order.compactMap { items[$0] } }

    public func contains(_ path: String) -> Bool {
        items[HangulText.nfc(path)] != nil
    }

    /// 넣는다. 이미 있으면 true, 상한에 닿았으면 false
    @discardableResult
    public mutating func insert(_ item: Item) -> Bool {
        if items[item.path] != nil { return true }
        guard items.count < limit else { return false }
        items[item.path] = item
        order.append(item.path)
        return true
    }

    /// 여러 개를 넣는다. 상한에 닿으면 나머지는 버린다
    @discardableResult
    public mutating func insert(contentsOf newItems: some Sequence<Item>) -> (added: Int, truncated: Bool) {
        var added = 0
        for item in newItems where items[item.path] == nil {
            guard insert(item) else { return (added, true) }
            added += 1
        }
        return (added, false)
    }

    /// 있으면 빼고 없으면 넣는다
    public mutating func toggle(_ item: Item) -> ToggleResult {
        if items[item.path] != nil {
            remove(item.path)
            return .removed
        }
        return insert(item) ? .added : .limitReached
    }

    public mutating func remove(_ path: String) {
        let key = HangulText.nfc(path)
        guard items.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    /// 여러 경로를 뺀다. includingDescendants면 그 아래 항목도 뺀다 (휴지통으로 옮긴 폴더의 안쪽 체크)
    public mutating func remove(paths: some Sequence<String>, includingDescendants: Bool) {
        let removed = Set(paths.map(HangulText.nfc))
        guard !removed.isEmpty else { return }
        let gone = { (path: String) in
            removed.contains(path) || (includingDescendants && Self.ancestors(of: path).contains { removed.contains($0) })
        }
        let before = items.count
        items = items.filter { !gone($0.key) }
        if items.count != before { order.removeAll { items[$0] == nil } }
    }

    public mutating func removeAll() {
        items.removeAll()
        order.removeAll()
    }

    /// 경로가 직접 체크됐는지, 체크한 조상 폴더 안에 있는지
    public func coverage(of path: String) -> Coverage {
        let key = HangulText.nfc(path)
        if items[key] != nil { return .explicit }
        for ancestor in Self.ancestors(of: key) where items[ancestor]?.isDirectory == true {
            return .implied(ancestor: ancestor)
        }
        return .none
    }

    /// 조상 폴더가 함께 체크된 항목을 빼고 남은 것 (체크한 순서). 폴더를 지우면 안쪽은 따라가므로 따로 셀 필요가 없다
    ///
    /// 경로를 정렬해 스택으로 거르면 `a-b`가 `a`와 `a/b` 사이에 오는 문제가 있어(`-` < `/`)
    /// 얕은 항목부터 보며 남긴 폴더 집합에 조상이 있는지 확인한다
    public func collapsedRoots() -> [Item] {
        var keptFolders = Set<String>()
        var kept = Set<String>()
        for item in items.values.sorted(by: { Self.depth($0.path) < Self.depth($1.path) }) {
            if Self.ancestors(of: item.path).contains(where: keptFolders.contains) { continue }
            kept.insert(item.path)
            if item.isDirectory { keptFolders.insert(item.path) }
        }
        return orderedItems.filter { kept.contains($0.path) }
    }

    // MARK: - 경로 도우미

    /// 가까운 쪽부터 조상 경로들 (`/a/b/c` → `/a/b`, `/a`, `/`)
    static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = Substring(path)
        while let slash = current.lastIndex(of: "/") {
            if slash == current.startIndex {
                if current.count > 1 { result.append("/") }
                break
            }
            current = current[..<slash]
            result.append(String(current))
        }
        return result
    }

    // 경로 깊이 (구분자 수, 루트 `/`는 0)
    static func depth(_ path: String) -> Int {
        path == "/" ? 0 : path.utf8.count { $0 == UInt8(ascii: "/") }
    }
}
