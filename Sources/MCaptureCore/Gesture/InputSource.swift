import Foundation

/// 제스처 이벤트를 내는 입력 소스의 계약. 터치 장치는 `MultitouchInputSource`가 맡고,
/// 비터치 장치(일반 마우스의 버튼, 키보드 코드 등)는 이 프로토콜을 구현해 붙인다. 앱은 이 계약만 본다
public protocol InputSource: AnyObject, Sendable {
    /// 이 소스가 다루는 장치들
    var devices: [InputDeviceDescriptor] { get }
    /// 제스처 이벤트 스트림. 소비자는 하나이고, 소비가 멈춰도 쌓이지 않게 최신 몇 개만 버퍼한다
    var events: AsyncStream<GestureEvent> { get }
    /// 장치를 열고 이벤트를 내기 시작한다. 한 번 멈춘 소스는 다시 시작하지 않는다 (새로 만든다)
    func start() throws
    /// 장치를 닫고 스트림을 끝낸다. 여러 번 불러도 안전하다
    func stop()
}
