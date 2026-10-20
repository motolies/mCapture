import Foundation

/// 파일 찾기 제외 규칙. 규칙에 맞는 폴더는 폴더 자체는 검색되고 안은 색인하지 않는다
///
/// 설정의 한 줄이 규칙 하나다. `/`나 `~`로 시작하면 경로 규칙, 아니면 어느 깊이에서든 맞는 이름 규칙이다.
/// 빈 줄과 `#`으로 시작하는 줄은 무시한다
public struct ExclusionRules: Sendable, Equatable {
    /// 이름 규칙 (NFC)
    public let names: Set<String>
    /// 경로 규칙 (~를 확장한 절대 경로, 끝의 / 없음)
    public let paths: [String]
    /// 경로 규칙의 마지막 구성 요소. 스캔 중 이름이 맞을 때만 전체 경로를 만들어 비교한다
    public let pathNames: Set<String>
    /// 이름이 .으로 시작하는 항목을 색인할지
    public let includeHidden: Bool

    /// 기본 제외 규칙 (설정 "기본값" 버튼)
    /// Cache·Code Cache·CacheStorage·Service Worker·GPUCache는 Application Support 아래 Chromium·Electron 앱 캐시다.
    /// 실측(2026-10-19)에서 ~/Library/Application Support 10만 개 중 9만 개를 차지했다. ~/Library/pnpm은 pnpm 패키지 저장소
    public static let defaultText = """
        node_modules
        .git
        .svn
        .hg
        DerivedData
        __pycache__
        .build
        Cache
        Code Cache
        CacheStorage
        Service Worker
        GPUCache
        ~/.Trash
        ~/Library/Caches
        ~/Library/Logs
        ~/Library/Containers
        ~/Library/Group Containers
        ~/Library/CloudStorage
        ~/Library/pnpm
        """

    /// 설정 문자열(한 줄에 규칙 하나)로 만든다
    public init(text: String, home: String, includeHidden: Bool) {
        var names: Set<String> = []
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let rule = HangulText.nfc(line.trimmingCharacters(in: .whitespaces))
            guard !rule.isEmpty, !rule.hasPrefix("#") else { continue }
            if rule.hasPrefix("/") || rule.hasPrefix("~") {
                paths.append(Self.normalizedPath(rule, home: home))
            } else {
                names.insert(rule)
            }
        }
        self.names = names
        self.paths = paths
        self.pathNames = Set(paths.compactMap { $0.split(separator: "/").last.map(String.init) })
        self.includeHidden = includeHidden
    }

    /// 항목 자체를 색인하지 않을지 (숨김을 끈 상태의 점 이름)
    public func skipsEntry(named name: String) -> Bool {
        !includeHidden && name.hasPrefix(".")
    }

    /// 디렉터리 안을 색인하지 않을지 (이름 규칙 또는 경로 규칙)
    public func excludesContents(ofDirectory path: String, name: String) -> Bool {
        names.contains(name) || paths.contains(path)
    }

    /// 디렉터리 안을 색인하지 않을지. 경로는 이름이 경로 규칙의 끝과 맞을 때만 만든다 (스캔 루프용)
    func excludesContents(name: String, path: () -> String) -> Bool {
        names.contains(name) || (pathNames.contains(name) && paths.contains(HangulText.nfc(path())))
    }

    /// 경로가 제외된 영역 안(제외 폴더의 자손이나 숨김 항목 아래)에 있는지. FSEvents 이벤트를 거를 때 쓴다
    /// 루트 아래의 구성 요소와 루트 안의 경로 규칙만 본다 (루트 경로 자체가 숨김이거나 제외 경로 안이어도 상관없다)
    public func isInsideExcludedArea(_ path: String, root: String) -> Bool {
        let path = HangulText.nfc(path)
        let base = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(base) else { return false }
        if paths.contains(where: { $0.hasPrefix(base) && path.hasPrefix($0 + "/") }) { return true }
        let relative = path.dropFirst(base.count)
        let components = relative.split(separator: "/")
        // 마지막 구성 요소는 그 항목 자체라 이름 규칙에 맞아도 폴더는 검색된다. 숨김은 항목 자체도 제외
        for (index, component) in components.enumerated() {
            if skipsEntry(named: String(component)) { return true }
            if index < components.count - 1, names.contains(String(component)) { return true }
        }
        return false
    }

    /// 루트 목록을 정리한다: ~ 확장, 중복 제거, 다른 루트를 스캔할 때 이미 색인되는 루트 제거 (순서 유지)
    /// 다른 루트 안이라도 그 루트에서 제외된 영역(제외 폴더·숨김 폴더 안)에 있으면 직접 추가한 것으로 보고 따로 색인한다
    public func normalizedRoots(_ roots: [String], home: String) -> [String] {
        let expanded = roots.map { Self.normalizedPath(HangulText.nfc($0), home: home) }.filter { !$0.isEmpty }
        var result: [String] = []
        for root in expanded where !result.contains(root) {
            let covered = expanded.contains { other in other != root && indexesContents(ofDirectory: root, under: other) }
            if !covered { result.append(root) }
        }
        return result
    }

    /// root를 스캔할 때 그 안의 디렉터리 path의 내용까지 색인하는지. path나 그 위 폴더가 제외 규칙에 맞거나 숨김이면 false
    func indexesContents(ofDirectory path: String, under root: String) -> Bool {
        let base = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(base) else { return false }
        if paths.contains(where: { $0.hasPrefix(base) && (path == $0 || path.hasPrefix($0 + "/")) }) { return false }
        return !path.dropFirst(base.count).split(separator: "/").contains { component in
            skipsEntry(named: String(component)) || names.contains(String(component))
        }
    }

    /// FSEvents에서 거를 경로 규칙. 루트이거나 루트를 품은 경로는 빼야 그 루트의 변경이 들어온다
    public func eventExclusions(roots: [String]) -> [String] {
        paths.filter { rule in !roots.contains { $0 == rule || $0.hasPrefix(rule + "/") } }
    }

    /// 설정이 바뀌었는지 판단하는 해시 (루트·규칙·숨김). 실행할 때마다 같아야 해서 FNV-1a를 쓴다
    public func configHash(roots: [String]) -> UInt64 {
        var text = "v1\n"
        text += roots.joined(separator: "\n") + "\n--\n"
        text += names.sorted().joined(separator: "\n") + "\n--\n"
        text += paths.sorted().joined(separator: "\n") + "\n--\n"
        text += includeHidden ? "hidden" : "visible"
        return FNV1a.hash(Array(text.utf8))
    }

    // ~ 확장, 끝의 / 제거 (루트 /는 그대로)
    static func normalizedPath(_ path: String, home: String) -> String {
        var path = path
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + path.dropFirst()
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// 64비트 FNV-1a 해시 (실행마다 시드가 바뀌는 Swift Hasher 대신 저장용으로 쓴다)
public enum FNV1a {
    static let offset: UInt64 = 0xcbf2_9ce4_8422_2325
    static let prime: UInt64 = 0x100_0000_01b3

    /// 바이트 배열의 해시
    public static func hash(_ bytes: [UInt8]) -> UInt64 {
        bytes.withUnsafeBufferPointer { update(offset, $0) }
    }

    /// 이어서 해시한다 (큰 데이터를 나눠 넣을 때)
    public static func update(_ hash: UInt64, _ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
        var hash = hash
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        return hash
    }

    /// 이어서 해시한다 (raw 바이트)
    public static func update(_ hash: UInt64, _ bytes: UnsafeRawBufferPointer) -> UInt64 {
        var hash = hash
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        return hash
    }
}
