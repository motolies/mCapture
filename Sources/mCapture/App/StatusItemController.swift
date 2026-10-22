import AppKit
import MCaptureCore

/// 메뉴바 아이콘과 메뉴
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let preferences: Preferences
    private let sleepPreventer: SleepPreventer
    /// 전역 단축키가 있는 동작의 메뉴 항목. 메뉴를 열 때 단축키를 제목 옆에 표시한다
    private let hotkeyItems: [(action: HotKeyCenter.Action, item: ClosureMenuItem)]
    /// 잠자기 방지 켜기·끄기. 켜져 있으면 체크 표시
    private lazy var sleepItem = ClosureMenuItem("잠자기 방지", modifiers: []) { [weak self] in self?.toggleSleepPrevention() }

    /// perform은 메뉴 항목이 고른 공용 동작을 실행한다 (AppDelegate.perform)
    init(preferences: Preferences, sleepPreventer: SleepPreventer, perform: @escaping (AppAction) -> Void) {
        self.preferences = preferences
        self.sleepPreventer = sleepPreventer
        hotkeyItems = HotKeyCenter.Action.allCases.map { action in
            (action, ClosureMenuItem(action.title, modifiers: []) { perform(action.appAction) })
        }
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        for (action, item) in hotkeyItems {
            // 캡처 동작과 파일 찾기 사이를 나눈다
            if action == .findFile { menu.addItem(.separator()) }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("이미지 열기…", modifiers: []) { perform(.openImage) })
        menu.addItem(ClosureMenuItem("저장 폴더 열기", modifiers: []) { perform(.openSaveFolder) })
        menu.addItem(ClosureMenuItem("설정…", keyEquivalent: ",") { perform(.showSettings) })
        menu.addItem(.separator())
        menu.addItem(sleepItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("\(AppVariant.current.displayName) 종료") { NSApp.terminate(nil) })
        statusItem.menu = menu
        updateAppearance()
    }

    /// 메뉴를 열 때 현재 단축키를 항목 옆에 표시한다
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (action, item) in hotkeyItems {
            item.title = "\(action.title)\t\(preferences.hotkey(for: action).displayString)"
        }
        updateAppearance()
    }

    /// 잠자기 방지를 켜거나 끄고 아이콘에 반영한다. 켜지 못하면 알린다
    func setSleepPrevention(_ active: Bool) {
        if !sleepPreventer.setActive(active) {
            ToastPanel.show("잠자기 방지를 켜지 못했습니다", systemImage: "exclamationmark.triangle.fill")
        }
        updateAppearance()
    }

    func toggleSleepPrevention() {
        setSleepPrevention(!sleepPreventer.isActive)
    }

    /// 잠자기 방지 상태를 아이콘 색·툴팁·체크 표시에 반영한다
    /// 켜지면 초록을 입힌 비템플릿 이미지로 바꾼다. 템플릿 이미지는 메뉴바가 단색으로 칠해 색이 남지 않는다
    private func updateAppearance() {
        let active = sleepPreventer.isActive
        sleepItem.state = active ? .on : .off
        guard let button = statusItem.button else { return }
        // 개발 빌드는 사용 중인 앱과 메뉴바에서 구분되도록 다른 아이콘을 쓴다
        let symbol = AppVariant.current == .dev ? "hammer" : "camera.viewfinder"
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: AppVariant.current.displayName)
        let image = active ? base?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemGreen])) : base
        image?.isTemplate = !active
        button.image = image
        // 아이콘에 마우스를 올리면 어떤 변형의 몇 버전이 떠 있는지 보인다
        let version = "\(AppVariant.current.displayName) \(AppVersion.current.displayString)"
        button.toolTip = active ? "\(version) — 잠자기 방지 켜짐" : version
    }
}
