import AppKit
import ApplicationServices

/// 다른 앱의 창 하나를 손쉬운 사용(AX) API로 다룬다. 좌표는 CG 전역(주 화면 왼쪽 위 원점, 아래로 증가)
/// 화면·가운데 맞춤은 모른다. AXUIElement는 Sendable이 아니라 메인 액터에 둔다
@MainActor
struct AccessibilityWindow {
    enum Failure: Error, Equatable {
        /// 포커스 창도 메인 창도 없다 (창이 없는 앱, 바탕화면만 있는 Finder)
        case noWindow
        /// 돌려받은 요소의 역할이 창이 아니다
        case notAWindow(String?)
        case minimized
        case fullScreen
        /// AX 호출 실패와 그때의 속성 이름
        case api(AXError, String)
    }

    /// 응답 없는 앱에 메인 스레드가 묶이지 않게 하는 메시지 한도(초). 기본값은 수 초라 메시지 몇 개면 비치볼이 돈다
    private static let messagingTimeout: Float = 1

    let element: AXUIElement

    /// 앱의 포커스 창(없으면 메인 창). 창이 아니거나 최소화·전체 화면이면 실패
    /// `kAXFullScreenAttribute`는 공개 헤더에 없어 문자열로 묻고, 지원하지 않는 앱은 nil이라 통과시킨다
    static func focused(of pid: pid_t) -> Result<AccessibilityWindow, Failure> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var raw: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &raw)
        if error == .noValue || error == .attributeUnsupported {
            error = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &raw)
        }
        switch error {
        case .success: break
        case .noValue, .attributeUnsupported: return .failure(.noWindow)
        default: return .failure(.api(error, kAXFocusedWindowAttribute))
        }
        // CF 타입으로의 as!는 런타임에 검사하지 않으므로 타입 ID를 먼저 확인한다
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .failure(.noWindow) }
        let window = AccessibilityWindow(element: raw as! AXUIElement)
        // 한도는 요소마다 따로다 (같은 창을 가리키는 다른 요소에도 전파되지 않음)
        AXUIElementSetMessagingTimeout(window.element, messagingTimeout)
        let role = window.string(kAXRoleAttribute)
        guard role == kAXWindowRole else { return .failure(.notAWindow(role)) }
        if window.bool(kAXMinimizedAttribute) == true { return .failure(.minimized) }
        if window.bool("AXFullScreen") == true { return .failure(.fullScreen) }
        return .success(window)
    }

    /// 위치와 크기를 한 번에 읽는다 (CG 좌표)
    func frame() -> Result<CGRect, Failure> {
        position().flatMap { origin in size().map { CGRect(origin: origin, size: $0) } }
    }

    func position() -> Result<CGPoint, Failure> {
        value(kAXPositionAttribute, type: .cgPoint, initial: CGPoint.zero)
    }

    func size() -> Result<CGSize, Failure> {
        value(kAXSizeAttribute, type: .cgSize, initial: CGSize.zero)
    }

    /// 성공하면 nil. 앱이 받아들였다고 해서 실제로 움직였다는 뜻은 아니므로 다시 읽어 확인한다
    func setPosition(_ point: CGPoint) -> Failure? {
        var point = point
        return set(kAXPositionAttribute, type: .cgPoint, pointer: &point)
    }

    /// 성공하면 nil. 앱이 최소 크기나 셀 격자로 값을 고칠 수 있으므로 다시 읽어 확인한다
    func setSize(_ size: CGSize) -> Failure? {
        var size = size
        return set(kAXSizeAttribute, type: .cgSize, pointer: &size)
    }

    // 속성 값을 CF 객체로 읽는다
    private func copy(_ attribute: String) -> Result<CFTypeRef, Failure> {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard error == .success, let raw else { return .failure(.api(error, attribute)) }
        return .success(raw)
    }

    private func string(_ attribute: String) -> String? {
        (try? copy(attribute).get()) as? String
    }

    private func bool(_ attribute: String) -> Bool? {
        (try? copy(attribute).get()) as? Bool
    }

    // AXValue(CGPoint·CGSize)를 풀어 읽는다. 타입 ID와 값 종류를 모두 확인한다
    private func value<T>(_ attribute: String, type: AXValueType, initial: T) -> Result<T, Failure> {
        copy(attribute).flatMap { raw in
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { return .failure(.api(.failure, attribute)) }
            let axValue = raw as! AXValue
            var result = initial
            // 제네릭 값에 &를 바로 쓰면 참조를 담을 수 있다는 경고가 나므로 포인터를 명시적으로 만든다 (T는 CGPoint·CGSize)
            let read = withUnsafeMutablePointer(to: &result) { AXValueGetValue(axValue, type, $0) }
            guard AXValueGetType(axValue) == type, read else {
                return .failure(.api(.failure, attribute))
            }
            return .success(result)
        }
    }

    // 값을 AXValue로 싸서 쓴다
    private func set(_ attribute: String, type: AXValueType, pointer: UnsafeRawPointer) -> Failure? {
        guard let axValue = AXValueCreate(type, pointer) else { return .api(.failure, attribute) }
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
        return error == .success ? nil : .api(error, attribute)
    }
}
