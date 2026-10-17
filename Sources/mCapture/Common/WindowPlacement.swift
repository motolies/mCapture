import AppKit
import MCaptureCore

extension NSWindow {
    /// 계단식으로 비켜 놓는 간격 (제목 막대 높이)
    private static let cascadeStep: CGFloat = 28

    /// 화면(nil이면 마우스 커서가 있는 화면)의 사용 영역 가운데에 둔다. 사용 영역보다 크면 제목 막대가 보이게 위쪽에 맞춘다
    /// others 중 보이는 창이 같은 자리에 있으면 계단식으로 비켜 놓아 새 창이 뜬 것을 알아볼 수 있게 한다
    /// SwiftUI·Auto Layout 내용은 첫 레이아웃에서 창 크기를 바꾸므로 레이아웃을 먼저 끝내 최종 크기로 계산한다
    /// AppKit center()는 키 창이 있는 화면에, 세로로는 위쪽에 치우쳐 두므로 쓰지 않는다
    func center(on screen: NSScreen?, avoiding others: [NSWindow] = []) {
        guard let area = (screen ?? NSScreen.underMouse)?.visibleFrame else { return }
        layoutIfNeeded()
        let size = frame.size
        let centered = NSRect(
            x: (area.midX - size.width / 2).rounded(),
            y: min(area.midY - size.height / 2, area.maxY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
        let occupied = others.filter { $0 !== self && $0.isVisible }.map(\.frame)
        setFrameOrigin(RectMath.cascaded(centered, avoiding: occupied, within: area, step: Self.cascadeStep).origin)
    }
}
