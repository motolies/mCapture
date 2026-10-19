import Foundation

/// 스캔 결과 요약 (로그·설정 표시용)
public struct ScanReport: Sendable {
    /// 색인한 항목 수 (루트 제외)
    public var entries = 0
    public var directories = 0
    /// 목록을 읽지 못한 디렉터리 (대부분 권한 거부)
    public var deniedPaths: [String] = []
    /// 없어서 건너뛴 루트
    public var missingRoots: [String] = []
    public var elapsed: Duration = .zero

    public init() {}

    /// 다른 스캔 결과를 더한다
    public mutating func merge(_ other: ScanReport) {
        entries += other.entries
        directories += other.directories
        deniedPaths += other.deniedPaths
        missingRoots += other.missingRoots
        elapsed += other.elapsed
    }
}

/// 디렉터리 트리를 훑어 인덱스를 만든다. 동기 I/O라 협력 스레드 풀이 아닌 전용 큐에서 부른다
///
/// - 패키지(.app 등)는 항목만 넣고 안은 건너뛴다
/// - 숨김은 이름이 .으로 시작하는지만 본다. `.skipsHiddenFiles`는 UF_HIDDEN 플래그가 붙은 ~/Library까지 빼므로 쓰지 않는다
/// - 심볼릭 링크는 따라가지 않는다 (순환·중복 방지)
/// - 권한이 없는 디렉터리는 항목만 남기고 경로를 기록한다
public enum FileTreeScanner {
    static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
    /// 거부 경로를 이보다 많이 모으지 않는다
    static let deniedLimit = 1000

    /// 루트들을 처음부터 스캔해 새 인덱스를 만든다. 없는 루트는 건너뛴다
    public static func scan(roots: [String], rules: ExclusionRules,
                            progress: (Int) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> (index: FileIndex, report: ScanReport) {
        let start = ContinuousClock.now
        var index = FileIndex()
        var report = ScanReport()
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                report.missingRoots.append(root)
                continue
            }
            let rootID = index.appendRoot(path: HangulText.nfc(root))
            scanContents(of: rootID, path: root, into: &index, rules: rules, report: &report, progress: progress, isCancelled: isCancelled)
            if isCancelled() { break }
        }
        report.elapsed = ContinuousClock.now - start
        return (index, report)
    }

    /// 디렉터리 하나 아래를 새로 스캔한 작은 인덱스를 돌려준다 (루트 = 그 디렉터리). 큰 인덱스에는 graft로 붙인다
    public static func scanSubtree(path: String, rules: ExclusionRules) -> (index: FileIndex, report: ScanReport) {
        let start = ContinuousClock.now
        var index = FileIndex()
        var report = ScanReport()
        let rootID = index.appendRoot(path: HangulText.nfc(path))
        scanContents(of: rootID, path: path, into: &index, rules: rules, report: &report, progress: { _ in }, isCancelled: { false })
        report.elapsed = ContinuousClock.now - start
        return (index, report)
    }

    // 디렉터리 아래를 깊이 우선으로 훑어 인덱스에 추가한다. 1000개마다 autorelease 풀을 비워 URL 객체가 쌓이지 않게 한다
    private static func scanContents(of directoryID: UInt32, path: String, into index: inout FileIndex, rules: ExclusionRules,
                                     report: inout ScanReport, progress: (Int) -> Void, isCancelled: () -> Bool) {
        let denied = DeniedPaths()
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { url, _ in
                denied.append(url.path)
                return true
            })
        else { return }

        // level(1부터)마다 부모 번호와 경로. 경로는 경로 규칙을 비교할 때만 쓴다
        var parentIDs: [UInt32] = [directoryID]
        var parentPaths: [String] = [HangulText.nfc(path)]
        var finished = false
        while !finished {
            autoreleasepool {
                for _ in 0..<1000 {
                    guard let item = enumerator.nextObject() as? URL else {
                        finished = true
                        return
                    }
                    let level = enumerator.level
                    let name = item.lastPathComponent
                    if rules.skipsEntry(named: name) {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard level >= 1, level <= parentIDs.count else { continue }
                    parentIDs.removeSubrange(level...)
                    parentPaths.removeSubrange(level...)
                    let parentPath = parentPaths[level - 1]
                    let flags = entryFlags(name: name, values: try? item.resourceValues(forKeys: Set(resourceKeys)),
                                           path: { parentPath == "/" ? "/" + name : parentPath + "/" + name }, rules: rules)
                    if flags.contains(.unindexed) { enumerator.skipDescendants() }
                    let id = index.append(name: name, parent: parentIDs[level - 1], flags: flags)
                    report.entries += 1
                    if flags.contains(.directory) {
                        report.directories += 1
                        if !flags.contains(.unindexed) {
                            parentIDs.append(id)
                            parentPaths.append(parentPath == "/" ? "/" + name : parentPath + "/" + name)
                        }
                    }
                    if report.entries % 10_000 == 0 { progress(report.entries) }
                }
                if isCancelled() { finished = true }
            }
        }
        report.deniedPaths += denied.paths.prefix(max(0, deniedLimit - report.deniedPaths.count))
    }

    /// 항목 플래그를 정한다: 디렉터리·패키지·링크·숨김, 그리고 안을 색인하지 않을지(패키지·제외 규칙)
    static func entryFlags(name: String, values: URLResourceValues?, path: () -> String, rules: ExclusionRules) -> FileIndex.Flags {
        var flags: FileIndex.Flags = []
        if values?.isSymbolicLink == true { flags.insert(.symlink) }
        if name.hasPrefix(".") { flags.insert(.hidden) }
        if values?.isDirectory == true {
            flags.insert(.directory)
            if values?.isPackage == true {
                flags.formUnion([.package, .unindexed])
            } else if rules.excludesContents(name: HangulText.nfc(name), path: path) {
                flags.insert(.unindexed)
            }
        }
        return flags
    }

    /// 열거자 오류 콜백이 넘겨주는 경로를 모은다 (같은 스레드에서 동기로 불린다)
    private final class DeniedPaths: @unchecked Sendable {
        var paths: [String] = []

        func append(_ path: String) {
            if paths.count < deniedLimit { paths.append(path) }
        }
    }
}

