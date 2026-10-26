import AppKit
import MCaptureCore

/// Spotlight처럼 화면 위쪽에 뜨는 파일 찾기 창. 검색 줄(필터 칩 · 검색 필드 · 필터 단추) · 결과 목록 · 상태 줄로 이루어진다
///
/// 포커스는 늘 검색 필드에 두고 ↑↓로 결과를 고른다. Enter·Esc·↑↓는 필드 에디터의 명령(doCommandBy)으로 받아
/// 한글 조합을 끝내는 Enter가 파일을 여는 일이 없다. ⌘ 조합은 한글 자판에서도 되도록 키 코드로 판별한다
///
/// 필터 칩은 검색어의 일부(`ext:` 등)를 나눠 보여 주기만 한다. 검색어는 늘 칩 원문 + 필드 글자다(`query`)
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
        /// 검색 필드가 시작하는 x (돋보기 아이콘 다음)
        static let fieldStartX: CGFloat = padding + 32
        static let filterButtonSize: CGFloat = 28
        static let chipGap: CGFloat = 6
        /// 칩이 차지할 수 있는 최대 폭. 넘치면 앞쪽 칩을 "+N"으로 줄인다
        static let chipAreaMaxWidth: CGFloat = 300
        /// 상태 줄 왼쪽(일치 수)에 남겨 둘 최소 폭
        static let statusMinWidth: CGFloat = 200
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
    private let filterButton = NSButton()
    private let overflowLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let container = FlippedView()
    private(set) var hits: [SearchHit] = []
    /// 위쪽 모서리 y. 결과 수에 따라 높이가 바뀌어도 검색 필드가 움직이지 않게 고정한다
    private var topEdge: CGFloat = 0

    /// 필터 칩 (검색어 앞부분)
    private var chips: [FilterToken] = []
    private var chipViews: [FilterChipView] = []
    /// 넘쳐서 "+N"으로 줄인 앞쪽 칩 수
    private var hiddenChipCount = 0
    /// ←로 고른 칩
    private var selectedChip: Int?
    /// 열 때 검색어와 함께 칩도 선택된 상태. 이때 타이핑하면 칩까지 바뀐다 (지난 필터가 몰래 남지 않게)
    private var chipsSelectedWithText = false
    /// 상태 줄 오른쪽 키 안내 (앞쪽이 중요, 폭이 모자라면 뒤에서부터 뺀다)
    private var hints = ["↩ 열기", "⌘↩ Finder에서 보기", "⌘C 경로 복사", "⌘F 필터"]

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
        searchField.placeholderString = "파일 이름   (ext:pdf  ~/폴더/  folder:  regex:^IMG  ㅎㄱ)"
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.delegate = self
        container.addSubview(searchField)

        fieldEditor.isFieldEditor = true
        fieldEditor.allowsUndo = true
        fieldEditor.onChange = { [weak self] text, composing in
            self?.fieldChanged(text, composing: composing)
        }
        fieldEditor.onWillChange = { [weak self] range in
            self?.fieldWillChange(range)
        }
        fieldEditor.onSelectionChange = { [weak self] in
            self?.fieldSelectionChanged()
        }

        overflowLabel.font = .systemFont(ofSize: 12, weight: .medium)
        overflowLabel.textColor = .secondaryLabelColor
        overflowLabel.isHidden = true
        container.addSubview(overflowLabel)

        filterButton.isBordered = false
        filterButton.refusesFirstResponder = true
        filterButton.imagePosition = .imageOnly
        filterButton.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        filterButton.toolTip = "필터 추가 (⌘F)"
        filterButton.target = self
        filterButton.action = #selector(showFilterMenu)
        container.addSubview(filterButton)
        updateFilterButton()

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
        layoutSearchRow()
        separator.isHidden = rows == 0
        separator.frame = NSRect(x: 0, y: Metrics.searchHeight, width: width, height: 1)
        scrollView.isHidden = rows == 0
        scrollView.frame = NSRect(x: 0, y: Metrics.searchHeight + 1, width: width, height: CGFloat(rows) * Metrics.rowHeight)
        tableView.tableColumns.first?.width = width
        layoutStatusRow(y: height - Metrics.statusHeight + (Metrics.statusHeight - 15) / 2)
    }

    // 검색 줄: 돋보기 · [+N] · 칩들 · 검색 필드 · 필터 단추
    private func layoutSearchRow() {
        let width = Metrics.width
        let size = Metrics.filterButtonSize
        filterButton.frame = NSRect(x: width - Metrics.padding - size, y: (Metrics.searchHeight - size) / 2, width: size, height: size)

        // 칩 영역 폭을 넘으면 뒤쪽(최근) 칩을 남기고 앞쪽을 "+N"으로 줄인다
        let widths = chipViews.map(\.preferredWidth)
        let total = { (from: Int) in widths[from...].reduce(0) { $0 + $1 + Metrics.chipGap } }
        hiddenChipCount = 0
        if total(0) > Metrics.chipAreaMaxWidth {
            overflowLabel.stringValue = "+\(chipViews.count)"
            let reserve = ceil(overflowLabel.intrinsicContentSize.width) + Metrics.chipGap
            while hiddenChipCount < chipViews.count - 1, total(hiddenChipCount) + reserve > Metrics.chipAreaMaxWidth {
                hiddenChipCount += 1
            }
        }
        var x = Metrics.fieldStartX
        overflowLabel.isHidden = hiddenChipCount == 0
        if hiddenChipCount > 0 {
            overflowLabel.stringValue = "+\(hiddenChipCount)"
            overflowLabel.toolTip = chips[..<hiddenChipCount].map(\.raw).joined(separator: "  ")
            let labelSize = overflowLabel.intrinsicContentSize
            overflowLabel.frame = NSRect(x: x, y: (Metrics.searchHeight - labelSize.height) / 2,
                                         width: ceil(labelSize.width), height: labelSize.height)
            x = overflowLabel.frame.maxX + Metrics.chipGap
        }
        for (index, view) in chipViews.enumerated() {
            view.isHidden = index < hiddenChipCount
            guard !view.isHidden else { continue }
            view.frame = NSRect(x: x, y: (Metrics.searchHeight - FilterChipView.Metrics.height) / 2,
                                width: widths[index], height: FilterChipView.Metrics.height)
            x = view.frame.maxX + Metrics.chipGap
        }
        let fieldHeight: CGFloat = 28
        searchField.frame = NSRect(x: x, y: (Metrics.searchHeight - fieldHeight) / 2,
                                   width: filterButton.frame.minX - 8 - x, height: fieldHeight)
    }

    // 상태 줄: 왼쪽 일치 수, 오른쪽 키 안내(들어가는 만큼만)
    private func layoutStatusRow(y: CGFloat) {
        let width = Metrics.width
        let available = width - Metrics.padding * 2 - Metrics.statusMinWidth
        let fitted = Self.fit(hints, font: hintLabel.font ?? .systemFont(ofSize: 11), width: available)
        hintLabel.stringValue = fitted.text
        let hintWidth = fitted.width
        hintLabel.frame = NSRect(x: width - Metrics.padding - hintWidth, y: y, width: hintWidth, height: 15)
        statusLabel.frame = NSRect(x: Metrics.padding, y: y, width: width - Metrics.padding * 2 - hintWidth - 10, height: 15)
    }

    // MARK: - 표시

    /// 커서가 있는 화면의 가운데 위쪽에 띄우고 검색어를 전체 선택한다 (바로 타이핑하면 칩까지 바뀐다)
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
        selectedChip = nil
        chipsSelectedWithText = !chips.isEmpty
        updateChipSelection()
    }

    /// 지금 검색어 (칩 원문 + 필드 글자)
    var query: String { FilterToken.combine(chips, rest: fieldText) }

    /// 검색어를 바꾼다 (URL로 열 때). 필터 항은 칩으로 나눈다
    func setQuery(_ text: String) {
        if let extraction = FilterToken.extract(from: text, includeLast: true) {
            chips = extraction.tokens
            setFieldText(extraction.rest)
        } else {
            chips = []
            setFieldText(text)
        }
        selectedChip = nil
        rebuildChips()
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

    // MARK: - 검색 필드와 칩

    // 필드 에디터의 지금 글자 (조합 중 글자 포함)
    private var fieldText: String {
        (searchField.currentEditor() as? NSTextView)?.string ?? searchField.stringValue
    }

    // 필드 글자를 코드로 바꾼다. 칩과 글자가 따로 움직여 실행 취소 기록이 맞지 않으므로 기록을 비운다
    private func setFieldText(_ text: String, cursor: Int? = nil) {
        guard let editor = searchField.currentEditor() as? NSTextView else {
            searchField.stringValue = text
            return
        }
        editor.string = text
        editor.setSelectedRange(NSRange(location: cursor ?? (text as NSString).length, length: 0))
        editor.undoManager?.removeAllActions()
    }

    // 글자가 바뀌면: 커서가 끝에 있고 조합 중이 아니면 다 친 필터 항을 칩으로 옮긴 뒤 검색어를 알린다
    private func fieldChanged(_ text: String, composing: Bool) {
        if selectedChip != nil {
            selectedChip = nil
            updateChipSelection()
        }
        if !composing, let editor = searchField.currentEditor() as? NSTextView,
           editor.selectedRange() == NSRange(location: (text as NSString).length, length: 0),
           let extraction = FilterToken.extract(from: text, includeLast: false) {
            chips += extraction.tokens
            setFieldText(extraction.rest)
            rebuildChips()
        }
        onQueryChange?(query, composing)
    }

    // 칩과 함께 전체 선택된 글자를 덮어쓰면 칩도 지운다
    private func fieldWillChange(_ range: NSRange) {
        guard chipsSelectedWithText else { return }
        let length = (fieldText as NSString).length
        guard range.location == 0, range.length == length else { return }
        chipsSelectedWithText = false
        chips.removeAll()
        rebuildChips()
    }

    // 전체 선택이 풀리면 칩 선택도 푼다
    private func fieldSelectionChanged() {
        guard chipsSelectedWithText, let editor = searchField.currentEditor() as? NSTextView else { return }
        if editor.selectedRange() != NSRange(location: 0, length: (editor.string as NSString).length) {
            chipsSelectedWithText = false
            updateChipSelection()
        }
    }

    // 칩 뷰를 칩 목록에 맞춰 다시 만든다
    private func rebuildChips() {
        chipViews.forEach { $0.removeFromSuperview() }
        chipViews = chips.enumerated().map { index, token in
            let view = FilterChipView(token: token)
            view.onClick = { [weak self] in self?.selectChip(index) }
            view.onDoubleClick = { [weak self] in self?.unchip(at: index) }
            view.onRemove = { [weak self] in self?.removeChip(at: index) }
            container.addSubview(view)
            return view
        }
        if let selected = selectedChip, !chips.indices.contains(selected) { selectedChip = nil }
        updateChipSelection()
        updateFilterButton()
        layoutContent()
    }

    // 칩 선택 표시를 맞춘다
    private func updateChipSelection() {
        for (index, view) in chipViews.enumerated() {
            view.isSelected = chipsSelectedWithText || index == selectedChip
        }
    }

    // 칩이 바뀐 뒤 화면과 검색을 맞춘다
    private func chipsChanged() {
        rebuildChips()
        onQueryChange?(query, false)
    }

    private func selectChip(_ index: Int) {
        chipsSelectedWithText = false
        selectedChip = index
        updateChipSelection()
    }

    private func removeChip(at index: Int) {
        guard chips.indices.contains(index) else { return }
        chips.remove(at: index)
        selectedChip = nil
        chipsChanged()
    }

    // 칩을 글자로 되돌려 필드 앞에 넣고 그 끝에 커서를 둔다 (고쳐 쓰고 끝에서 Space를 치면 다시 칩이 된다)
    private func unchip(at index: Int) {
        guard chips.indices.contains(index) else { return }
        let token = chips.remove(at: index)
        let text = fieldText
        setFieldText(text.isEmpty ? token.raw : token.raw + " " + text, cursor: (token.raw as NSString).length)
        selectedChip = nil
        chipsSelectedWithText = false
        chipsChanged()
    }

    // ←→: 맨 앞에서 ←는 마지막 칩을 고르고, 칩을 고른 동안은 칩 사이를 옮긴다
    private func moveChipSelection(left: Bool, in textView: NSTextView) -> Bool {
        if chipsSelectedWithText {
            chipsSelectedWithText = false
            updateChipSelection()
            return false
        }
        if let selected = selectedChip {
            if left {
                selectedChip = max(hiddenChipCount, selected - 1)
            } else {
                selectedChip = selected + 1 < chips.count ? selected + 1 : nil
            }
            updateChipSelection()
            return true
        }
        guard left, !chips.isEmpty, textView.selectedRange() == NSRange(location: 0, length: 0) else { return false }
        selectedChip = chips.count - 1
        updateChipSelection()
        return true
    }

    // ⌫: 고른 칩은 지우고, 맨 앞에서는 마지막 칩을 글자로 되돌린다
    private func deleteBackwardIntoChips(in textView: NSTextView) -> Bool {
        if let selected = selectedChip {
            removeChip(at: selected)
            return true
        }
        if chipsSelectedWithText, textView.string.isEmpty {
            chipsSelectedWithText = false
            chips.removeAll()
            chipsChanged()
            return true
        }
        guard !chipsSelectedWithText, !chips.isEmpty, textView.selectedRange() == NSRange(location: 0, length: 0) else { return false }
        unchip(at: chips.count - 1)
        return true
    }

    // 필터 단추: 칩이 있으면 채운 아이콘에 강조색
    private func updateFilterButton() {
        let name = chips.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
        filterButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "필터")
        filterButton.contentTintColor = chips.isEmpty ? .secondaryLabelColor : .controlAccentColor
    }

    // MARK: - 필터 메뉴

    private enum FilterMenuAction {
        /// 칩을 추가한다 (위치·종류는 같은 범주 칩을 바꾼다)
        case chip(FilterToken)
        /// 필드 끝에 접두어를 넣고 값을 치게 한다
        case insert(String)
        case clear
    }

    /// 필터 메뉴를 필터 단추 아래에 연다 (⌘F)
    @objc func showFilterMenu() {
        let menu = makeFilterMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: filterButton.bounds.height + 4), in: filterButton)
    }

    // 위치·확장자·종류·정규식 메뉴를 만든다. 고르면 칩이 되거나 필드에 문법 글자가 들어간다
    private func makeFilterMenu() -> NSMenu {
        let home = NSHomeDirectory()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let location = NSMenu()
        location.autoenablesItems = false
        location.addItem(menuItem("홈 폴더  ~/", .chip(.location(home, home: home))))
        location.addItem(menuItem("응용 프로그램  /Applications/", .chip(.location("/Applications", home: home))))
        if let hit = selectedHit {
            let folder = hit.isDirectory ? hit.path : (hit.path as NSString).deletingLastPathComponent
            let token = FilterToken.location(folder, home: home)
            location.addItem(menuItem("고른 결과의 폴더  \(token.value)", .chip(token)))
        } else {
            let item = menuItem("고른 결과의 폴더", .clear)
            item.isEnabled = false
            location.addItem(item)
        }
        location.addItem(.separator())
        location.addItem(menuItem("경로 직접 입력…", .insert("~/")))
        menu.addItem(submenuItem("위치 (이 폴더 안)", location))

        let extensions = NSMenu()
        extensions.autoenablesItems = false
        for (title, list) in Self.extensionGroups {
            if let token = FilterToken.extensions(list) {
                let item = menuItem(title, .chip(token))
                item.toolTip = token.value
                extensions.addItem(item)
            }
        }
        extensions.addItem(.separator())
        extensions.addItem(menuItem("확장자 직접 입력…", .insert("ext:")))
        menu.addItem(submenuItem("확장자", extensions))

        let kind = NSMenu()
        kind.autoenablesItems = false
        for value in [SearchQuery.Kind.file, .folder] {
            guard let token = FilterToken.kind(value) else { continue }
            let item = menuItem(token.value, .chip(token))
            item.state = chips.contains(token) ? .on : .off
            kind.addItem(item)
        }
        menu.addItem(submenuItem("종류", kind))
        menu.addItem(menuItem("정규식 입력…", .insert("regex:")))

        menu.addItem(.separator())
        let clear = menuItem("필터 모두 지우기", .clear)
        clear.isEnabled = !chips.isEmpty
        menu.addItem(clear)
        return menu
    }

    /// 확장자 묶음 (메뉴 이름, 확장자)
    private static let extensionGroups: [(String, [String])] = [
        ("문서", ["pdf", "doc", "docx", "hwp", "hwpx", "txt", "md", "rtf", "pages"]),
        ("이미지", ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]),
        ("동영상", ["mp4", "mov", "m4v", "mkv", "avi", "webm"]),
        ("오디오", ["mp3", "m4a", "wav", "aac", "flac"]),
        ("압축", ["zip", "tar", "gz", "tgz", "7z", "rar", "dmg"]),
    ]

    private func menuItem(_ title: String, _ action: FilterMenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(filterMenuChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        return item
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // 메뉴 항목을 골랐을 때: 칩 추가·접두어 넣기·모두 지우기
    @objc private func filterMenuChosen(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FilterMenuAction else { return }
        if searchField.currentEditor() == nil { makeFirstResponder(searchField) }
        chipsSelectedWithText = false
        selectedChip = nil
        switch action {
        case .chip(let token):
            if token.category == .location || token.category == .kind {
                chips.removeAll { $0.category == token.category }
            }
            chips.append(token)
            chipsChanged()
        case .insert(let prefix):
            let text = fieldText
            let separator = text.isEmpty || text.last?.isWhitespace == true ? "" : " "
            setFieldText(text + separator + prefix)
            onQueryChange?(query, false)
        case .clear:
            chips.removeAll()
            chipsChanged()
        }
    }

    // MARK: - 키 처리

    // Enter·Esc·↑↓·Page Up/Down·←→·⌫. 한글 조합 중에 입력기가 쓴 키는 여기로 오지 않는다
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
        case #selector(NSResponder.moveLeft(_:)):
            return moveChipSelection(left: true, in: textView)
        case #selector(NSResponder.moveRight(_:)):
            return moveChipSelection(left: false, in: textView)
        case #selector(NSResponder.deleteBackward(_:)):
            return deleteBackwardIntoChips(in: textView)
        case #selector(NSResponder.insertNewline(_:)):
            if let hit = selectedHit { onOpen?(hit) }
        case #selector(NSResponder.cancelOperation(_:)):
            // 고른 칩이 있으면 선택만 풀고, 없으면 닫는다
            if selectedChip != nil {
                selectedChip = nil
                updateChipSelection()
            } else {
                onDismiss?()
            }
        default:
            return false
        }
        return true
    }

    // ⌘↩ Finder에서 보기, ⌘C 경로 복사, ⌘F 필터 메뉴, ⌘W·⌘Q 닫기
    // ⌘C는 검색어 일부를 직접 골라 둔 경우에만 글자를 복사한다. 열 때 전체 선택해 둔 검색어는 경로 복사를 막지 않는다
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, handleCommandKey(event.keyCode, modifiers: event.modifierFlags) else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // 키 코드와 수식키로 패널 동작을 실행한다. 처리하지 않은 조합이면 false (검색어 편집으로 넘긴다)
    private func handleCommandKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.command, .control, .option, .shift]) == .command else { return false }
        switch keyCode {
        case 36, 76:
            if let hit = selectedHit { onReveal?(hit) }
        case 8:
            let selection = searchField.currentEditor()?.selectedRange.length ?? 0
            let partialSelection = selection > 0 && selection < (searchField.currentEditor()?.string as NSString?)?.length ?? 0
            guard !partialSelection, let hit = selectedHit else { return false }
            onCopyPath?(hit)
        case 3:
            showFilterMenu()
        case 13, 12:
            onDismiss?()
        default:
            return false
        }
        return true
    }

    #if DEBUG
    /// 개발용: 키 창이 아니어도 필드 명령(`moveLeft:` 등)·글자 입력·⌘ 조합을 흉내 낸다 (mcapture-dev://debug/find-key)
    /// 시험 중 사용자가 다른 앱에서 치는 글자가 새어 들어오지 않도록 앱을 활성화하지 않고 쓴다
    func debugKey(command: String?, text: String?, keyCode: UInt16?, modifiers: String?) {
        guard let editor = searchField.currentEditor() as? NSTextView else {
            Log.findFile.error("find-key: 검색 필드가 편집 중이 아님")
            return
        }
        if let command {
            let selector = NSSelectorFromString(command)
            if !control(searchField, textView: editor, doCommandBy: selector) { editor.doCommand(by: selector) }
        }
        if let text {
            editor.insertText(text, replacementRange: editor.selectedRange())
        }
        if let keyCode {
            var flags: NSEvent.ModifierFlags = []
            for name in (modifiers ?? "").split(separator: ",") {
                switch name {
                case "cmd": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "opt": flags.insert(.option)
                case "ctrl": flags.insert(.control)
                default: break
                }
            }
            _ = handleCommandKey(keyCode, modifiers: flags)
        }
    }
    #endif

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

    // 키 안내를 폭에 들어가는 만큼 앞에서부터 남긴다 (문구, 폭)
    private static func fit(_ hints: [String], font: NSFont, width: CGFloat) -> (text: String, width: CGFloat) {
        var count = hints.count
        while count > 0 {
            let text = hints.prefix(count).joined(separator: "   ")
            let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 4
            if measured <= width { return (text, measured) }
            count -= 1
        }
        return ("", 0)
    }

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
