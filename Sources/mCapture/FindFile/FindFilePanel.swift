import AppKit
import MCaptureCore

/// Spotlight처럼 화면 위쪽에 뜨는 파일 찾기 창. 검색 줄(필터 칩 · 검색 필드 · 필터 단추) · 결과 목록 · 선택 막대 · 상태 줄로 이루어진다
///
/// 포커스는 늘 검색 필드에 두고 ↑↓로 결과를 고른다. Enter·Esc·↑↓·⇥는 필드 에디터의 명령(doCommandBy)으로 받아
/// 한글 조합을 끝내는 Enter가 파일을 여는 일이 없다. ⌘ 조합은 한글 자판에서도 되도록 키 코드로 판별한다
///
/// 필터 칩은 검색어의 일부(`ext:` 등)를 나눠 보여 주기만 한다. 검색어는 늘 칩 원문 + 필드 글자다(`query`)
/// 체크 상태는 컨트롤러가 경로로 들고 바뀔 때마다 `update(selection:)`으로 넘긴다. 패널은 체크 요청만 보낸다
final class FindFilePanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuDelegate {
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
        /// 체크가 있을 때 목록 아래에 보이는 선택 막대
        static let barHeight: CGFloat = 40
    }

    /// (검색어, 한글 조합 중인지)
    var onQueryChange: ((String, Bool) -> Void)?
    var onOpen: ((SearchHit) -> Void)?
    /// Finder에서 보기 (체크가 있으면 체크한 경로들)
    var onReveal: (([String]) -> Void)?
    /// 경로 복사 (체크가 있으면 체크한 경로들)
    var onCopyPaths: (([String]) -> Void)?
    /// 결과를 체크(true)하거나 해제(false)한다
    var onCheck: (([SearchHit], Bool) -> Void)?
    /// 일치하는 모든 항목을 불러와 체크한다
    var onCheckAllMatches: (() -> Void)?
    var onClearChecks: (() -> Void)?
    /// 체크한 항목만 목록에 보인다
    var onShowSelection: (() -> Void)?
    /// 휴지통 이동 확인을 연다 (nil이면 체크한 항목, 아니면 그 결과들)
    var onRequestDelete: (([SearchHit]?) -> Void)?
    var onConfirmDelete: (() -> Void)?
    var onCancelDelete: (() -> Void)?
    /// 확인 카드의 "모두 보기": 확인을 닫고 체크한 항목만 보인다
    var onReviewDelete: (() -> Void)?
    var onStopDeletion: (() -> Void)?
    var onUndoDeletion: (() -> Void)?
    /// Esc·⌘W·⌘Q로 닫을 때
    var onDismiss: (() -> Void)?

    private let searchField = NSTextField()
    private let fieldEditor = SearchFieldEditor(frame: .zero)
    private let filterButton = NSButton()
    private let overflowLabel = NSTextField(labelWithString: "")
    private let tableView = ResultTableView()
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

    /// 체크한 항목 (컨트롤러가 넘겨준 사본)
    private(set) var selection = PathSelection()
    /// 일치하는 모든 항목을 불러와 체크한 상태
    private var allMatchesSelected = false
    /// 지금 검색의 전체 일치 수 (목록은 상위 몇 개만)
    private var totalMatches = 0
    /// ⇧⌘A로 보이는 결과를 모두 체크한 직후 (한 번 더 누르면 일치 전체)
    private var visibleCheckedAll = false
    /// ⇧클릭 범위의 기준 행
    private var checkAnchor: Int?

    private let barSeparator = NSBox()
    private let barCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let barCountLabel = NSTextField(labelWithString: "")
    private let barOutsideButton = NSButton()
    private let barAllMatchesButton = NSButton()
    private let barNoteLabel = NSTextField(labelWithString: "")
    private let barRevealButton = NSButton(title: "Finder에서 보기", target: nil, action: nil)
    private let barCopyButton = NSButton(title: "경로 복사", target: nil, action: nil)
    private let barTrashButton = NSButton(title: "휴지통으로 이동…", target: nil, action: nil)
    private let barClearButton = NSButton()

    private let cardView = DeletionCardView()
    private let bannerView = DeletionBannerView()
    /// 떠 있는 휴지통 확인 카드
    private var card: DeletionCard?
    /// 카드가 뜬 시각. 그 직후의 ⌘⌫는 확정으로 받지 않는다 (두 번 연타·누르고 있기 방지)
    private var cardShownAt: ContinuousClock.Instant?
    private static let confirmArmingDelay = Duration.milliseconds(500)
    /// 선택 막대 자리에 보일 휴지통 이동 진행·결과
    private var banner: DeletionBanner?

    /// 상태 줄 오른쪽 키 안내 (앞쪽이 중요, 폭이 모자라면 뒤에서부터 뺀다)
    private var hints: [String] {
        if let card {
            return card.countToType == nil ? ["↩ 취소", "⌘⌫ 휴지통으로 이동", "Esc 취소"] : ["항목 수를 입력하고 ↩", "Esc 취소"]
        }
        if banner?.canUndo == true { return ["⌘Z 되돌리기", "↩ 열기", "⇥ 체크", "⌘F 필터"] }
        return selection.isEmpty
            ? ["↩ 열기", "⌘↩ Finder에서 보기", "⌘C 경로 복사", "⇥ 체크", "⌘F 필터"]
            : ["⇥ 체크", "⌘⌫ 휴지통", "⇧↓ 이어서 체크", "⇧⌘A 모두 체크", "⌥⌘A 해제"]
    }

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
        fieldEditor.canChangeText = { [weak self] in
            self?.card == nil
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
        tableView.onModifiedClick = { [weak self] row, modifiers in
            self?.modifiedClick(row: row, modifiers: modifiers) ?? false
        }
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        tableView.menu = rowMenu
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
        buildSelectionBar()
        cardView.isHidden = true
        cardView.onCancel = { [weak self] in self?.onCancelDelete?() }
        cardView.onConfirm = { [weak self] in self?.onConfirmDelete?() }
        cardView.onShowAll = { [weak self] in self?.onReviewDelete?() }
        container.addSubview(cardView)
        bannerView.isHidden = true
        bannerView.onStop = { [weak self] in self?.onStopDeletion?() }
        bannerView.onUndo = { [weak self] in self?.onUndoDeletion?() }
        bannerView.onClose = { [weak self] in self?.showBanner(nil) }
        container.addSubview(bannerView)
        layoutContent()
    }

    // 선택 막대: [3상태 체크박스] N개 선택 · 목록 밖 N개 · 일치 전체 선택 … [Finder에서 보기] [경로 복사] ×
    private func buildSelectionBar() {
        barSeparator.boxType = .separator
        barCheckbox.allowsMixedState = true
        barCheckbox.target = self
        barCheckbox.action = #selector(barCheckboxClicked)
        barCheckbox.toolTip = "보이는 결과 모두 체크 (⇧⌘A)"
        barCountLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        barNoteLabel.font = .systemFont(ofSize: 11)
        barNoteLabel.textColor = .secondaryLabelColor
        barNoteLabel.lineBreakMode = .byTruncatingTail
        for (button, action) in [(barOutsideButton, #selector(showSelectionClicked)), (barAllMatchesButton, #selector(allMatchesClicked))] {
            button.isBordered = false
            button.target = self
            button.action = action
        }
        for (button, action) in [(barRevealButton, #selector(revealClicked)), (barCopyButton, #selector(copyClicked)),
                                 (barTrashButton, #selector(trashClicked))] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = action
        }
        barTrashButton.hasDestructiveAction = true
        barTrashButton.attributedTitle = NSAttributedString(string: "휴지통으로 이동…", attributes: [
            .foregroundColor: DeletionCardView.destructiveColor, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        barTrashButton.toolTip = "⌘⌫"
        barClearButton.isBordered = false
        barClearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "체크 모두 해제")
        barClearButton.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        barClearButton.contentTintColor = .secondaryLabelColor
        barClearButton.toolTip = "체크 모두 해제 (⌥⌘A)"
        barClearButton.target = self
        barClearButton.action = #selector(clearClicked)
        for view in [barSeparator, barCheckbox, barCountLabel, barOutsideButton, barAllMatchesButton, barNoteLabel,
                     barRevealButton, barCopyButton, barTrashButton, barClearButton] as [NSView] {
            if let button = view as? NSButton { button.refusesFirstResponder = true }
            view.isHidden = true
            container.addSubview(view)
        }
    }

    // 결과 수에 맞춰 높이를 정하고 위쪽 모서리를 고정한 채 하위 뷰를 배치한다
    // 확인 카드가 떠 있으면 목록 자리를 카드가 대신하고(높이는 지금 목록보다 작아지지 않게), 막대 자리는 배너가 대신한다
    private func layoutContent() {
        let rows = min(hits.count, Metrics.maxVisibleRows)
        var listHeight = rows > 0 ? 1 + CGFloat(rows) * Metrics.rowHeight : 0
        if card != nil {
            listHeight = 1 + max(cardView.preferredHeight, listHeight - 1)
        }
        let showsBanner = card == nil && banner != nil
        let showsBar = card == nil && !showsBanner && !selection.isEmpty
        let barHeight = showsBanner || showsBar ? 1 + Metrics.barHeight : 0
        let height = Metrics.searchHeight + listHeight + barHeight + Metrics.statusHeight
        let width = Metrics.width
        if isVisible || topEdge > 0 {
            setFrame(NSRect(x: frame.minX, y: topEdge - height, width: width, height: height), display: true)
        } else {
            setContentSize(NSSize(width: width, height: height))
        }
        layoutSearchRow()
        separator.isHidden = listHeight == 0
        separator.frame = NSRect(x: 0, y: Metrics.searchHeight, width: width, height: 1)
        scrollView.isHidden = rows == 0 || card != nil
        scrollView.frame = NSRect(x: 0, y: Metrics.searchHeight + 1, width: width, height: CGFloat(rows) * Metrics.rowHeight)
        tableView.tableColumns.first?.width = width
        cardView.isHidden = card == nil
        cardView.frame = NSRect(x: 0, y: Metrics.searchHeight + 1, width: width, height: max(0, listHeight - 1))
        layoutSelectionBar(y: Metrics.searchHeight + listHeight, visible: showsBar)
        bannerView.isHidden = !showsBanner
        if showsBanner, let banner {
            bannerView.frame = NSRect(x: 0, y: Metrics.searchHeight + listHeight + 1, width: width, height: Metrics.barHeight)
            bannerView.configure(banner, width: width, height: Metrics.barHeight)
            barSeparator.isHidden = false
            barSeparator.frame = NSRect(x: 0, y: Metrics.searchHeight + listHeight, width: width, height: 1)
        }
        searchField.alphaValue = card == nil ? 1 : 0.5
        layoutStatusRow(y: height - Metrics.statusHeight + (Metrics.statusHeight - 15) / 2)
    }

    // 선택 막대 내용과 배치 (체크가 없거나 카드·배너가 대신하면 숨긴다)
    private func layoutSelectionBar(y: CGFloat, visible: Bool) {
        let views: [NSView] = [barSeparator, barCheckbox, barCountLabel, barOutsideButton, barAllMatchesButton, barNoteLabel,
                               barRevealButton, barCopyButton, barTrashButton, barClearButton]
        guard visible else {
            views.forEach { $0.isHidden = true }
            return
        }
        let width = Metrics.width
        let midY = y + 1 + Metrics.barHeight / 2
        barSeparator.frame = NSRect(x: 0, y: y, width: width, height: 1)

        // 보이는 결과 중 체크한 수 → 3상태 체크박스
        let checkedVisible = hits.count { selection.contains($0.path) }
        barCheckbox.state = checkedVisible == 0 ? .off : (checkedVisible == hits.count ? .on : .mixed)
        barCheckbox.isEnabled = !hits.isEmpty
        barCheckbox.sizeToFit()
        barCheckbox.frame.origin = NSPoint(x: Metrics.padding - 2, y: midY - barCheckbox.frame.height / 2)

        barCountLabel.stringValue = allMatchesSelected ? "\(selection.count.formatted())개 모두 선택됨" : "\(selection.count.formatted())개 선택"
        barCountLabel.sizeToFit()
        barCountLabel.frame.origin = NSPoint(x: barCheckbox.frame.maxX + 6, y: midY - barCountLabel.frame.height / 2)
        var x = barCountLabel.frame.maxX + 8

        // 지금 목록에 없는 체크 → "목록 밖 N개" (누르면 체크한 항목만 보기)
        let outside = selection.count - checkedVisible
        barOutsideButton.isHidden = outside <= 0
        if outside > 0 {
            barOutsideButton.attributedTitle = Self.linkTitle("목록 밖 \(outside.formatted())개")
            barOutsideButton.toolTip = "체크한 항목만 보기"
            barOutsideButton.sizeToFit()
            barOutsideButton.frame.origin = NSPoint(x: x, y: midY - barOutsideButton.frame.height / 2)
            x = barOutsideButton.frame.maxX + 8
        }

        // 보이는 결과를 모두 체크했고 일치가 더 있으면 → 일치 전체 선택 링크 (상한을 넘으면 안내만)
        let offerAll = !allMatchesSelected && totalMatches > hits.count && checkedVisible > 0
            && (checkedVisible == hits.count || visibleCheckedAll)
        barAllMatchesButton.isHidden = !offerAll || totalMatches > selection.limit
        barNoteLabel.isHidden = !(offerAll && totalMatches > selection.limit)
        if offerAll, totalMatches <= selection.limit {
            barAllMatchesButton.attributedTitle = Self.linkTitle("일치하는 \(totalMatches.formatted())개 모두 선택")
            barAllMatchesButton.toolTip = "⇧⌘A"
            barAllMatchesButton.sizeToFit()
            barAllMatchesButton.frame.origin = NSPoint(x: x, y: midY - barAllMatchesButton.frame.height / 2)
            x = barAllMatchesButton.frame.maxX + 8
        }

        // 오른쪽 단추들 (오른쪽부터)
        var right = width - Metrics.padding
        barClearButton.frame = NSRect(x: right - 18, y: midY - 9, width: 18, height: 18)
        right = barClearButton.frame.minX - 10
        for button in [barTrashButton, barCopyButton, barRevealButton] {
            button.sizeToFit()
            button.frame.origin = NSPoint(x: right - button.frame.width, y: midY - button.frame.height / 2)
            right = button.frame.minX - 6
        }
        if !barNoteLabel.isHidden {
            barNoteLabel.stringValue = "일치 \(totalMatches.formatted())개 · \(selection.limit.formatted())개까지만 고를 수 있습니다"
            barNoteLabel.frame = NSRect(x: x, y: midY - 7, width: max(0, right - 8 - x), height: 15)
        }
        for view in [barSeparator, barCheckbox, barCountLabel, barRevealButton, barCopyButton, barTrashButton, barClearButton] as [NSView] {
            view.isHidden = false
        }
    }

    // 링크처럼 보이는 단추 글자
    private static func linkTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 12)])
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
    /// activate가 false면 앱을 활성화하지 않고 띄우기만 한다 (개발용 시험: 키 창이 아니라 다른 앱을 눌러도 닫히지 않음)
    func present(on screen: NSScreen?, activate: Bool = true) {
        if let area = (screen ?? NSScreen.underMouse ?? NSScreen.main)?.visibleFrame {
            let maxHeight = Metrics.searchHeight + 1 + CGFloat(Metrics.maxVisibleRows) * Metrics.rowHeight
                + 1 + Metrics.barHeight + Metrics.statusHeight
            topEdge = (area.midY + maxHeight / 2).rounded()
            setFrameOrigin(NSPoint(x: (area.midX - Metrics.width / 2).rounded(), y: topEdge - frame.height))
            layoutContent()
        }
        // 비활성 패널이어도 한글 입력기가 확실히 붙도록 앱을 활성화한 뒤 키 창으로 만든다 (영역 선택 오버레이와 같은 순서)
        if activate {
            NSApp.activate()
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
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

    /// 결과를 바꾸고 첫 줄을 고른다. preserving이 있으면 그 경로의 줄을 다시 고른다 (인덱스가 바뀌어 다시 찾을 때)
    func show(_ hits: [SearchHit], total: Int? = nil, preserving path: String? = nil) {
        self.hits = hits
        totalMatches = total ?? hits.count
        if path == nil {
            visibleCheckedAll = false
            checkAnchor = nil
        }
        tableView.reloadData()
        if !hits.isEmpty {
            let row = path.flatMap { path in hits.firstIndex { $0.path == path } } ?? 0
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
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

    // MARK: - 체크

    /// 체크 상태를 바꾼다 (컨트롤러가 체크를 바꿀 때마다 부른다). 보이는 행의 표시와 선택 막대를 맞춘다
    func update(selection: PathSelection, allMatchesSelected: Bool) {
        let wasEmpty = self.selection.isEmpty
        let changed = self.selection != selection
        self.selection = selection
        self.allMatchesSelected = allMatchesSelected
        if selection.isEmpty { visibleCheckedAll = false }
        // 새로 체크하면 지난 휴지통 결과 배너는 내린다 (진행 중이면 그대로)
        if changed, let banner, banner.tone != .progress { self.banner = nil }
        refreshVisibleChecks()
        if wasEmpty != selection.isEmpty || !selection.isEmpty || changed { layoutContent() }
    }

    // 보이는 행의 체크박스·틴트만 다시 그린다 (행을 다시 만들지 않아 스크롤·선택이 그대로)
    private func refreshVisibleChecks() {
        let showsCheckbox = !selection.isEmpty
        tableView.enumerateAvailableRowViews { rowView, row in
            guard hits.indices.contains(row) else { return }
            let check = checkState(of: hits[row])
            (rowView as? ResultRowView)?.isChecked = check == .checked
            (rowView.view(atColumn: 0) as? ResultCellView)?.updateCheck(check, showsCheckbox: showsCheckbox)
        }
    }

    // 결과 한 줄의 체크 표시
    private func checkState(of hit: SearchHit) -> ResultCellView.Check {
        switch selection.coverage(of: hit.path) {
        case .explicit: .checked
        case .implied: .implied
        case .none: .unchecked
        }
    }

    // 한 줄의 체크를 뒤집는다
    private func toggleCheck(row: Int) {
        guard hits.indices.contains(row) else { return }
        let hit = hits[row]
        let checking = !selection.contains(hit.path)
        onCheck?([hit], checking)
        checkAnchor = row
        announce(checking ? "체크함, \(hit.name)" : "체크 해제, \(hit.name)")
    }

    // 지금 커서 행을 체크하고 delta만큼 옮긴다 (⇧↓·⇧↑: 지나가는 줄을 체크)
    private func extendCheck(by delta: Int) {
        let row = tableView.selectedRow
        guard hits.indices.contains(row) else { return }
        let next = max(0, min(hits.count - 1, row + delta))
        let range = min(row, next)...max(row, next)
        onCheck?(range.map { hits[$0] }, true)
        moveSelection(by: delta)
        announce("\(selection.count)개 선택")
    }

    // ⇧⌘A·막대 체크박스: 보이는 결과를 모두 체크하고, 이미 다 체크했으면 일치하는 모든 항목으로 넓힌다
    private func checkAll() {
        guard !hits.isEmpty else { return }
        let allVisibleChecked = hits.allSatisfy { selection.contains($0.path) }
        if (allVisibleChecked || visibleCheckedAll), totalMatches > hits.count, !allMatchesSelected {
            onCheckAllMatches?()
            return
        }
        onCheck?(hits, true)
        visibleCheckedAll = true
        layoutContent()
    }

    // ⌘클릭은 그 줄 체크 뒤집기, ⇧클릭은 기준 줄부터 그 줄까지 체크
    private func modifiedClick(row: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift), let anchor = checkAnchor, hits.indices.contains(anchor) {
            let range = min(anchor, row)...max(anchor, row)
            onCheck?(range.map { hits[$0] }, true)
        } else {
            toggleCheck(row: row)
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return true
    }

    // 동작 대상 경로: 체크가 있으면 체크한 항목, 없으면 커서 행
    private var targetPaths: [String] {
        if !selection.isEmpty { return selection.orderedItems.map(\.path) }
        return selectedHit.map { [$0.path] } ?? []
    }

    // 키보드로 체크할 때 VoiceOver에 알린다 (포커스는 검색 필드라 행 변화를 읽지 않는다)
    private func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc private func barCheckboxClicked() {
        if hits.allSatisfy({ selection.contains($0.path) }) {
            onCheck?(hits, false)
        } else {
            onCheck?(hits, true)
            visibleCheckedAll = true
        }
        layoutContent()
    }

    // MARK: - 휴지통 확인·배너

    /// 휴지통 이동 확인 카드를 목록 자리에 띄운다. 개수 입력 단계면 개수 칸에 포커스를 둔다
    func showConfirmation(_ card: DeletionCard) {
        self.card = card
        banner = nil
        cardShownAt = .now
        cardView.configure(card, width: Metrics.width)
        layoutContent()
        if card.countToType != nil { makeFirstResponder(cardView.countField) }
    }

    /// 확인 카드의 요약 줄을 바꾼다 (크기 계산이 끝났을 때)
    func updateConfirmationSummary(_ text: String) {
        cardView.setSummary(text)
    }

    /// 확인 카드를 닫고 포커스를 검색 필드로 돌려준다 (커서는 끝에)
    func hideConfirmation() {
        guard card != nil else { return }
        card = nil
        cardShownAt = nil
        layoutContent()
        if searchField.currentEditor() == nil {
            makeFirstResponder(searchField)
            let length = (fieldText as NSString).length
            (searchField.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: length, length: 0))
        }
    }

    var isConfirming: Bool { card != nil }

    /// 진행·결과 배너를 선택 막대 자리에 보인다 (nil이면 숨김)
    func showBanner(_ banner: DeletionBanner?) {
        self.banner = banner
        layoutContent()
    }

    /// 휴지통으로 옮긴 결과를 목록에서 바로 뺀다 (인덱스 반영을 기다리지 않음). 폴더면 그 안도 뺀다
    func removeHits(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        let cursor = selectedHit?.path
        let kept = hits.filter { hit in
            !paths.contains(hit.path) && !paths.contains { hit.path.hasPrefix($0 + "/") }
        }
        let removed = hits.count - kept.count
        let previousRow = tableView.selectedRow
        hits = kept
        totalMatches = max(0, totalMatches - removed)
        tableView.reloadData()
        if !hits.isEmpty {
            let row = cursor.flatMap { path in hits.firstIndex { $0.path == path } } ?? min(max(previousRow, 0), hits.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        layoutContent()
    }

    // ⌘⌫: 카드가 떠 있으면 확정(뜬 직후·키 반복은 무시), 아니면 체크한 항목의 확인을 연다
    private func trashKey(isRepeat: Bool) -> Bool {
        if card != nil {
            guard !isRepeat, let shown = cardShownAt, ContinuousClock.now - shown >= Self.confirmArmingDelay,
                  cardView.countMatches else { return true }
            onConfirmDelete?()
            return true
        }
        guard !selection.isEmpty else { return false }
        onRequestDelete?(nil)
        return true
    }

    @objc private func trashClicked() { onRequestDelete?(nil) }
    @objc private func showSelectionClicked() { onShowSelection?() }
    @objc private func allMatchesClicked() { onCheckAllMatches?() }
    @objc private func revealClicked() { onReveal?(targetPaths) }
    @objc private func copyClicked() { onCopyPaths?(targetPaths) }
    @objc private func clearClicked() { onClearChecks?() }

    // MARK: - 우클릭 메뉴

    // 누른 줄의 메뉴를 채운다. 체크한 줄을 눌렀으면 동작은 체크한 항목 전체에 걸린다 (Finder 방식)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard hits.indices.contains(row) else { return }
        let hit = hits[row]
        let checked = selection.contains(hit.path)
        let paths = checked && selection.count > 1 ? selection.orderedItems.map(\.path) : [hit.path]
        let suffix = paths.count > 1 ? " (\(paths.count)개)" : ""
        menu.addItem(rowMenuItem("열기") { [weak self] in self?.onOpen?(hit) })
        menu.addItem(rowMenuItem("Finder에서 보기" + suffix) { [weak self] in self?.onReveal?(paths) })
        menu.addItem(rowMenuItem("경로 복사" + suffix) { [weak self] in self?.onCopyPaths?(paths) })
        menu.addItem(.separator())
        menu.addItem(rowMenuItem(checked ? "체크 해제" : "체크") { [weak self] in
            guard let self, let index = hits.firstIndex(where: { $0.path == hit.path }) else { return }
            toggleCheck(row: index)
        })
        let folder = hit.isDirectory ? hit.path : (hit.path as NSString).deletingLastPathComponent
        menu.addItem(rowMenuItem("이 폴더 안에서 찾기") { [weak self] in self?.addLocationChip(folder) })
        menu.addItem(.separator())
        let trashSuffix = checked && selection.count > 1 ? " (\(selection.count)개)" : ""
        menu.addItem(rowMenuItem("휴지통으로 이동…" + trashSuffix) { [weak self] in
            self?.onRequestDelete?(checked ? nil : [hit])
        })
    }

    // 클로저를 실행하는 메뉴 항목
    private func rowMenuItem(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(rowMenuChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        return item
    }

    @objc private func rowMenuChosen(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
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
        // 타이핑하면 지난 휴지통 결과 배너는 내린다 (⌘Z는 다시 검색어 실행 취소로)
        if let banner, banner.tone != .progress { showBanner(nil) }
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
            addChip(token)
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

    // 칩을 추가한다. 위치·종류는 같은 범주 칩을 바꾼다 (위치 두 개는 AND라 결과가 비기 쉽다)
    private func addChip(_ token: FilterToken) {
        chipsSelectedWithText = false
        selectedChip = nil
        if token.category == .location || token.category == .kind {
            chips.removeAll { $0.category == token.category }
        }
        chips.append(token)
        chipsChanged()
    }

    /// 그 폴더 아래에서 찾도록 위치 칩을 둔다 (우클릭 "이 폴더 안에서 찾기")
    func addLocationChip(_ folder: String) {
        addChip(.location(folder, home: NSHomeDirectory()))
    }

    // MARK: - 키 처리

    // Enter·Esc·↑↓·Page Up/Down·←→·⌫·⇥·⇧↑↓. 한글 조합 중에 입력기가 쓴 키는 여기로 오지 않는다
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // 확인 카드가 떠 있으면 ↩·Esc는 취소(기본 단추), 나머지 명령은 먹는다 (↩ = 열기 습관이 삭제로 이어지지 않게)
        if card != nil {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
                onCancelDelete?()
            default:
                break
            }
            return true
        }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.insertTab(_:)):
            // ⇥: 커서 행 체크를 뒤집고 아래로 (fzf --multi). 포커스가 검색 필드를 떠나지 않게 늘 먹는다
            toggleCheck(row: tableView.selectedRow)
            moveSelection(by: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            toggleCheck(row: tableView.selectedRow)
            moveSelection(by: -1)
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            extendCheck(by: 1)
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            extendCheck(by: -1)
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

    // ⌘↩ Finder에서 보기, ⌘C 경로 복사(체크가 있으면 체크한 항목), ⌘F 필터 메뉴, ⇧⌘A 모두 체크, ⌥⌘A 체크 해제, ⌘W·⌘Q 닫기
    // ⌘C는 검색어 일부를 직접 골라 둔 경우에만 글자를 복사한다. 열 때 전체 선택해 둔 검색어는 경로 복사를 막지 않는다
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isKeyWindow, handleCommandKey(event.keyCode, modifiers: event.modifierFlags, isRepeat: event.isARepeat) else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // 키 코드와 수식키로 패널 동작을 실행한다. 처리하지 않은 조합이면 false (검색어 편집으로 넘긴다)
    // ⌘⌫ 휴지통(체크가 있을 때만, 없으면 검색어 줄 지우기), ⌘Z 결과 배너가 보이면 되돌리기
    private func handleCommandKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool = false) -> Bool {
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if modifiers == .command, keyCode == 51 {
            return trashKey(isRepeat: isRepeat)
        }
        if card != nil {
            // 확인 중에는 닫기만 받고 나머지 ⌘ 조합은 먹는다
            if modifiers == .command, keyCode == 13 || keyCode == 12 { onDismiss?() }
            return !modifiers.isEmpty
        }
        if modifiers == .command, keyCode == 6, banner?.canUndo == true {
            onUndoDeletion?()
            return true
        }
        if keyCode == 0, modifiers == [.command, .shift] {
            checkAll()
            return true
        }
        if keyCode == 0, modifiers == [.command, .option] {
            onClearChecks?()
            return true
        }
        guard modifiers == .command else { return false }
        switch keyCode {
        case 36, 76:
            let paths = targetPaths
            if !paths.isEmpty { onReveal?(paths) }
        case 8:
            let selected = searchField.currentEditor()?.selectedRange.length ?? 0
            let partialSelection = selected > 0 && selected < (searchField.currentEditor()?.string as NSString?)?.length ?? 0
            let paths = targetPaths
            guard !partialSelection, !paths.isEmpty else { return false }
            onCopyPaths?(paths)
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
        // 지금 편집 중인 칸 (검색 필드, 개수 입력 단계면 개수 칸)
        guard let editor = firstResponder as? NSTextView else {
            Log.findFile.error("find-key: 편집 중인 칸이 없음")
            return
        }
        let field = (editor.delegate as? NSTextField) ?? searchField
        if let command {
            // 행 클릭 흉내: click:행[:cmd|shift]
            if command.hasPrefix("click:") {
                let parts = command.split(separator: ":")
                if parts.count >= 2, let row = Int(parts[1]) {
                    let modifiers: NSEvent.ModifierFlags = parts.count > 2 ? (parts[2] == "shift" ? .shift : .command) : .command
                    _ = modifiedClick(row: row, modifiers: modifiers)
                }
                return
            }
            let selector = NSSelectorFromString(command)
            let handled = field === cardView.countField
                ? cardView.control(field, textView: editor, doCommandBy: selector)
                : control(searchField, textView: editor, doCommandBy: selector)
            if !handled { editor.doCommand(by: selector) }
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
        let hit = hits[row]
        cell.configure(hit, check: checkState(of: hit), showsCheckbox: !selection.isEmpty)
        cell.onCheckboxClick = { [weak self] in
            guard let self, let index = hits.firstIndex(where: { $0.path == hit.path }) else { return }
            toggleCheck(row: index)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ResultRowView()
        rowView.isChecked = hits.indices.contains(row) && selection.contains(hits[row].path)
        return rowView
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