/// FSEvents로 바뀐 디렉터리를 실제 목록과 맞춘다
///
/// 이벤트 종류(생성·삭제·이름 변경)를 믿지 않고 디렉터리를 다시 읽어 비교하므로,
/// 이벤트가 합쳐지거나, 대소문자만 바뀌거나, 경로가 NFD여도 결과가 같다. 여러 번 적용해도 같다(멱등)
public enum DirectoryReconciler {
    public struct ListedEntry: Sendable, Equatable {
        /// NFC 이름
        public let name: String
        public let flags: FileIndex.Flags
    }

    /// 디렉터리의 실제 목록을 읽는다 (I/O). 숨김 설정에 따라 점 이름은 뺀다
    public static func list(directory path: String, rules: ExclusionRules) throws -> [ListedEntry] {
        let items = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path, isDirectory: true),
                                                                includingPropertiesForKeys: FileTreeScanner.resourceKeys)
        let base = HangulText.nfc(path)
        return items.compactMap { item in
            let name = HangulText.nfc(item.lastPathComponent)
            guard !rules.skipsEntry(named: name) else { return nil }
            let flags = FileTreeScanner.entryFlags(name: name, values: try? item.resourceValues(forKeys: Set(FileTreeScanner.resourceKeys)),
                                                   path: { base == "/" ? "/" + name : base + "/" + name }, rules: rules)
            return ListedEntry(name: name, flags: flags)
        }
    }

    /// 인덱스의 자식들을 목록과 맞춘다. 없어진 것은 하위 트리째 지우고 새 것은 추가한다
    /// 안을 새로 스캔해야 하는 디렉터리 번호를 돌려준다 (새로 생겼거나 제외 규칙에서 풀린 디렉터리)
    public static func apply(_ listing: [ListedEntry], to directory: UInt32, in index: inout FileIndex) -> [UInt32] {
        var existing: [String: UInt32] = [:]
        for child in index.children(of: directory) {
            existing[index.name(of: child)] = child
        }
        var needsScan: [UInt32] = []
        for entry in listing {
            if let id = existing.removeValue(forKey: entry.name) {
                let old = index.flags(of: id)
                let sameKind = old.contains(.directory) == entry.flags.contains(.directory)
                    && old.contains(.symlink) == entry.flags.contains(.symlink)
                if sameKind {
                    if old.contains(.unindexed) != entry.flags.contains(.unindexed) {
                        index.removeChildren(of: id)
                        if entry.flags.contains(.directory), !entry.flags.contains(.unindexed) { needsScan.append(id) }
                    }
                    if old != entry.flags { index.setFlags(entry.flags, of: id) }
                    continue
                }
                index.removeSubtree(id)
            }
            let id = index.append(name: entry.name, parent: directory, flags: entry.flags)
            if entry.flags.contains(.directory), !entry.flags.contains(.unindexed) { needsScan.append(id) }
        }
        for id in existing.values {
            index.removeSubtree(id)
        }
        return needsScan
    }
}
