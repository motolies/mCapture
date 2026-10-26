import AppKit

/// 휴지통 이동 확인 카드에 보일 내용
struct DeletionCard {
    struct Row {
        let icon: NSImage?
        let name: String
        /// 폴더면 "폴더 · 최소 1,180개"
        let detail: String
        /// 상위 폴더 (~로 줄임)
        let location: String
    }

    var title: String
    var summary: String
    var rows: [Row]
    /// "외 9개 · 모두 보기" (없으면 nil)
    var moreText: String?
    /// 뺀 항목·경고 (주황 느낌표)
    var notes: [String]
    /// 많이 든 위치 (개수 입력 단계)
    var locations: String?
    /// 확인하려면 칠 항목 수 (nil이면 한 단계 확인)
    var countToType: Int?
}

/// 파일 찾기 창 안에서 목록 자리에 뜨는 휴지통 이동 확인 카드
///
/// 창이 키 창에서 벗어나면 닫히므로 NSAlert·시트 대신 창 안에 그린다. 바깥을 누르면 창과 함께 취소된다
final class DeletionCardView: FlippedView, NSTextFieldDelegate {
    enum Metrics {
        static let padding: CGFloat = 18
        static let top: CGFloat = 16
        static let iconSize: CGFloat = 28
        static let textX: CGFloat = padding + iconSize + 12
        static let rowHeight: CGFloat = 22
        static let lineHeight: CGFloat = 18
        static let buttonHeight: CGFloat = 28
    }

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onShowAll: (() -> Void)?

    /// 개수 입력 칸 (개수 입력 단계에서 첫 응답자)
    let countField = NSTextField()

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private var rowViews: [NSView] = []
    private let moreButton = NSButton()
    private var noteLabels: [NSTextField] = []
    private let locationsLabel = NSTextField(labelWithString: "")
    private let countPrompt = NSTextField(labelWithString: "항목이 많습니다. 확인하려면 항목 수를 입력하세요")
    private let footnote = NSTextField(labelWithString: "휴지통에서 되돌릴 수 있습니다.")
    private let cancelButton = NSButton(title: "취소", target: nil, action: nil)
    private let confirmButton = NSButton(title: "휴지통으로 이동", target: nil, action: nil)
    private var card: DeletionCard?
    private(set) var preferredHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        for label in [titleLabel, summaryLabel, locationsLabel, countPrompt, footnote] {
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        for label in [locationsLabel, countPrompt, footnote] {
            label.font = .systemFont(ofSize: label === footnote ? 11 : 12)
            label.textColor = .secondaryLabelColor
        }
        moreButton.isBordered = false
        moreButton.target = self
        moreButton.action = #selector(showAllClicked)
        countField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countField.placeholderString = "항목 수"
        countField.delegate = self
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked)
        confirmButton.hasDestructiveAction = true
        for button in [moreButton, cancelButton, confirmButton] {
            button.refusesFirstResponder = true
        }
        for view in [iconView, moreButton, countField, cancelButton, confirmButton] as [NSView] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("휴지통 이동 확인")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 개수 입력 단계에서 맞는 수를 쳤는지 (한 단계 확인이면 늘 true)
    var countMatches: Bool {
        guard let expected = card?.countToType else { return true }
        return Int(countField.stringValue.trimmingCharacters(in: .whitespaces)) == expected
    }

