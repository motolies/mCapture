import AppKit

/// 파일 찾기의 폴더 접근 권한 확인과 안내
///
/// 샌드박스를 쓰지 않는 앱도 데스크탑·문서·다운로드·iCloud Drive는 처음 열 때 허용 창이 뜨고(TCC),
/// ~/Library의 Mail·Messages·Safari 같은 폴더는 전체 디스크 접근 권한이 없으면 허용 창 없이 거부된다
enum FileAccessPermission {
    /// 전체 디스크 접근 권한이 있는지. TCC 데이터베이스를 열어 보는 방식이라 허용 창을 띄우지 않는다
    static var hasFullDiskAccess: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = Darwin.open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// 거부되면 사용자에게 알릴 폴더 (나머지 ~/Library 보호 폴더는 조용히 건너뛴다)
    static func userFolders(home: String) -> [String] {
        ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { home + "/" + $0 }
    }

    /// 거부 경로 중 사용자 폴더(또는 그 아래)만 고른다
    static func deniedUserFolders(_ denied: [String], home: String) -> [String] {
        let folders = userFolders(home: home)
        return folders.filter { folder in denied.contains { $0 == folder || $0.hasPrefix(folder + "/") } }
    }

    /// 거부됐던 폴더를 지금 열 수 있는지 (한 번 결정된 권한은 다시 묻지 않으므로 허용 창이 뜨지 않는다)
    static func canRead(_ path: String) -> Bool {
        guard let directory = opendir(path) else { return false }
        closedir(directory)
        return true
    }

    /// 시스템 설정의 전체 디스크 접근 화면을 연다
    @MainActor
    static func openFullDiskAccessSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    /// 시스템 설정의 파일 및 폴더 화면을 연다
    @MainActor
    static func openFilesAndFoldersSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    // 시스템 설정 URL을 연다
    @MainActor
    private static func openSettings(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
