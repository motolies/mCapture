import AppKit
import Combine
import MCaptureCore
import SwiftUI

/// 설정 "파일 찾기" 탭의 상태. 값을 바꾸면 2초 뒤 한 번에 인덱서에 반영한다 (제외 규칙을 타이핑하는 동안 다시 스캔하지 않게)
@MainActor
final class FindFileSettingsModel: ObservableObject {
    @Published var roots: [String] = []
    @Published var status = ""
    @Published var fullDiskAccess = false
    /// 접근이 거부된 사용자 폴더 (데스크탑·문서·다운로드·iCloud Drive)
    @Published var deniedFolders: [String] = []
    private let controller: FindFileController
    private var applyTask: Task<Void, Never>?

    init(controller: FindFileController) {
        self.controller = controller
    }

    /// 창을 열 때마다 지금 값으로 다시 읽고, 거부됐던 폴더를 다시 시도한다
    func reload() {
        roots = Preferences.shared.findFileRoots
        fullDiskAccess = FileAccessPermission.hasFullDiskAccess
        controller.onStatusChange = { [weak self] status in self?.update(status) }
        update(controller.status)
        Task { [controller] in
            await controller.indexer.retryDeniedFolders()
            let denied = await controller.indexer.stats().deniedPaths
            self.deniedFolders = FileAccessPermission.deniedUserFolders(denied, home: NSHomeDirectory())
        }
    }

    // 인덱서 상태를 문구로 바꾼다 (준비됐으면 갱신 시각도)
    private func update(_ status: FileIndexer.Status) {
        if case .ready(let count, let updatedAt) = status {
            let relative = RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: Date())
            self.status = "\(count.formatted())개 · \(relative) 갱신"
        } else {
            self.status = FindFileController.statusText(status)
        }
    }

    /// 검색 폴더를 추가한다 (~ 형태로 저장)
    func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = (url.path as NSString).abbreviatingWithTildeInPath
        guard !roots.contains(root) else { return }
        roots.append(root)
        saveRoots()
    }

    /// 검색 폴더를 뺀다
    func removeRoot(_ root: String) {
        roots.removeAll { $0 == root }
        saveRoots()
    }

    /// 기본 검색 폴더로 되돌린다
    func resetRoots() {
        roots = Preferences.Default.findFileRoots
        saveRoots()
    }

    // 폴더 목록을 저장하고 반영을 예약한다
    private func saveRoots() {
        Preferences.shared.findFileRoots = roots
        scheduleApply()
    }

    /// 설정 변경을 2초 뒤 인덱서에 반영한다. 그 사이 또 바뀌면 다시 2초를 기다린다
    func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [controller] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            controller.applyPreferences()
        }
    }

    func rebuild() {
        controller.rebuild()
    }
}

/// 설정 창의 "파일 찾기" 탭
struct FindFileSettingsView: View {
    @ObservedObject var model: FindFileSettingsModel
    /// 단축키 녹화 상태 (다른 탭과 함께 쓴다)
    @ObservedObject var hotkeys: SettingsModel
    @AppStorage(Preferences.Key.findFileEnabled) private var enabled = true
    @AppStorage(Preferences.Key.findFileExclusions) private var exclusions = ExclusionRules.defaultText
    @AppStorage(Preferences.Key.findFileIncludeHidden) private var includeHidden = false

    var body: some View {
        Form {
            Section("인덱스") {
                Toggle("파일 찾기 인덱스 사용 (앱 시작 때 만들고 변경을 감시)", isOn: $enabled)
                LabeledContent("상태") {
                    HStack {
                        Text(model.status)
                            .foregroundStyle(.secondary)
                        Button("다시 만들기") { model.rebuild() }
                            .disabled(!enabled)
                    }
                }
            }

            Section("검색 폴더") {
                ForEach(model.roots, id: \.self) { root in
                    HStack(spacing: 6) {
                        Text(root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { model.removeRoot(root) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("이 폴더 빼기")
                    }
                }
                HStack {
                    Spacer()
                    Button("기본값") { model.resetRoots() }
                        .disabled(model.roots == Preferences.Default.findFileRoots)
                    Button("폴더 추가…") { model.addRoot() }
                }
            }

            Section("제외 규칙") {
                TextEditor(text: $exclusions)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 110)
                HStack(alignment: .top) {
                    Text("검색 폴더 안에서 내용을 색인하지 않을 폴더. 한 줄에 하나, 이름(node_modules) 또는 경로(~/Library/Caches). 폴더 이름은 검색됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("기본값") { exclusions = ExclusionRules.defaultText }
                        .disabled(exclusions == ExclusionRules.defaultText)
                }
                Toggle("숨김 파일 포함 (.으로 시작하는 이름)", isOn: $includeHidden)
            }

            Section("권한") {
                LabeledContent("전체 디스크 접근") {
                    HStack {
                        Text(model.fullDiskAccess ? "허용됨" : "없음 (~/Library 보호 폴더는 건너뜀)")
                            .foregroundStyle(model.fullDiskAccess ? .green : .secondary)
                        Button("시스템 설정 열기") { FileAccessPermission.openFullDiskAccessSettings() }
                    }
                }
                if !model.deniedFolders.isEmpty {
                    HStack(alignment: .top) {
                        Text("접근이 거부된 폴더: " + model.deniedFolders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("파일 및 폴더 설정 열기") { FileAccessPermission.openFilesAndFoldersSettings() }
                    }
                }
            }

            HotKeySettingsSection(model: hotkeys, actions: [.findFile])
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
        .onChange(of: enabled) { _, _ in model.scheduleApply() }
        .onChange(of: exclusions) { _, _ in model.scheduleApply() }
        .onChange(of: includeHidden) { _, _ in model.scheduleApply() }
    }
}
