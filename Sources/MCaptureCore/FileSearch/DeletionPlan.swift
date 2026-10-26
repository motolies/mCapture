import Foundation

/// 파일 하나를 가리키는 식별자. 확인한 뒤 같은 경로가 다른 파일로 바뀌었는지 실행 직전에 비교한다
public struct FileIdentity: Sendable, Hashable {
    public let device: UInt64
    public let inode: UInt64
    public let isDirectory: Bool

    public init(device: UInt64, inode: UInt64, isDirectory: Bool) {
        self.device = device
        self.inode = inode
        self.isDirectory = isDirectory
    }
}

/// 확인 화면을 만들 때 파일 시스템에서 읽은 항목 상태
public struct FileProbe: Sendable, Equatable {
    /// 없으면 nil
    public let identity: FileIdentity?
    /// 잠긴 파일 (Finder "잠금", uchg/schg)
    public let isLocked: Bool
    /// iCloud 같은 클라우드 동기화 항목
    public let isUbiquitous: Bool

    public init(identity: FileIdentity?, isLocked: Bool = false, isUbiquitous: Bool = false) {
        self.identity = identity
        self.isLocked = isLocked
        self.isUbiquitous = isUbiquitous
    }

    public static let missing = FileProbe(identity: nil)
}

/// 확인 단계 기준
public struct DeletionPolicy: Sendable {
    /// 옮길 항목이 이만큼이면 개수 입력 확인을 더한다
    public var countConfirmEntries = 100
    /// 폴더 안 항목(인덱스로 센 하한)이 이만큼이면 개수 입력 확인을 더한다
    public var countConfirmContained = 10_000

    public init() {}
}

/// 휴지통으로 옮길 계획: 조상만 남기고, 지울 수 없는 항목을 빼고, 확인을 몇 단계 거칠지 정한다
///
/// 파일 시스템 상태(`FileProbe`)와 인덱스 통계는 밖에서 넘겨받아 순수 함수로 계산한다 (가짜 값으로 테스트)
public struct DeletionPlan: Sendable {
    public struct Entry: Sendable, Equatable {
        public let path: String
        public let isDirectory: Bool
        /// 확인할 때의 식별자. 실행 직전에 다시 읽어 다르면 건너뛴다
        public let identity: FileIdentity
        /// 인덱스로 센 안쪽 항목 수 (폴더, 하한)
        public let contained: Int
        /// 안을 색인하지 않은 폴더가 들어 있어 실제로는 더 많을 수 있다
        public let hasUnindexed: Bool
    }

    public enum Exclusion: Sendable, Equatable {
        case blocked(DeletionGuard.Reason)
        case missing
        case locked
        case cloud

        /// 확인 화면에 보일 이유
        public var message: String {
            switch self {
            case .blocked(let reason): reason.message
            case .missing: "이미 없습니다"
            case .locked: "잠긴 파일입니다"
            case .cloud: "클라우드 항목입니다"
            }
        }
    }

    public struct Excluded: Sendable, Equatable {
        public let path: String
        public let reason: Exclusion
    }

    /// 많이 든 위치 (부모 폴더별 항목 수, 안쪽 포함)
    public struct Location: Sendable, Equatable {
        public let folder: String
        public let count: Int
    }

    public let entries: [Entry]
    public let excluded: [Excluded]
    /// 체크한 폴더 안에 들어 있어 따로 세지 않은 체크 수
    public let coveredCount: Int
    /// 개수 입력 확인이 필요한지
    public let requiresCountConfirmation: Bool

    public var fileCount: Int { entries.count { !$0.isDirectory } }
    public var folderCount: Int { entries.count { $0.isDirectory } }
    /// 폴더 안 항목 합 (하한)
    public var containedTotal: Int { entries.reduce(0) { $0 + $1.contained } }
    public var hasUnindexed: Bool { entries.contains { $0.hasUnindexed } }

    /// 체크한 항목으로 계획을 만든다
    /// - probe: 경로의 실제 상태, stats: 인덱스로 센 하위 트리 (없으면 nil), fromAllMatches: 일치 전체 선택으로 고름
    public static func make(selection: PathSelection, guardian: DeletionGuard,
                            probe: (String) -> FileProbe, stats: (String) -> FileIndex.SubtreeStats?,
                            fromAllMatches: Bool, policy: DeletionPolicy = DeletionPolicy()) -> DeletionPlan {
        let roots = selection.collapsedRoots()
        var entries: [Entry] = []
        var excluded: [Excluded] = []
        for item in roots {
            if let reason = guardian.reason(path: item.path) {
                excluded.append(Excluded(path: item.path, reason: .blocked(reason)))
                continue
            }
            let state = probe(item.path)
            guard let identity = state.identity else {
                excluded.append(Excluded(path: item.path, reason: .missing))
                continue
            }
            let reason: Exclusion? = state.isUbiquitous ? .cloud : state.isLocked ? .locked : nil
            if let reason {
                excluded.append(Excluded(path: item.path, reason: reason))
                continue
            }
            let tree = identity.isDirectory ? stats(item.path) : nil
            entries.append(Entry(path: item.path, isDirectory: identity.isDirectory, identity: identity,
                                 contained: tree?.total ?? 0, hasUnindexed: (tree?.unindexedDirectories ?? 0) > 0))
        }
        let contained = entries.reduce(0) { $0 + $1.contained }
        let needsCount = !entries.isEmpty
            && (entries.count >= policy.countConfirmEntries || contained >= policy.countConfirmContained || fromAllMatches)
        return DeletionPlan(entries: entries, excluded: excluded, coveredCount: selection.count - roots.count,
                            requiresCountConfirmation: needsCount)
    }

    /// 확인 화면 미리보기 순서: 안의 항목이 많은 폴더부터, 같으면 체크한 순서 (영향이 큰 것을 위로)
    public var preview: [Entry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.contained != rhs.element.contained ? lhs.element.contained > rhs.element.contained : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// 많이 든 위치 상위 limit개 (부모 폴더별 1 + 안쪽 항목 수)
    public func topLocations(limit: Int = 3) -> [Location] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for entry in entries {
            let folder = (entry.path as NSString).deletingLastPathComponent
            if counts[folder] == nil { order.append(folder) }
            counts[folder, default: 0] += 1 + entry.contained
        }
        return order.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (counts[lhs.element]!, counts[rhs.element]!)
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map { Location(folder: $0.element, count: counts[$0.element]!) }
    }
}