    /// 내용을 채우고 배치한다
    func configure(_ card: DeletionCard, width: CGFloat) {
        self.card = card
        let warning = card.countToType != nil
        iconView.image = NSImage(systemSymbolName: warning ? "exclamationmark.triangle.fill" : "trash", accessibilityDescription: nil)
        iconView.contentTintColor = warning ? .systemOrange : .secondaryLabelColor
        titleLabel.stringValue = card.title
        summaryLabel.stringValue = card.summary
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = card.rows.map(makeRow)
        rowViews.forEach(addSubview)
        moreButton.isHidden = card.moreText == nil
        moreButton.attributedTitle = NSAttributedString(string: card.moreText ?? "", attributes: [
            .foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 12),
        ])
        noteLabels.forEach { $0.removeFromSuperview() }
        noteLabels = card.notes.map { text in
            let label = NSTextField(labelWithString: "⚠︎ " + text)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .systemOrange
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            return label
        }
        locationsLabel.isHidden = card.locations == nil
        locationsLabel.stringValue = card.locations.map { "많이 든 위치  " + $0 } ?? ""
        countPrompt.isHidden = !warning
        countField.isHidden = !warning
        countField.stringValue = ""
        updateConfirmTitle()
        layoutCard(width: width)
        setAccessibilityLabel("휴지통 이동 확인: \(card.title) \(card.summary)")
    }

    /// 요약 줄만 바꾼다 (크기 계산이 끝났을 때)
    func setSummary(_ text: String) {
        card?.summary = text
        summaryLabel.stringValue = text
    }

    // 위에서부터: 아이콘·제목 / 요약 / 미리보기 줄 / 외 N개 / 경고 / 많이 든 위치 / 개수 입력 / 안내 / 단추
    private func layoutCard(width: CGFloat) {
        let textWidth = width - Metrics.textX - Metrics.padding
        iconView.frame = NSRect(x: Metrics.padding, y: Metrics.top, width: Metrics.iconSize, height: Metrics.iconSize)
        titleLabel.frame = NSRect(x: Metrics.textX, y: Metrics.top, width: textWidth, height: 20)
        summaryLabel.frame = NSRect(x: Metrics.textX, y: Metrics.top + 24, width: textWidth, height: 16)
        var y = Metrics.top + 50
        for row in rowViews {
            row.frame = NSRect(x: Metrics.textX, y: y, width: textWidth, height: Metrics.rowHeight)
            layoutRow(row)
            y += Metrics.rowHeight
        }
        if !moreButton.isHidden {
            moreButton.sizeToFit()
            moreButton.frame.origin = NSPoint(x: Metrics.textX - 2, y: y + 1)
            y += Metrics.rowHeight
        }
        y += 4
        for label in noteLabels {
            label.frame = NSRect(x: Metrics.textX, y: y, width: textWidth, height: 16)
            y += Metrics.lineHeight
        }
        if !locationsLabel.isHidden {
            locationsLabel.frame = NSRect(x: Metrics.textX, y: y, width: textWidth, height: 16)
            y += Metrics.lineHeight
        }
        if !countField.isHidden {
            y += 4
            countPrompt.sizeToFit()
            countPrompt.frame = NSRect(x: Metrics.textX, y: y + 3, width: min(countPrompt.frame.width, textWidth - 130), height: 16)
            countField.frame = NSRect(x: countPrompt.frame.maxX + 10, y: y, width: 110, height: 22)
            y += 28
        }
        footnote.frame = NSRect(x: Metrics.textX, y: y + 2, width: textWidth, height: 15)
        y += 22
        confirmButton.sizeToFit()
        cancelButton.sizeToFit()
        confirmButton.frame.size.width = max(96, confirmButton.frame.width)
        cancelButton.frame.size.width = max(96, cancelButton.frame.width)
        confirmButton.frame.origin = NSPoint(x: width - Metrics.padding - confirmButton.frame.width, y: y)
        cancelButton.frame.origin = NSPoint(x: confirmButton.frame.minX - 12 - cancelButton.frame.width, y: y)
        preferredHeight = y + Metrics.buttonHeight + Metrics.top
    }

    // 미리보기 한 줄: 아이콘 · 이름 · 설명 · 위치
    private func makeRow(_ row: DeletionCard.Row) -> NSView {
        let view = FlippedView()
        let icon = NSImageView(image: row.icon ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: row.name)
        name.font = .systemFont(ofSize: 12)
        let detail = NSTextField(labelWithString: row.detail)
        let location = NSTextField(labelWithString: row.location)
        for label in [detail, location] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        name.lineBreakMode = .byTruncatingMiddle
        detail.lineBreakMode = .byTruncatingTail
        location.lineBreakMode = .byTruncatingMiddle
        [icon, name, detail, location].forEach(view.addSubview)
        return view
    }

    // 미리보기 줄 안의 열 배치 (이름 40% · 설명 22% · 위치 나머지)
    private func layoutRow(_ row: NSView) {
        let views = row.subviews
        guard views.count == 4 else { return }
        let width = row.bounds.width
        views[0].frame = NSRect(x: 0, y: 3, width: 16, height: 16)
        let nameWidth = (width - 22) * 0.4
        let detailWidth = (width - 22) * 0.22
        views[1].frame = NSRect(x: 22, y: 3, width: nameWidth - 8, height: 16)
        views[2].frame = NSRect(x: 22 + nameWidth, y: 4, width: detailWidth - 8, height: 15)
        views[3].frame = NSRect(x: 22 + nameWidth + detailWidth, y: 4, width: width - 22 - nameWidth - detailWidth, height: 15)
    }

    // 이동 단추: 빨간 글자(대비를 맞춘 색), 개수 입력 단계는 맞게 칠 때까지 끔
    private func updateConfirmTitle() {
        confirmButton.isEnabled = countMatches
        confirmButton.attributedTitle = NSAttributedString(string: "휴지통으로 이동", attributes: [
            .foregroundColor: confirmButton.isEnabled ? Self.destructiveColor : NSColor.disabledControlTextColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
    }

    /// 파괴 동작 글자색. systemRed는 흰 바탕에서 대비가 약 3.6:1이라 더 진한 빨강을 쓴다 (밝게 #D70015 / 어둡게 #FF6961)
    static let destructiveColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0x69 / 255, blue: 0x61 / 255, alpha: 1)
            : NSColor(srgbRed: 0xD7 / 255, green: 0, blue: 0x15 / 255, alpha: 1)
    }

    func controlTextDidChange(_ obj: Notification) {
        updateConfirmTitle()
    }

    // 개수 칸: ↩는 맞으면 확정, Esc는 취소
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if countMatches { onConfirm?() } else { NSSound.beep() }
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        default:
            return false
        }
        return true
    }

    @objc private func cancelClicked() { onCancel?() }
    @objc private func showAllClicked() { onShowAll?() }

    @objc private func confirmClicked() {
        if countMatches { onConfirm?() }
    }
}
