import AppKit
import MCaptureCore
import SwiftUI

/// 설정 창 (한 개만 유지). 툴바 아이콘 탭으로 일반·캡처·파일 찾기·시스템 모니터를 나누고, 탭마다 창 높이를 내용에 맞춘다
///
/// 탭 컨트롤러는 화면만 바꾸고(툴바 스타일을 쓰지 않음) 툴바와 창 크기는 여기서 맡는다.
/// 툴바 스타일 NSTabViewController는 창이 숨어 있을 때 뷰 자체 크기로 창을 맞춰, 직접 정한 크기와 매번 다르게 섞였다
@MainActor
final class SettingsWindowController {
    private let model = SettingsModel()
    private let findFile: FindFileSettingsModel
    private var window: NSWindow?
    private let tabs = NSTabViewController()
    private var toolbar: SettingsToolbar?

    init(findFile controller: FindFileController) {
        findFile = FindFileSettingsModel(controller: controller)
    }

    /// 설정 창을 띄운다. tab을 주면 그 탭을, 없으면 마지막에 본 탭(처음엔 일반)을 연다
    func present(tab: SettingsTab? = nil) {
        model.reload()
        findFile.reload()
        if window == nil { makeWindow() }
        guard let window else { return }
        if let tab { select(tab) }
        // 닫았다가 다시 열 때도 지금 마우스가 있는 화면 가운데에 띄운다. 이미 떠 있으면 옮기지 않는다
        if !window.isVisible {
            fitToSelectedTab(animate: false)
            window.center(on: nil)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    // 탭마다 SwiftUI 화면을 붙인 탭 컨트롤러와 툴바, 창을 만든다
    private func makeWindow() {
        let title = "\(AppVariant.current.displayName) 설정"
        tabs.tabStyle = .unspecified
        // 창 제목은 콘텐츠 뷰 컨트롤러의 제목을 따르므로, 탭 화면의 제목(없음)으로 바뀌지 않게 고정한다
        tabs.canPropagateSelectedChildViewControllerTitle = false
        tabs.title = title
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: content(for: tab))
            // 창 크기를 SwiftUI 내용 높이에 묶지 않는다. 높이는 fitToSelectedTab이 맞춘다
            hosting.sizingOptions = []
            tabs.addTabViewItem(NSTabViewItem(viewController: hosting))
        }
        let toolbar = SettingsToolbar { [weak self] tab in self?.select(tab) }
        toolbar.highlight(selectedTab)

        let window = NSWindow(contentViewController: tabs)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.toolbar = toolbar.toolbar
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // 창을 닫거나 다른 앱으로 넘어가면 로컬 모니터가 키를 못 받으므로 녹화를 끝내 단축키를 되살린다
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.stopRecording() }
            }
        }
        self.window = window
        self.toolbar = toolbar
    }

    // 탭의 SwiftUI 화면
    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView(model: model)
        case .capture: CaptureSettingsView(model: model)
        case .find: FindFileSettingsView(model: findFile, hotkeys: model)
        case .monitor: SystemMonitorSettingsView()
        }
    }

    // 지금 고른 탭
    private var selectedTab: SettingsTab {
        SettingsTab.allCases[max(0, tabs.selectedTabViewItemIndex)]
    }

    // 탭을 고른다. 녹화를 끝내고(녹화 버튼이 보이지 않게 되므로) 창 높이를 새 탭에 맞춘다
    private func select(_ tab: SettingsTab) {
        toolbar?.highlight(tab)
        guard tab != selectedTab else { return }
        model.resetHotkeyEditing()
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        fitToSelectedTab(animate: window?.isVisible == true)
    }

    /// 창 내용 크기를 지금 탭에 맞춘다. 화면보다 길면 화면에 맞추고 내용을 스크롤한다. 위쪽 모서리는 그대로 둔다
    private func fitToSelectedTab(animate: Bool) {
        guard let window, let current = window.contentView?.frame.size else { return }
        let height = min(idealHeight(of: selectedTab), maxContentHeight(for: window))
        var frame = window.frame
        frame.size.width += SettingsTab.contentWidth - current.width
        frame.size.height += height - current.height
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true, animate: animate)
    }

    // 탭 내용을 스크롤 없이 펼쳤을 때의 높이
    private func idealHeight(of tab: SettingsTab) -> CGFloat {
        let measuring = NSHostingView(rootView: content(for: tab).fixedSize(horizontal: false, vertical: true))
        return measuring.fittingSize.height
    }

    // 커서가 있는 화면에서 창 내용이 차지할 수 있는 최대 높이 (제목 막대·툴바와 위아래 여백 제외)
    private func maxContentHeight(for window: NSWindow) -> CGFloat {
        let area = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame.height ?? 800
        let chrome = window.frame.height - (window.contentView?.frame.height ?? 0)
        return area - chrome - 40
    }
}

/// 설정 창 툴바. 탭마다 아이콘 항목을 두고, 누르면 그 탭을 고른다
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "SettingsTabs")
    private let onSelect: (SettingsTab) -> Void

    init(onSelect: @escaping (SettingsTab) -> Void) {
        self.onSelect = onSelect
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
    }

    /// 고른 탭 항목을 강조한다
    func highlight(_ tab: SettingsTab) {
        toolbar.selectedItemIdentifier = Self.identifier(tab)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(Self.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(itemClicked(_:))
        return item
    }

    // 툴바 항목을 누르면 그 탭을 고른다
    @objc private func itemClicked(_ item: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue) else { return }
        onSelect(tab)
    }

    // 탭의 툴바 항목 식별자 (URL과 같은 rawValue)
    private static func identifier(_ tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tab.rawValue)
    }
}
