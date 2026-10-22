import AppKit
import MCaptureCore

/// 앞 앱의 포커스 창을 마우스 커서가 있는 화면의 사용 영역 가운데로 옮긴다 (F32)
/// 자기 창은 NSWindow로, 다른 앱 창은 손쉬운 사용(AX) API로 옮기며 둘 다 같은 `WindowCentering` 계산을 쓴다
///
/// 알려진 한계: `AXEnhancedUserInterface`가 켜진 앱(VoiceOver 사용 중, 일부 Chrome·Electron)은 AX 이동이 애니메이션되거나
/// 어긋날 수 있다. 문제가 되면 쓰기 전후로 그 속성을 끄는 처리를 더한다
@MainActor
enum WindowCenterer {
    /// 사용 영역보다 큰 창 처리. 설정으로 뺄 때까지 여기서 고른다
    static let oversizePolicy: WindowCentering.OversizePolicy = .shrinkToFit
    /// 옮긴 뒤 실제 원점이 목표와 이보다 많이 다르면 앱이 무시한 것으로 본다 (pt)
    private static let tolerance: CGFloat = 1

    enum Failure: Error, Equatable {
        case permissionDenied
        case noWindow
        case fullScreen
        /// 1초 안에 응답하지 않는 앱 (멈췄거나 AX를 지원하지 않음)
        case notResponding(app: String)
        /// 쓰기는 성공했지만 위치가 바뀌지 않음 (위치를 고정하는 앱)
        case ignored(app: String)
        case accessibility(AXError, attribute: String, app: String)
        case noScreen
    }

    /// 커서가 있는 화면으로 옮기고 결과를 토스트·로그로 알린다. 성공하면 옮긴 뒤 프레임(AppKit 좌표)
    @discardableResult
    static func centerFocusedWindowOnMouseScreen() -> Result<CGRect, Failure> {
        let screen = NSScreen.underMouse
        let result = centerFocusedWindow(on: screen)
        report(result, on: screen)
        return result
    }

    /// 앞 앱의 포커스 창을 screen의 사용 영역 가운데로 옮긴다. 알림은 하지 않는다
    /// 순서: 크기 줄이기(필요할 때만) → 실제 크기 다시 읽기 → 위치 쓰기(크기가 또 바뀌면 한 번 더) → 실제 위치 확인
    static func centerFocusedWindow(on screen: NSScreen?) -> Result<CGRect, Failure> {
        // 주 화면(메뉴바 화면, 원점 0,0)의 높이가 CG↔AppKit 좌표 변환 기준. NSScreen.main은 키 창의 화면이라 쓰지 않는다
        guard let area = screen?.visibleFrame, let primaryHeight = NSScreen.screens.first?.frame.height else {
            return .failure(.noScreen)
        }
        guard let app = targetApplication() else { return .failure(.noWindow) }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return centerOwnWindow(in: area)
        }
        guard AccessibilityPermission.isGranted else { return .failure(.permissionDenied) }
        let name = app.localizedName ?? "앱"

        let window: AccessibilityWindow
        switch AccessibilityWindow.focused(of: app.processIdentifier) {
        case .success(let found): window = found
        case .failure(let failure): return .failure(map(failure, app: name))
        }
        // AX 프레임(CG 좌표)을 AppKit 좌표로 읽는다
        func read() -> Result<CGRect, Failure> {
            window.frame().map { RectMath.flipped($0, height: primaryHeight) }.mapError { map($0, app: name) }
        }
        var current: CGRect
        switch read() {
        case .success(let frame): current = frame
        case .failure(let failure): return .failure(failure)
        }
        // 어느 화면 전체와 똑같은 창은 전체 화면·Split View·Finder 바탕화면이다. AXFullScreen을 지원하지 않는 앱을 위한 보강
        if NSScreen.screens.contains(where: { $0.frame == current }) { return .failure(.fullScreen) }

