import AppKit
import MCaptureCore
import UniformTypeIdentifiers

/// 결과 한 줄: 아이콘 · 이름(일치한 글자 강조) · 상위 경로(~로 줄임)
final class ResultCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FindFileResult")

    enum Metrics {
        static let iconSize: CGFloat = 24
        static let horizontalPadding: CGFloat = 14
        static let gap: CGFloat = 10
        static let nameFontSize: CGFloat = 13
        static let pathFontSize: CGFloat = 11
    }

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private var hit: SearchHit?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: Metrics.pathFontSize)
        pathLabel.textColor = .secondaryLabelColor
        for view in [iconView, nameLabel, pathLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
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
    func configure(_ hit: SearchHit) {
        self.hit = hit
        iconView.image = FileIcons.icon(for: hit)
        pathLabel.stringValue = ((hit.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        updateName()
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

/// 테이블이 첫 응답자가 아니어도(포커스는 늘 검색 필드) 선택 행을 강조색으로 그린다
final class ResultRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
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
