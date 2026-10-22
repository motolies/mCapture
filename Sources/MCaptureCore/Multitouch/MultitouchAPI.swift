import Foundation
import IOKit

/// MultitouchSupport를 쓸 수 없는 경우
public enum MultitouchError: Error, Equatable, CustomStringConvertible {
    /// dlopen 실패 (사유)
    case frameworkUnavailable(String)
    /// 찾지 못한 심볼 이름
    case missingSymbols([String])
    /// MTDeviceStart가 0이 아닌 값을 돌려줌 (장치 id, 반환값)
    case deviceStartFailed(UInt64, Int32)

    public var description: String {
        switch self {
        case .frameworkUnavailable(let reason): "MultitouchSupport 프레임워크를 열 수 없음: \(reason)"
        case .missingSymbols(let names): "MultitouchSupport 심볼 없음: \(names.joined(separator: ", "))"
        case .deviceStartFailed(let id, let status): String(format: "장치 0x%016llx 시작 실패 (MTDeviceStart=%d)", id, status)
        }
    }
}

/// MTDeviceRef는 CFType 포인터. CFArrayGetValueAtIndex가 돌려주는 UnsafeRawPointer를 그대로 쓴다
typealias MTDeviceRef = UnsafeRawPointer
/// 접촉 프레임 콜백 (device, touches, count, timestamp, frame). 프레임워크 자체 스레드에서 불린다
typealias MTFrameCallback = @convention(c) (MTDeviceRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
/// MTRegisterButtonStateCallback용. 공개된 헤더가 없어 (장치, 정수 셋)으로 선언한다. 실측: (장치, 버튼, 이전 버튼, 쓰레기)
typealias MTButtonCallback = @convention(c) (MTDeviceRef?, Int32, Int32, Int32) -> Int32

/// 비공개 MultitouchSupport 프레임워크의 함수 포인터 묶음.
/// 정적 초기화로 열지 않는다: 테스트나 앱 시작 때 dlopen이 일어나지 않도록 `load()`를 명시적으로 부른다.
/// dlopen 핸들과 장치 포인터는 프로세스가 끝날 때까지 닫지도 해제하지도 않는다 (해제 시 크래시 보고가 있고, 종료로 충분하다)
public struct MultitouchAPI: Sendable {
    typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    typealias FromDeviceIDFn = @convention(c) (UInt64) -> MTDeviceRef?
    typealias FromServiceFn = @convention(c) (io_service_t) -> MTDeviceRef?
    typealias StartFn = @convention(c) (MTDeviceRef, Int32) -> Int32
    typealias StopFn = @convention(c) (MTDeviceRef) -> Int32
    typealias CallbackFn = @convention(c) (MTDeviceRef, MTFrameCallback) -> Bool
    typealias ButtonCallbackFn = @convention(c) (MTDeviceRef, MTButtonCallback) -> Bool
    typealias BoolFn = @convention(c) (MTDeviceRef) -> Bool
    typealias Int32OutFn = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>) -> Int32
    typealias UInt64OutFn = @convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32
    typealias DimensionsFn = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    let createList: CreateListFn
    /// CreateList에 빠진 장치(블루투스 매직마우스)를 IORegistry 정보로 여는 두 경로
    let createFromDeviceID: FromDeviceIDFn
    let createFromService: FromServiceFn
    let start: StartFn
    let stop: StopFn
    let registerCallback: CallbackFn
    let unregisterCallback: CallbackFn
    let registerButtonCallback: ButtonCallbackFn
    let unregisterButtonCallback: ButtonCallbackFn
    let isBuiltIn: BoolFn
    let isRunning: BoolFn
    let isAlive: BoolFn
    let familyID: Int32OutFn
    let deviceID: UInt64OutFn
    let surfaceDimensions: DimensionsFn

    public static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// 프레임워크를 열고 심볼을 모두 찾는다. 하나라도 없으면 이름을 모두 담아 던진다
    public static func load() throws -> MultitouchAPI {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            throw MultitouchError.frameworkUnavailable(dlerror().map { String(cString: $0) } ?? "알 수 없음")
        }
        var missing: [String] = []
        // 심볼을 찾은 뒤에만 함수 포인터로 바꾼다. 옵셔널을 그대로 캐스팅하면 없는 심볼이 0번지 호출이 된다
        func symbol<F>(_ name: String, _: F.Type) -> F? {
            guard let pointer = dlsym(handle, name) else {
                missing.append(name)
                return nil
            }
            return unsafeBitCast(pointer, to: F.self)
        }
        let createList = symbol("MTDeviceCreateList", CreateListFn.self)
        let fromDeviceID = symbol("MTDeviceCreateFromDeviceID", FromDeviceIDFn.self)
        let fromService = symbol("MTDeviceCreateFromService", FromServiceFn.self)
        let start = symbol("MTDeviceStart", StartFn.self)
        let stop = symbol("MTDeviceStop", StopFn.self)
        let register = symbol("MTRegisterContactFrameCallback", CallbackFn.self)
        let unregister = symbol("MTUnregisterContactFrameCallback", CallbackFn.self)
        let registerButton = symbol("MTRegisterButtonStateCallback", ButtonCallbackFn.self)
        let unregisterButton = symbol("MTUnregisterButtonStateCallback", ButtonCallbackFn.self)
        let isBuiltIn = symbol("MTDeviceIsBuiltIn", BoolFn.self)
        let isRunning = symbol("MTDeviceIsRunning", BoolFn.self)
        let isAlive = symbol("MTDeviceIsAlive", BoolFn.self)
        let familyID = symbol("MTDeviceGetFamilyID", Int32OutFn.self)
        let deviceID = symbol("MTDeviceGetDeviceID", UInt64OutFn.self)
        let dimensions = symbol("MTDeviceGetSensorSurfaceDimensions", DimensionsFn.self)
        guard missing.isEmpty,
              let createList, let fromDeviceID, let fromService, let start, let stop, let register, let unregister,
              let registerButton, let unregisterButton,
              let isBuiltIn, let isRunning, let isAlive, let familyID, let deviceID, let dimensions
        else {
            throw MultitouchError.missingSymbols(missing)
        }
        return MultitouchAPI(
            createList: createList, createFromDeviceID: fromDeviceID, createFromService: fromService,
            start: start, stop: stop,
            registerCallback: register, unregisterCallback: unregister,
            registerButtonCallback: registerButton, unregisterButtonCallback: unregisterButton,
            isBuiltIn: isBuiltIn, isRunning: isRunning, isAlive: isAlive,
            familyID: familyID, deviceID: deviceID, surfaceDimensions: dimensions
        )
    }
}
