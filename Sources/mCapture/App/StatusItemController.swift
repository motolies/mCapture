import AppKit

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
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "mCapture")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self
        hotkeyItems.forEach { menu.addItem($0.item) }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("이미지 열기…", modifiers: [], handler: actions.openFile))
        menu.addItem(ClosureMenuItem("저장 폴더 열기", modifiers: [], handler: actions.openSaveFolder))
        menu.addItem(ClosureMenuItem("설정…", keyEquivalent: ",", handler: actions.showSettings))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("mCapture 종료") { NSApp.terminate(nil) })
        statusItem.menu = menu
    }

    /// 메뉴를 열 때 현재 단축키를 항목 옆에 표시한다
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (action, item) in hotkeyItems {
            item.title = "\(action.title)\t\(preferences.hotkey(for: action).displayString)"
        }
    }
}
