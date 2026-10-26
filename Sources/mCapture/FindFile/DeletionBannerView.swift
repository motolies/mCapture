import AppKit

/// 휴지통 이동의 진행·결과를 선택 막대 자리에 보일 내용
struct DeletionBanner {
    enum Tone {
        case progress, success, warning, info
    }

    var text: String
    var tone: Tone
    /// 진행 중일 때 (끝낸 수, 전체)
    var progress: (done: Int, total: Int)?
    var canStop = false
    var canUndo = false
    /// [자세히]에 보일 줄 (이름 — 이유)
    var details: [String] = []
}

/// 휴지통 이동 진행·완료·부분 실패·되돌림 배너 (40pt). 타이머로 사라지지 않는다
final class DeletionBannerView: FlippedView {
    var onStop: (() -> Void)?
    var onUndo: (() -> Void)?
    var onClose: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let stopButton = NSButton(title: "중지", target: nil, action: nil)
    private let detailsButton = NSButton(title: "자세히", target: nil, action: nil)
    private let undoButton = NSButton(title: "되돌리기 ⌘Z", target: nil, action: nil)
    private let closeButton = NSButton()
    private var details: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        progressBar.isIndeterminate = false
        progressBar.style = .bar
        progressBar.controlSize = .small
        for (button, action) in [(stopButton, #selector(stopClicked)), (detailsButton, #selector(detailsClicked)),
                                 (undoButton, #selector(undoClicked))] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = action
        }
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "닫기")
        closeButton.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        for view in [iconView, label, progressBar, stopButton, detailsButton, undoButton, closeButton] as [NSView] {
            if let button = view as? NSButton { button.refusesFirstResponder = true }
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 내용을 바꾸고 배치한다
    func configure(_ banner: DeletionBanner, width: CGFloat, height: CGFloat) {
        let (symbol, tint): (String, NSColor) = switch banner.tone {
        case .progress: ("trash", .secondaryLabelColor)
        case .success: ("checkmark.circle.fill", .systemGreen)
        case .warning: ("exclamationmark.triangle.fill", .systemOrange)
        case .info: ("arrow.uturn.backward.circle", .secondaryLabelColor)
        }
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = tint
        label.stringValue = banner.text
        details = banner.details
        progressBar.isHidden = banner.progress == nil
        if let progress = banner.progress {
            progressBar.maxValue = Double(max(progress.total, 1))
            progressBar.doubleValue = Double(progress.done)
        }
        stopButton.isHidden = !banner.canStop
        undoButton.isHidden = !banner.canUndo
        detailsButton.isHidden = banner.details.isEmpty
        closeButton.isHidden = banner.tone == .progress

        let padding: CGFloat = 18
        let midY = height / 2
        iconView.frame = NSRect(x: padding, y: midY - 9, width: 18, height: 18)
        var right = width - padding
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: right - 18, y: midY - 9, width: 18, height: 18)
            right = closeButton.frame.minX - 10
        }
        for button in [undoButton, detailsButton, stopButton] where !button.isHidden {
            button.sizeToFit()
            button.frame.origin = NSPoint(x: right - button.frame.width, y: midY - button.frame.height / 2)
            right = button.frame.minX - 6
        }
        if !progressBar.isHidden {
            progressBar.frame = NSRect(x: right - 160, y: midY - 6, width: 160, height: 12)
            right = progressBar.frame.minX - 10
        }
        label.frame = NSRect(x: iconView.frame.maxX + 8, y: midY - 8, width: max(0, right - iconView.frame.maxX - 8), height: 16)
        NSAccessibility.post(element: label, notification: .announcementRequested,
                             userInfo: [.announcement: banner.text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func stopClicked() { onStop?() }
    @objc private func undoClicked() { onUndo?() }
    @objc private func closeClicked() { onClose?() }

    // 옮기지 못한 항목과 이유를 메뉴로 보인다
    @objc private func detailsClicked() {
        let menu = NSMenu()
        for line in details.prefix(30) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if details.count > 30 {
            let item = NSMenuItem(title: "외 \(details.count - 30)개", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: detailsButton.bounds.height + 2), in: detailsButton)
    }
}
