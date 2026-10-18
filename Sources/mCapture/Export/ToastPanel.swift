import AppKit
import SwiftUI

/// 화면 아래쪽에 잠깐 떴다 사라지는 알림. 알림 권한이 필요 없다
@MainActor
enum ToastPanel {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    /// 안내처럼 긴 문장은 duration을 늘리고 tint를 중립색으로 준다
    /// swatch가 있으면 아이콘 대신 그 색 견본을 보인다 (색 복사)
    static func show(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        tint: Color = .green,
        swatch: CGColor? = nil,
        duration: Duration = .seconds(1.6),
        on screen: NSScreen? = nil
    ) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage, tint: tint, swatch: swatch))
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let target = (screen ?? NSScreen.underMouse ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: target.midX - size.width / 2, y: target.minY + 72))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        hideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in panel.orderOut(nil) }
            }
        }
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String
    let tint: Color
    let swatch: CGColor?

    var body: some View {
        HStack(spacing: 8) {
            if let swatch {
                // 흰색·검정도 배경과 구분되도록 테두리를 두른다
                Circle()
                    .fill(Color(cgColor: swatch))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
