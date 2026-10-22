import AppKit
import MCaptureCore

/// 클로저로 동작하는 메뉴 항목
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, keyEquivalent: String = "", modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func invoke() {
        handler()
    }
}

/// 앱 메인 메뉴. 에디터 동작은 first responder(캔버스)로 전달된다
@MainActor
enum MainMenu {
    static func build(appDelegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        let name = AppVariant.current.displayName

        main.addItem(submenu(name, items: [
            NSMenuItem(title: "\(name) 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            actionItem(.showSettings, "설정…", ",", target: appDelegate),
            .separator(),
            NSMenuItem(title: "\(name) 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            // 상주 앱이라 단축키 없이 메뉴로만 종료한다
            NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""),
        ]))

        main.addItem(submenu("파일", items: [
            actionItem(.captureArea, target: appDelegate),
            actionItem(.captureFullscreen, target: appDelegate),
            actionItem(.captureWindow, target: appDelegate),
            actionItem(.recognizeText, target: appDelegate),
            actionItem(.pickColor, target: appDelegate),
            actionItem(.findFile, target: appDelegate),
            actionItem(.openImage, "열기…", "o", [.command, .shift], target: appDelegate),
            .separator(),
            item("저장", #selector(CanvasView.saveDocument(_:)), "s"),
            item("다른 이름으로 저장…", #selector(CanvasView.saveDocumentAs(_:)), "s", [.command, .shift]),
            item("화면에 고정", #selector(CanvasView.pinToScreen(_:)), "p"),
            .separator(),
            item("닫기", #selector(NSWindow.performClose(_:)), "w"),
            quitShortcutClosesWindow(),
        ]))

        main.addItem(submenu("편집", items: [
            item("실행 취소", #selector(CanvasView.undo(_:)), "z"),
            item("다시 실행", #selector(CanvasView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("잘라내기", #selector(NSText.cut(_:)), "x"),
            item("복사", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("삭제", #selector(NSText.delete(_:)), ""),
            item("전체 선택", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("크롭", #selector(CanvasView.cropToSelection(_:)), ""),
            item("크롭 초기화", #selector(CanvasView.resetCrop(_:)), "r", [.command, .shift]),
        ]))

        main.addItem(submenu("보기", items: [
            item("확대", #selector(CanvasView.zoomIn(_:)), "="),
            item("축소", #selector(CanvasView.zoomOut(_:)), "-"),
            item("실제 크기", #selector(CanvasView.zoomToActualSize(_:)), "0"),
            item("화면에 맞춤", #selector(CanvasView.zoomToFit(_:)), "1"),
            item("선택 영역으로 확대", #selector(CanvasView.zoomToSelection(_:)), "2"),
        ]))

        let windowMenu = submenu("윈도우", items: [
            NSMenuItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu
        return main
    }

    // 하위 메뉴를 가진 최상위 항목을 만든다
    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// ⌘Q를 앱 종료 대신 앞 창 닫기(⌘W와 같음)로 받는 숨은 항목. 메뉴에는 보이지 않고 단축키만 동작한다
    private static func quitShortcutClosesWindow() -> NSMenuItem {
        let item = item("닫기", #selector(NSWindow.performClose(_:)), "q")
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    // AppDelegate.perform(_:)으로 가는 메뉴 항목. 동작 이름을 representedObject에 담아 셀렉터 하나로 받는다. 제목을 주지 않으면 동작 이름
    private static func actionItem(
        _ action: AppAction,
        _ title: String? = nil,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AppDelegate
    ) -> NSMenuItem {
        let item = item(title ?? action.title, #selector(AppDelegate.performMenuAction(_:)), key, modifiers, target: target)
        item.representedObject = action.rawValue
        return item
    }

    // first responder 또는 지정 대상에게 보내는 메뉴 항목을 만든다
    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
