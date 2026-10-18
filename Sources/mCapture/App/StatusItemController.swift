import AppKit
import MCaptureCore

/// 메뉴바 아이콘과 메뉴
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var captureArea: () -> Void
        var captureFullscreen: () -> Void
        var captureWindow: () -> Void
        var recognizeText: () -> Void
        var openFile: () -> Void
        var openSaveFolder: () -> Void
        var showSettings: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let preferences: Preferences
    /// 전역 단축키가 있는 동작의 메뉴 항목. 메뉴를 열 때 단축키를 제목 옆에 표시한다
    private let hotkeyItems: [(action: HotKeyCenter.Action, item: ClosureMenuItem)]

    init(preferences: Preferences, actions: Actions) {
        self.preferences = preferences
        hotkeyItems = [
            (.area, actions.captureArea),
            (.fullscreen, actions.captureFullscreen),
            (.window, actions.captureWindow),
            (.ocr, actions.recognizeText),
        ].map { action, handler in (action, ClosureMenuItem(action.title, modifiers: [], handler: handler)) }
        super.init()

        if let button = statusItem.button {
            // 개발 빌드는 사용 중인 앱과 메뉴바에서 구분되도록 다른 아이콘을 쓴다
            let symbol = AppVariant.current == .dev ? "hammer" : "camera.viewfinder"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppVariant.current.displayName)
            image?.isTemplate = true
            button.image = image
            // 아이콘에 마우스를 올리면 어떤 변형의 몇 버전이 떠 있는지 보인다
            button.toolTip = "\(AppVariant.current.displayName) \(AppVersion.current.displayString)"
        }

        let menu = NSMenu()
        menu.delegate = self
        hotkeyItems.forEach { menu.addItem($0.item) }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("이미지 열기…", modifiers: [], handler: actions.openFile))
        menu.addItem(ClosureMenuItem("저장 폴더 열기", modifiers: [], handler: actions.openSaveFolder))
        menu.addItem(ClosureMenuItem("설정…", keyEquivalent: ",", handler: actions.showSettings))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("\(AppVariant.current.displayName) 종료") { NSApp.terminate(nil) })
        statusItem.menu = menu
    }

    /// 메뉴를 열 때 현재 단축키를 항목 옆에 표시한다
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (action, item) in hotkeyItems {
            item.title = "\(action.title)\t\(preferences.hotkey(for: action).displayString)"
        }
    }
}
