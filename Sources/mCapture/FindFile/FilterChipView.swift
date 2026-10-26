import AppKit
import MCaptureCore

/// 검색 줄 왼쪽의 필터 칩 하나: 범주 이름(굵게) · 값. 범주마다 배경색이 다르고, 마우스를 올리면 ×가 나온다
///
/// 포커스는 늘 검색 필드에 있어야 하므로 첫 응답자가 되지 않는다. 클릭은 선택, 더블클릭은 글자로 되돌리기
final class FilterChipView: NSView {
    enum Metrics {
        static let height: CGFloat = 24
        static let cornerRadius: CGFloat = 6
        /// 라벨 셀의 안쪽 여백 2pt를 더하면 보이는 여백은 8pt
        static let padding: CGFloat = 6
        static let gap: CGFloat = 0
        static let maxWidth: CGFloat = 180
        static let removeSize: CGFloat = 14
    }

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRemove: (() -> Void)?

    private(set) var token: FilterToken
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateColors()
            needsDisplay = true
        }
    }
    private var isHovered = false {
        didSet {
            removeButton.isHidden = !isHovered
            needsLayout = true
            needsDisplay = true
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()

    init(token: FilterToken) {
        self.token = token
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.lineBreakMode = .byTruncatingMiddle
        for label in [titleLabel, valueLabel] {
            label.cell?.usesSingleLineMode = true
            addSubview(label)
        }
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "필터 지우기")
        removeButton.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        removeButton.isBordered = false
        removeButton.refusesFirstResponder = true
        removeButton.isHidden = true
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        addSubview(removeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(token)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 칩 내용을 바꾼다
    func update(_ token: FilterToken) {
        self.token = token
        titleLabel.stringValue = token.category.title
        valueLabel.stringValue = token.value
        toolTip = token.isInvalid ? "잘못된 정규식: \(token.raw)" : token.raw
        setAccessibilityLabel("필터: \(token.category.title) \(token.value)")
        updateColors()
        needsLayout = true
        needsDisplay = true
    }

    /// 내용에 맞는 폭 (최대 폭에서 값을 가운데 줄임)
    var preferredWidth: CGFloat {
        min(Metrics.maxWidth, Metrics.padding * 2 + Self.labelWidth(titleLabel) + Metrics.gap + Self.labelWidth(valueLabel))
    }

    // 라벨이 글자를 자르지 않는 폭: 글자 폭 + 셀 좌우 안쪽 여백(2pt씩)
    private static func labelWidth(_ label: NSTextField) -> CGFloat {
        let font = label.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        return ceil((label.stringValue as NSString).size(withAttributes: [.font: font]).width) + 4
    }

    override var acceptsFirstResponder: Bool { false }

    // 프레임만 바뀌어도 글자 배치를 다시 한다 (자동 레이아웃을 쓰지 않아 저절로 다시 배치되지 않는다)
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let titleWidth = Self.labelWidth(titleLabel)
        let labelHeight = ceil(valueLabel.intrinsicContentSize.height)
        let y = (bounds.height - labelHeight) / 2
        titleLabel.frame = NSRect(x: Metrics.padding, y: y, width: titleWidth, height: labelHeight)
        let valueX = titleLabel.frame.maxX + Metrics.gap
        // 마우스를 올리면 오른쪽 끝을 ×에 내준다 (칩 폭은 그대로라 옆 칩이 움직이지 않는다)
        let trailing = isHovered ? Metrics.removeSize + 4 : Metrics.padding
        valueLabel.frame = NSRect(x: valueX, y: y, width: max(0, bounds.width - valueX - trailing), height: labelHeight)
        removeButton.frame = NSRect(x: bounds.width - Metrics.removeSize - 4, y: (bounds.height - Metrics.removeSize) / 2,
                                    width: Metrics.removeSize, height: Metrics.removeSize)
    }

    // 범주색 배경(선택하면 강조색), 잘못된 정규식은 빨간 테두리
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius)
        if isSelected {
            NSColor.controlAccentColor.setFill()
        } else {
            background(hovered: isHovered).setFill()
        }
        path.fill()
        if token.isInvalid {
            NSColor.systemRed.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    // 글자색: 선택하면 흰색, 아니면 기본 글자색 (범주색은 배경에만 쓴다)
    private func updateColors() {
        let color: NSColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        titleLabel.textColor = color
        valueLabel.textColor = color
        removeButton.contentTintColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    // MARK: - 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    // MARK: - 색

    /// 범주별 배경색 (밝은 모드 12%, 어두운 모드 22%, 마우스를 올리면 6% 진하게)
    private func background(hovered: Bool) -> NSColor {
        let base: NSColor = switch token.category {
        case .location: .systemBlue
        case .pathContains: .systemTeal
        case .extensions: .systemPurple
        case .kind: .systemGreen
        case .regex: .systemOrange
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha: CGFloat = (dark ? 0.22 : 0.12) + (hovered ? 0.06 : 0)
        return base.withAlphaComponent(alpha)
    }
}