        // 1) 크기부터 줄인다 (제자리에서 오른쪽·아래 변만 들어온다). 앱이 최소 크기로 막을 수 있으므로 실제 크기를 다시 읽고
        //    그 크기로 원점을 다시 계산한다 (keepSize: 못 줄였으면 왼쪽 위 정렬이 맞다). 줄이기를 거부해도 옮기기는 계속한다
        var target = WindowCentering.frame(centering: current, in: area, oversize: oversizePolicy)
        if target.size != current.size {
            if let failure = window.setSize(target.size) {
                Log.window.info("\(name, privacy: .public) 크기 조절 거부, 크기는 두고 옮김: \(String(describing: failure), privacy: .public)")
            } else {
                switch read() {
                case .success(let frame): current = frame
                case .failure(let failure): return .failure(failure)
                }
            }
            target = WindowCentering.frame(centering: current, in: area, oversize: .keepSize)
        }
        // 2) 옮긴다. 다른 디스플레이로 가면 앱이 크기를 다시 잡기도 하므로(터미널 셀 격자 등) 바뀌었으면 그 크기로 한 번 더
        var actual = current
        for attempt in 0..<2 {
            let origin = RectMath.flipped(target, height: primaryHeight).origin
            if let failure = window.setPosition(origin) { return .failure(map(failure, app: name)) }
            switch read() {
            case .success(let frame): actual = frame
            case .failure(let failure): return .failure(failure)
            }
            if actual.size == target.size || attempt == 1 { break }
            target = WindowCentering.frame(centering: actual, in: area, oversize: .keepSize)
        }
        // 3) 확인. 위치를 고정하는 앱은 성공을 돌려주고도 움직이지 않는다
        guard abs(actual.minX - target.minX) <= tolerance, abs(actual.minY - target.minY) <= tolerance else {
            Log.window.error("\(name, privacy: .public) 창이 움직이지 않음: 요청 \(NSStringFromRect(target), privacy: .public) 실제 \(NSStringFromRect(actual), privacy: .public)")
            return .failure(.ignored(app: name))
        }
        Log.window.info("\(name, privacy: .public) 창 이동: \(NSStringFromRect(actual), privacy: .public)")
        return .success(actual)
    }

    // 옮길 창을 가진 앱. 보통 앞 앱이다. 전역 단축키는 앱을 활성화하지 않지만 URL(`open mcapture://window/center`)은
    // 창 없는 자기 앱을 잠깐 앞으로 가져오므로, 그때는 메뉴 막대를 가진 앱(직전에 쓰던 앱)을 대상으로 한다.
    // 메뉴바 전용(LSUIElement) 앱은 활성화돼도 메뉴 막대를 갖지 않아 menuBarOwningApplication이 직전 앱으로 남는다
    private static func targetApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard frontmost?.processIdentifier == ownPID, NSApp.keyWindow == nil, NSApp.mainWindow == nil,
              let owner = NSWorkspace.shared.menuBarOwningApplication, owner.processIdentifier != ownPID
        else { return frontmost }
        return owner
    }

    // 자기 앱(에디터·빈 캔버스·설정 창): 권한 없이 NSWindow로 옮긴다. 같은 계산을 써서 다른 앱 창과 결과가 같다
    // 핀은 nonactivatingPanel이라 핀이 키여도 앞 앱은 다른 앱이고, 그 앱의 창이 움직인다
    private static func centerOwnWindow(in area: CGRect) -> Result<CGRect, Failure> {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return .failure(.noWindow) }
        guard !window.styleMask.contains(.fullScreen) else { return .failure(.fullScreen) }
        window.setFrame(WindowCentering.frame(centering: window.frame, in: area, oversize: oversizePolicy), display: true)
        Log.window.info("자기 창 이동: \(NSStringFromRect(window.frame), privacy: .public)")
        return .success(window.frame)
    }

    // AX 래퍼의 실패를 사용자에게 보일 종류로 바꾼다
    private static func map(_ failure: AccessibilityWindow.Failure, app: String) -> Failure {
        switch failure {
        case .noWindow, .minimized, .notAWindow: .noWindow
        case .fullScreen: .fullScreen
        case .api(.apiDisabled, _): .permissionDenied
        case .api(.cannotComplete, _): .notResponding(app: app)
        // 읽는 사이에 창이 닫혔다
        case .api(.invalidUIElement, _): .noWindow
        case .api(let error, let attribute): .accessibility(error, attribute: attribute, app: app)
        }
    }

    // 결과를 토스트(대상 화면에)와 로그로 알린다. 성공은 움직임이 보이므로 토스트를 띄우지 않는다
    private static func report(_ result: Result<CGRect, Failure>, on screen: NSScreen?) {
        let warning = "exclamationmark.triangle.fill"
        switch result {
        case .success:
            break
        case .failure(.permissionDenied):
            let permission = AccessibilityPermission.settingsItemName
            Log.window.error("\(permission, privacy: .public) 권한이 없어 창을 옮기지 못함")
            ToastPanel.show(
                "\(permission) 권한이 없어 창을 옮기지 못했습니다 — 시스템 설정에서 \(AppVariant.current.displayName)를 허용하세요",
                systemImage: warning, tint: .orange, duration: .seconds(4), on: screen
            )
            // 단축키는 의도한 조작이므로 제스처와 달리 바로 시스템 대화상자를 띄우고 설정을 연다
            AccessibilityPermission.request()
        case .failure(.noWindow):
            Log.window.info("옮길 창이 없음")
            ToastPanel.show("옮길 창이 없습니다", systemImage: "macwindow", tint: .secondary, on: screen)
        case .failure(.fullScreen):
            Log.window.info("전체 화면 창은 옮기지 않음")
            ToastPanel.show("전체 화면 창은 옮길 수 없습니다", systemImage: "macwindow", tint: .secondary, on: screen)
        case .failure(.notResponding(let app)):
            Log.window.error("\(app, privacy: .public)이 응답하지 않아 창을 옮기지 못함")
            ToastPanel.show("\(app)이(가) 응답하지 않아 창을 옮기지 못했습니다", systemImage: warning, tint: .orange, on: screen)
        case .failure(.ignored(let app)):
            ToastPanel.show("\(app) 창을 옮기지 못했습니다", systemImage: warning, tint: .orange, on: screen)
        case .failure(.accessibility(let error, let attribute, let app)):
            Log.window.error("\(app, privacy: .public) \(attribute, privacy: .public) 실패: AXError \(error.rawValue)")
            ToastPanel.show("\(app) 창을 옮기지 못했습니다 (오류 \(error.rawValue))", systemImage: warning, tint: .orange, on: screen)
        case .failure(.noScreen):
            Log.window.error("옮길 화면이 없음")
        }
    }
}
