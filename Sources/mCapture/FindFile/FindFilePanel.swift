import AppKit
import MCaptureCore

/// Spotlight처럼 화면 위쪽에 뜨는 파일 찾기 창. 검색 필드 · 결과 목록 · 상태 줄로 이루어진다
///
/// 포커스는 늘 검색 필드에 두고 ↑↓로 결과를 고른다. Enter·Esc·↑↓는 필드 에디터의 명령(doCommandBy)으로 받아
/// 한글 조합을 끝내는 Enter가 파일을 여는 일이 없다. ⌘ 조합은 한글 자판에서도 되도록 키 코드로 판별한다
final class FindFilePanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    enum Metrics {
        static let width: CGFloat = 680
        static let searchHeight: CGFloat = 52
        static let rowHeight: CGFloat = 40
        static let maxVisibleRows = 9
        static let statusHeight: CGFloat = 28
        static let cornerRadius: CGFloat = 12
        static let searchFontSize: CGFloat = 22
        static let padding: CGFloat = 18
        /// ↑↓ 대신 Page Up/Down으로 움직이는 줄 수
        static let pageRows = 8
    }

    /// (검색어, 한글 조합 중인지)
    var onQueryChange: ((String, Bool) -> Void)?
    var onOpen: ((SearchHit) -> Void)?
    var onReveal: ((SearchHit) -> Void)?
    var onCopyPath: ((SearchHit) -> Void)?
    /// Esc·⌘W·⌘Q로 닫을 때
    var onDismiss: (() -> Void)?

    private let searchField = NSTextField()
    private let fieldEditor = SearchFieldEditor(frame: .zero)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "↩ 열기   ⌘↩ Finder에서 보기   ⌘C 경로 복사")
    private let container = FlippedView()
    private(set) var hits: [SearchHit] = []
    /// 위쪽 모서리 y. 결과 수에 따라 높이가 바뀌어도 검색 필드가 움직이지 않게 고정한다
    private var topEdge: CGFloat = 0

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.searchHeight + Metrics.statusHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        animationBehavior = .utilityWindow
        delegate = self
        buildContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 구성

    // 둥근 반투명 배경 위에 검색 줄·결과 목록·상태 줄을 놓는다
    private func buildContent() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Metrics.cornerRadius)
        contentView = background

        container.autoresizingMask = [.width, .height]
        container.frame = background.bounds
        background.addSubview(container)

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "검색") ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = NSRect(x: Metrics.padding, y: (Metrics.searchHeight - 22) / 2, width: 22, height: 22)
        container.addSubview(icon)

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: Metrics.searchFontSize)
        searchField.placeholderString = "파일 이름   (ext:pdf  folder:  ~/경로/  regex:^IMG  ㅎㄱ)"
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.delegate = self
        container.addSubview(searchField)

        fieldEditor.isFieldEditor = true
        fieldEditor.allowsUndo = true
        fieldEditor.onChange = { [weak self] text, composing in
            self?.onQueryChange?(text, composing)
        }

        separator.boxType = .separator
        container.addSubview(separator)

        let column = NSTableColumn(identifier: ResultCellView.identifier)
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = .zero
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.refusesFirstResponder = true
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        for label in [statusLabel, hintLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            container.addSubview(label)
        }
        hintLabel.alignment = .right
        layoutContent()
    }

    // 결과 수에 맞춰 높이를 정하고 위쪽 모서리를 고정한 채 하위 뷰를 배치한다
    private func layoutContent() {
        let rows = min(hits.count, Metrics.maxVisibleRows)
        let listHeight = rows > 0 ? 1 + CGFloat(rows) * Metrics.rowHeight : 0
        let height = Metrics.searchHeight + listHeight + Metrics.statusHeight
        let width = Metrics.width
        if isVisible || topEdge > 0 {
            setFrame(NSRect(x: frame.minX, y: topEdge - height, width: width, height: height), display: true)
        } else {
            setContentSize(NSSize(width: width, height: height))
        }
        let fieldHeight: CGFloat = 28
        searchField.frame = NSRect(x: Metrics.padding + 32, y: (Metrics.searchHeight - fieldHeight) / 2,
                                   width: width - Metrics.padding * 2 - 32, height: fieldHeight)
        separator.isHidden = rows == 0
        separator.frame = NSRect(x: 0, y: Metrics.searchHeight, width: width, height: 1)
        scrollView.isHidden = rows == 0
        scrollView.frame = NSRect(x: 0, y: Metrics.searchHeight + 1, width: width, height: CGFloat(rows) * Metrics.rowHeight)
        tableView.tableColumns.first?.width = width
        let statusY = height - Metrics.statusHeight + (Metrics.statusHeight - 15) / 2
        hintLabel.frame = NSRect(x: width - Metrics.padding - 260, y: statusY, width: 260, height: 15)
        statusLabel.frame = NSRect(x: Metrics.padding, y: statusY, width: width - Metrics.padding * 2 - 270, height: 15)
    }

    // MARK: - 표시

    /// 커서가 있는 화면의 가운데 위쪽에 띄우고 검색어를 전체 선택한다 (바로 타이핑하면 바뀐다)
    func present(on screen: NSScreen?) {
        if let area = (screen ?? NSScreen.underMouse ?? NSScreen.main)?.visibleFrame {
            let maxHeight = Metrics.searchHeight + 1 + CGFloat(Metrics.maxVisibleRows) * Metrics.rowHeight + Metrics.statusHeight
            topEdge = (area.midY + maxHeight / 2).rounded()
            setFrameOrigin(NSPoint(x: (area.midX - Metrics.width / 2).rounded(), y: topEdge - frame.height))
            layoutContent()
        }
        // 비활성 패널이어도 한글 입력기가 확실히 붙도록 앱을 활성화한 뒤 키 창으로 만든다 (영역 선택 오버레이와 같은 순서)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    /// 지금 검색어
    var query: String { searchField.stringValue }

    /// 검색어를 바꾼다 (URL로 열 때)
    func setQuery(_ text: String) {
        searchField.stringValue = text
    }

    /// 결과를 바꾸고 첫 줄을 고른다
    func show(_ hits: [SearchHit]) {
        self.hits = hits
        tableView.reloadData()
        if !hits.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        layoutContent()
    }

    /// 상태 줄 왼쪽 문구
    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    /// 고른 결과
    var selectedHit: SearchHit? {
        let row = tableView.selectedRow
        return hits.indices.contains(row) ? hits[row] : nil
    }

    // 선택을 delta만큼 옮긴다 (끝에서 멈춤)
    private func moveSelection(by delta: Int) {
        guard !hits.isEmpty else { return }
        let row = max(0, min(hits.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func openClickedRow() {
        let row = tableView.clickedRow
        if hits.indices.contains(row) { onOpen?(hits[row]) }
    }

    // MARK: - 키 처리

    // Enter·Esc·↑↓·Page Up/Down. 한글 조합 중에 입력기가 쓴 키는 여기로 오지 않는다
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
            moveSelection(by: -Metrics.pageRows)
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
            moveSelection(by: Metrics.pageRows)
        case #selector(NSResponder.insertNewline(_:)):
            if let hit = selectedHit { onOpen?(hit) }
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
        default:
            return false
        }
        return true
    }

    // ⌘↩ Finder에서 보기, ⌘C 경로 복사, ⌘W·⌘Q 닫기
    // ⌘C는 검색어 일부를 직접 골라 둔 경우에만 글자를 복사한다. 열 때 전체 선택해 둔 검색어는 경로 복사를 막지 않는다
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.keyCode {
        case 36, 76:
            if let hit = selectedHit { onReveal?(hit) }
        case 8:
            let selection = searchField.currentEditor()?.selectedRange.length ?? 0
            let partialSelection = selection > 0 && selection < (searchField.currentEditor()?.string as NSString?)?.length ?? 0
            guard !partialSelection, let hit = selectedHit else { return super.performKeyEquivalent(with: event) }
            onCopyPath?(hit)
        case 13, 12:
            onDismiss?()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // 검색 필드에는 조합 중 글자를 알려 주는 필드 에디터를 쓴다
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NSTextField) === searchField ? fieldEditor : nil
    }

    // MARK: - 테이블

    func numberOfRows(in tableView: NSTableView) -> Int {
        hits.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCellView.identifier, owner: nil) as? ResultCellView ?? ResultCellView()
        cell.configure(hits[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRowView()
    }

    // MARK: - 도우미

    // 둥근 모서리 마스크 (늘려 써도 모서리는 그대로)
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
