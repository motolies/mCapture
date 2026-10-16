import AppKit

/// 오버레이에서 고른 것
enum SelectionPick: Sendable {
    /// 드래그 없이 클릭: 디스플레이 전체
    case display
    /// 이미지 픽셀 좌표의 영역
    case area(CGRect)
    /// 창 모드에서 클릭한 창
    case window(CGWindowID)
    /// 확대경 가운데 픽셀 색 ("#RRGGBB")
    case color(String)
}

/// 영역 선택 결과
struct SelectionResult {
    let shot: ScreenShot
    let pick: SelectionPick
    /// 캡처한 앱 이름 (파일 이름 {app}). 창을 골랐으면 그 창의 앱, 아니면 캡처 전에 쓰던 앱
    var appName: String?

    /// 크롭할 영역. 디스플레이 전체이거나 영역이 아니면 nil
    var rect: CGRect? {
        if case .area(let rect) = pick { return rect }
        return nil
    }
}

/// 디스플레이마다 멈춘 화면 오버레이를 띄우고 선택 결과를 기다린다
@MainActor
final class SelectionOverlayController {
    private let shots: [ScreenShot]
    /// 창 모드의 후보 창 (앞에서 뒤 순서). 비어 있으면 영역 모드
    private let windows: [WindowTarget]
    private var panels: [OverlayPanel] = []
    private var views: [SelectionView] = []
    /// Sendable 값(화면 순번, 고른 것)만 넘기고 결과 객체는 메인 액터에서 다시 만든다
    private var continuation: CheckedContinuation<(index: Int, pick: SelectionPick)?, Never>?

    init(shots: [ScreenShot], windows: [WindowTarget] = []) {
        self.shots = shots
        self.windows = windows
    }

    /// 선택이 끝나거나 취소될 때까지 기다린다
    func run() async -> SelectionResult? {
        let picked = await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
        return picked.map { SelectionResult(shot: shots[$0.index], pick: $0.pick) }
    }

    // 모든 디스플레이에 오버레이를 띄우고 커서가 있는 화면을 키 창으로 만든다
    private func present() {
        for (index, shot) in shots.enumerated() {
            let panel = OverlayPanel(frame: shot.screen.frame)
            let view = SelectionView(shot: shot, frame: NSRect(origin: .zero, size: shot.screen.frame.size), windows: localWindows(on: shot.screen))
            view.onFinish = { [weak self] pick in
                self?.finish((index, pick))
            }
            view.onCancel = { [weak self] in
                self?.finish(nil)
            }
            view.onDragStart = { [weak self, weak view] in
                // 다른 화면에서 진행 중이던 선택은 지운다
                self?.views.filter { $0 !== view }.forEach { $0.resetInteraction() }
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }

        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
        keyPanel?.makeKey()
        if let keyPanel, let view = keyPanel.contentView {
            keyPanel.makeFirstResponder(view)
        }
        NSCursor.crosshair.set()
    }

    // 이 화면에 걸친 창을 화면 오버레이의 뷰 좌표(왼쪽 위 원점)로 바꾼다
    private func localWindows(on screen: NSScreen) -> [SelectionView.WindowRegion] {
        let frame = screen.frame
        return windows.filter { $0.frame.intersects(frame) }.map {
            SelectionView.WindowRegion(
                id: $0.id,
                rect: CGRect(x: $0.frame.minX - frame.minX, y: frame.maxY - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
            )
        }
    }

    private func finish(_ result: (index: Int, pick: SelectionPick)?) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: result)
    }
}

/// 메뉴바·Dock 위까지 덮는 테두리 없는 창
final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
