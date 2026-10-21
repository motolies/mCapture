import AppKit
import MCaptureCore

/// 메뉴바의 CPU 또는 MEM 항목. 두 줄 글자("CPU" / "24%")를 직접 그린 이미지로 보인다
///
/// 평소에는 템플릿 이미지라 밝은·어두운 메뉴바를 따라가고, 임계값을 넘으면 빨간 비템플릿 이미지로 바꾼다
/// (잠자기 방지 아이콘과 같은 규칙). 폭을 고정해 값이 바뀌어도 옆 항목이 흔들리지 않는다
@MainActor
final class MonitorStatusItem {
    enum Kind: String {
        case cpu
        case memory

        /// 위 줄 글자
        var label: String {
            switch self {
            case .cpu: "CPU"
            case .memory: "MEM"
            }
        }

        /// 메뉴바 위치를 기억하는 이름 (사용자가 ⌘-드래그로 옮긴 자리)
        var autosaveName: String { "monitor-\(rawValue)" }
    }

    enum Metrics {
        static let width: CGFloat = 34
        static let height: CGFloat = 22
        static let labelSize: CGFloat = 8
        static let valueSize: CGFloat = 11
    }

    let kind: Kind
    private let statusItem: NSStatusItem
    /// 누르면 (팝오버 토글)
    var onClick: (() -> Void)?
    /// 사용자가 메뉴바에서 끌어내거나(⌘-드래그) 시스템이 숨겼을 때
    var onVisibilityChange: ((Bool) -> Void)?
    private var visibilityObservation: NSKeyValueObservation?
    private(set) var value: Double?
    private(set) var alert = false
    /// 마지막으로 그린 (글자, 색). 같으면 다시 그리지 않는다
    private var rendered: (text: String, alert: Bool)?

    init(kind: Kind) {
        self.kind = kind
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = kind.autosaveName
        statusItem.behavior = [.removalAllowed]
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            let visible = item.isVisible
            Task { @MainActor [weak self] in self?.onVisibilityChange?(visible) }
        }
        render()
    }

    var isVisible: Bool {
        get { statusItem.isVisible }
        set { if statusItem.isVisible != newValue { statusItem.isVisible = newValue } }
    }

    var button: NSStatusBarButton? { statusItem.button }

    /// 값(%)과 임계값 초과 여부, 툴팁을 반영한다
    func update(value: Double?, alert: Bool, tooltip: String) {
        self.value = value
        self.alert = alert
        statusItem.button?.toolTip = tooltip
        render()
    }

    /// 팝오버가 열린 동안 눌린 모양을 유지한다
    func setHighlighted(_ highlighted: Bool) {
        statusItem.button?.isHighlighted = highlighted
    }

    @objc private func clicked() {
        onClick?()
    }

    // 지금 값으로 이미지를 다시 그린다. 글자와 색이 그대로면 건너뛴다
    private func render() {
        let text = value.map(MonitorFormat.percent) ?? "–"
        guard rendered?.text != text || rendered?.alert != alert else { return }
        rendered = (text, alert)
        statusItem.button?.image = Self.image(label: kind.label, value: text, alert: alert)
        statusItem.button?.setAccessibilityLabel("\(kind.label) \(text)")
    }

    /// 두 줄 글자 이미지. alert면 빨간 비템플릿, 아니면 검정 템플릿(메뉴바가 색을 입힘)
    static func image(label: String, value: String, alert: Bool) -> NSImage {
        let size = NSSize(width: Metrics.width, height: Metrics.height)
        let color: NSColor = alert ? .systemRed : .black
        let image = NSImage(size: size, flipped: false) { rect in
            let labelFont = NSFont.systemFont(ofSize: Metrics.labelSize, weight: .medium)
            let valueFont = NSFont.monospacedDigitSystemFont(ofSize: Metrics.valueSize, weight: .semibold)
            draw(label, font: labelFont, color: color, centerY: rect.height * 0.74, in: rect)
            draw(value, font: valueFont, color: color, centerY: rect.height * 0.3, in: rect)
            return true
        }
        image.isTemplate = !alert
        return image
    }

    // 글자를 가로 가운데, 주어진 세로 중심에 그린다
    private static func draw(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: ((rect.width - size.width) / 2).rounded(), y: (centerY - size.height / 2).rounded())
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
