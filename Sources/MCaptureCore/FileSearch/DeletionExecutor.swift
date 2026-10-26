import Darwin
import Foundation

/// 휴지통 이동에 쓰는 파일 시스템 동작. 단위 테스트는 가짜를 넣어 사용자 휴지통을 건드리지 않는다
public protocol FileRemoving: Sendable {
    /// 경로의 식별자 (심볼릭 링크는 링크 자체). 없으면 nil
    func identity(of path: String) -> FileIdentity?
    func isUbiquitous(_ path: String) -> Bool
    func exists(_ path: String) -> Bool
    /// 휴지통으로 옮기고 휴지통 안 경로를 돌려준다
    func trash(_ path: String) throws -> String
    func move(_ source: String, to destination: String) throws
}

/// 실제 파일 시스템 (`FileManager.trashItem`)
public struct SystemFileRemover: FileRemoving {
    public init() {}

    // 심볼릭 링크를 따라가지 않도록 lstat로 읽는다
    public func identity(of path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino),
                            isDirectory: info.st_mode & S_IFMT == S_IFDIR)
    }

    public func isUbiquitous(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    public func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    public func trash(_ path: String) throws -> String {
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        return (result as URL?)?.path ?? path
    }

    public func move(_ source: String, to destination: String) throws {
        try FileManager.default.moveItem(atPath: source, toPath: destination)
    }

    /// 확인 화면용 상태: 식별자·잠금(uchg/schg)·클라우드
    public func probe(_ path: String) -> FileProbe {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        let identity = FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino),
                                    isDirectory: info.st_mode & S_IFMT == S_IFDIR)
        let locked = info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE) != 0
        return FileProbe(identity: identity, isLocked: locked, isUbiquitous: isUbiquitous(path))
    }
}

/// 휴지통으로 옮기지 못한 이유
public enum DeletionFailure: Sendable, Equatable {
    case permissionDenied
    case readOnly
    case inUse
    case notFound
    case noTrash
    case other(String)

    /// 파일 시스템 오류를 나눈다 (Cocoa 코드, 아니면 POSIX 코드)
    public init(error: Error) {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                self = .permissionDenied
                return
            case NSFileWriteVolumeReadOnlyError:
                self = .readOnly
                return
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                self = .notFound
                return
            case NSFeatureUnsupportedError:
                self = .noTrash
                return
            default:
                break
            }
        }
        let posix = error.domain == NSPOSIXErrorDomain ? error : error.userInfo[NSUnderlyingErrorKey] as? NSError
        if let posix, posix.domain == NSPOSIXErrorDomain {
            switch Int32(posix.code) {
            case EACCES, EPERM: self = .permissionDenied
            case EROFS: self = .readOnly
            case EBUSY: self = .inUse
            case ENOENT: self = .notFound
            default: self = .other(error.localizedDescription)
            }
            return
        }
        self = .other(error.localizedDescription)
    }

    /// 사용자에게 보일 이유
    public var message: String {
        switch self {
        case .permissionDenied: "권한 없음 (Finder에서 관리자 암호로 지우세요)"
        case .readOnly: "읽기 전용 위치"
        case .inUse: "다른 앱이 사용 중"
        case .notFound: "이미 없음"
        case .noTrash: "휴지통을 쓸 수 없는 위치"
        case .other(let text): text
        }
    }
}

/// 휴지통 이동 결과
public struct DeletionReport: Sendable, Equatable {
    public struct Trashed: Sendable, Equatable {
        public let original: String
        /// 휴지통 안 경로 (되돌리기에 쓴다)
        public let trashed: String
    }

    public struct Failed: Sendable, Equatable {
        public let path: String
        public let failure: DeletionFailure
    }

    public enum SkipReason: Sendable, Equatable {
        /// 확인한 뒤 사라짐
        case missing
        /// 확인한 뒤 같은 이름의 다른 파일로 바뀜
        case changed
        /// 클라우드 동기화 항목
        case cloud
    }

    public struct Skipped: Sendable, Equatable {
        public let path: String
        public let reason: SkipReason
    }

    public var trashed: [Trashed] = []
    public var failed: [Failed] = []
    public var skipped: [Skipped] = []
    /// 중지해서 손대지 않은 항목 수
    public var cancelledRemaining = 0

    public init() {}

    /// 휴지통으로 옮긴 원래 경로들
    public var trashedPaths: [String] { trashed.map(\.original) }
}

/// 되돌리기 결과
public struct RestoreReport: Sendable, Equatable {
    public var restored: [String] = []
    /// 원래 자리에 같은 이름이 있어 휴지통에 남긴 항목
    public var conflicts: [String] = []
    public var failed: [String] = []

    public init() {}
}

/// 계획대로 휴지통으로 옮기고, 마지막 묶음을 되돌린다
public enum DeletionExecutor {
    /// 순서대로 휴지통으로 옮긴다. 취소는 항목 사이에서만 보고(이동 하나는 원자적), progress는 (끝낸 수, 전체)
    /// 실행 직전에 식별자를 다시 읽어 확인한 뒤 사라졌거나 다른 파일로 바뀐 항목은 건너뛴다
    public static func run(_ entries: [DeletionPlan.Entry], remover: some FileRemoving,
                           isCancelled: () -> Bool = { false }, progress: (Int, Int) -> Void = { _, _ in }) -> DeletionReport {
        var report = DeletionReport()
        for (index, entry) in entries.enumerated() {
            if isCancelled() {
                report.cancelledRemaining = entries.count - index
                break
            }
            defer { progress(index + 1, entries.count) }
            guard let current = remover.identity(of: entry.path) else {
                report.skipped.append(.init(path: entry.path, reason: .missing))
                continue
            }
            guard current == entry.identity else {
                report.skipped.append(.init(path: entry.path, reason: .changed))
                continue
            }
            if remover.isUbiquitous(entry.path) {
                report.skipped.append(.init(path: entry.path, reason: .cloud))
                continue
            }
            do {
                let trashed = try remover.trash(entry.path)
                report.trashed.append(.init(original: entry.path, trashed: trashed))
            } catch {
                let failure = DeletionFailure(error: error)
                if failure == .notFound {
                    report.skipped.append(.init(path: entry.path, reason: .missing))
                } else {
                    report.failed.append(.init(path: entry.path, failure: failure))
                }
            }
        }
        return report
    }

    /// 휴지통으로 옮긴 항목을 원래 자리로 되돌린다. 원래 자리가 차 있으면 휴지통에 남긴다
    public static func restore(_ items: [DeletionReport.Trashed], remover: some FileRemoving) -> RestoreReport {
        var report = RestoreReport()
        for item in items {
            if remover.exists(item.original) {
                report.conflicts.append(item.original)
                continue
            }
            guard remover.exists(item.trashed) else {
                report.failed.append(item.original)
                continue
            }
            do {
                try remover.move(item.trashed, to: item.original)
                report.restored.append(item.original)
            } catch {
                report.failed.append(item.original)
            }
        }
        return report
    }
}
