import AppKit
import MCaptureCore

/// 메뉴바 메뉴의 "외부 디스플레이 복구" 하위 메뉴 (F36).
/// 하위 메뉴를 열 때마다 연결 상태를 다시 읽어, 시스템이 인식하지 못한 디스플레이만 고를 수 있게 한다.
/// 맨 아래에는 자동 복구를 켜고 끄는 항목이 있다
@MainActor
final class DisplayRecoveryMenu: NSObject, NSMenuDelegate {
    let item = NSMenuItem(title: "외부 디스플레이 복구", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        let submenu = NSMenu()
        submenu.delegate = self
        item.submenu = submenu
    }

    /// 하위 메뉴가 열리기 직전에 항목을 다시 만든다
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        Self.makeItems().forEach(menu.addItem)
    }

    // 연결 상태 항목들, 구분선, 자동 복구 토글 순서로 만든다. 비공개 함수를 쓸 수 없으면 안내만 보인다
    private static func makeItems() -> [NSMenuItem] {
        guard let connections = ExternalDisplayConnection.all() else {
            return [status("이 macOS에서는 지원하지 않습니다")]
        }
        return connectionItems(connections) + [.separator(), automaticToggle()]
    }

    // 연결마다 항목 하나. 정상 인식된 디스플레이는 이름만 보이고, 인식 실패한 디스플레이만 누를 수 있다
    private static func connectionItems(_ connections: [ExternalDisplayConnection]) -> [NSMenuItem] {
        guard !connections.isEmpty else { return [status("연결된 외부 디스플레이가 없습니다")] }

        // 시스템이 가진 EDID는 연결마다 한 번만 묻는다
        let states = connections.map { (connection: $0, systemEDID: $0.systemEDIDBytes()) }
        let unrecognizedCount = states.count { $0.systemEDID == nil }
        var unrecognizedIndex = 0
        return states.map { connection, systemEDID in
            if let bytes = systemEDID {
                let name = EDID(validating: bytes)?.displayName ?? "외부 디스플레이"
                return status("\(name) — 정상")
            }
            unrecognizedIndex += 1
            // 인식 실패한 디스플레이는 이름을 알 수 없다. 여러 개일 때만 번호를 붙인다
            let number = unrecognizedCount > 1 ? " \(unrecognizedIndex)" : ""
            return ClosureMenuItem("인식 실패한 디스플레이\(number) 복구", modifiers: []) { DisplayRecovery.recover(connection) }
        }
    }

    // 자동 복구 켜기·끄기. 켜져 있으면 체크 표시
    private static func automaticToggle() -> NSMenuItem {
        let enabled = Preferences.shared.displayAutoRecovery
        let item = ClosureMenuItem("연결할 때 자동으로 복구", modifiers: []) { DisplayRecovery.setAutomatic(!enabled) }
        item.state = enabled ? .on : .off
        return item
    }

    // 누를 수 없는 상태 표시 항목. 동작이 없으면 메뉴가 알아서 흐리게 보인다
    private static func status(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    #if DEBUG
    /// 하위 메뉴 항목의 제목, 누를 수 있는지, 체크 여부 (debug/display-status). 메뉴를 열지 않고 확인한다
    static func debugItems() -> [[String: Any]] {
        makeItems().filter { !$0.isSeparatorItem }.map {
            ["title": $0.title, "actionable": $0.action != nil, "checked": $0.state == .on]
        }
    }
    #endif
}
