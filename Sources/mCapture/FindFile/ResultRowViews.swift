import AppKit
import MCaptureCore
import UniformTypeIdentifiers

/// 결과 한 줄: [체크박스] · 아이콘 · 이름(일치한 글자 강조) · 상위 경로(~로 줄임)
///
/// 체크박스는 체크한 항목이 하나라도 있을 때만 보인다 (평소 화면은 그대로)
final class ResultCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FindFileResult")

    enum Metrics {
        static let iconSize: CGFloat = 24
        static let horizontalPadding: CGFloat = 14
        static let gap: CGFloat = 10
        static let nameFontSize: CGFloat = 13
        static let pathFontSize: CGFloat = 11
        /// 체크박스 열 폭 (체크박스 16 + 여백)
        static let checkColumnWidth: CGFloat = 28
    }

    /// 체크 표시
    enum Check: Equatable {
        case unchecked
        case checked
        /// 체크한 조상 폴더 안이라 함께 포함됨 (흐리게, 따로 끌 수 없음)
        case implied
    }

    /// 체크박스를 눌렀을 때
    var onCheckboxClick: (() -> Void)?

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private var iconLeading: NSLayoutConstraint!
    private var hit: SearchHit?
    private var check = Check.unchecked

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        checkbox.refusesFirstResponder = true
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)
        checkbox.isHidden = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: Metrics.pathFontSize)
        pathLabel.textColor = .secondaryLabelColor
        for view in [checkbox, iconView, nameLabel, pathLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        iconLeading = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLeading,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.gap),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 결과를 표시한다
    func configure(_ hit: SearchHit, check: Check, showsCheckbox: Bool) {
        self.hit = hit
        iconView.image = FileIcons.icon(for: hit)
        pathLabel.stringValue = ((hit.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        updateName()
        updateCheck(check, showsCheckbox: showsCheckbox)
    }

    /// 체크 표시만 바꾼다 (행을 다시 만들지 않고)
    func updateCheck(_ check: Check, showsCheckbox: Bool) {
        self.check = check
        checkbox.isHidden = !showsCheckbox
        checkbox.state = check == .unchecked ? .off : .on
        checkbox.isEnabled = check != .implied
        iconLeading.constant = Metrics.horizontalPadding + (showsCheckbox ? Metrics.checkColumnWidth : 0)
        guard let hit else { return }
        let state = switch check {
        case .unchecked: ""
        case .checked: ", 체크됨"
        case .implied: ", 체크한 폴더 안"
        }
        setAccessibilityLabel("\(hit.name), \(pathLabel.stringValue)\(state)")
        checkbox.setAccessibilityLabel("체크: \(hit.name)")
    }

    @objc private func checkboxClicked() {
        // 상태는 컨트롤러가 정해 다시 그리므로 버튼이 바꾼 값은 되돌린다
        checkbox.state = check == .unchecked ? .off : .on
        onCheckboxClick?()
    }

    // 선택 행(강조 배경)에서는 강조색 대신 굵게만 표시하도록 다시 그린다
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateName() }
    }

    // 이름을 기본 글꼴로 쓰고 일치한 글자는 굵게(선택되지 않은 행은 강조색도) 표시한다
    private func updateName() {
        guard let hit else { return }
        let emphasized = backgroundStyle == .emphasized
        let text = NSMutableAttributedString(string: hit.name, attributes: [
            .font: NSFont.systemFont(ofSize: Metrics.nameFontSize),
            .foregroundColor: emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
        ])
        var highlight: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Metrics.nameFontSize, weight: .bold)]
        if !emphasized { highlight[.foregroundColor] = NSColor.controlAccentColor }
        for range in Self.ranges(of: hit.highlights, in: hit.name) {
            text.addAttributes(highlight, range: range)
        }
        nameLabel.attributedStringValue = text
        pathLabel.textColor = emphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
    }

    /// 스칼라 번호를 UTF-16 범위로 바꾼다 (한글·이모지도 글자 단위로 맞게 칠하려고)
    static func ranges(of positions: [Int], in name: String) -> [NSRange] {
        let wanted = Set(positions)
        var ranges: [NSRange] = []
        var offset = 0
        for (index, scalar) in name.unicodeScalars.enumerated() {
            let length = scalar.utf16.count
            if wanted.contains(index) { ranges.append(NSRange(location: offset, length: length)) }
            offset += length
        }
        return ranges
    }
}

/// 테이블이 첫 응답자가 아니어도(포커스는 늘 검색 필드) 선택 행을 강조색으로 그린다. 체크한 행은 연한 강조색을 깐다
final class ResultRowView: NSTableRowView {
    var isChecked = false {
        didSet { if isChecked != oldValue { needsDisplay = true } }
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    // 커서 행(진한 선택색)과 구분되게 체크한 행은 연한 틴트 (밝은 모드 14%, 어두운 모드 22%)
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isChecked else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.controlAccentColor.withAlphaComponent(dark ? 0.22 : 0.14).setFill()
        bounds.fill()
    }
}

/// 결과 목록. ⌘클릭·⇧클릭은 행 선택 대신 체크로 넘긴다 (Finder 다중 선택 습관)
final class ResultTableView: NSTableView {
    /// (행, 수식키) → 처리했으면 true
    var onModifiedClick: ((Int, NSEvent.ModifierFlags) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift])
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !modifiers.isEmpty, onModifiedClick?(row, modifiers) == true { return }
        super.mouseDown(with: event)
    }
}

/// 결과 아이콘. 파일은 확장자별로, 폴더·앱은 경로별로 캐시한다
@MainActor
enum FileIcons {
    private static let cache = NSCache<NSString, NSImage>()

    /// 결과의 아이콘 (보이는 행만 요청하므로 동기로 가져온다)
    static func icon(for hit: SearchHit) -> NSImage {
        let ext = (hit.name as NSString).pathExtension.lowercased()
        let key = hit.isDirectory || ext.isEmpty ? "path:" + hit.path : "ext:" + ext
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image: NSImage
        if hit.isDirectory || ext.isEmpty {
            image = NSWorkspace.shared.icon(forFile: hit.path)
        } else {
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
