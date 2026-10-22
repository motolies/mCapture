import Foundation
import IOKit
import MCaptureCore

/// MTDeviceRef는 CFType 포인터. CFArrayGetValueAtIndex가 돌려주는 UnsafeRawPointer를 그대로 쓴다
typealias MTDeviceRef = UnsafeRawPointer

/// 접촉 프레임 콜백 (device, touches, count, timestamp, frame). 프레임워크 자체 스레드에서 불린다
typealias MTFrameCallback = @convention(c) (MTDeviceRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
/// MTRegisterButtonStateCallback용. 공개된 헤더가 없어 (장치, 정수 셋)으로 선언하고 실측으로 의미를 확인한다
typealias MTButtonCallback = @convention(c) (MTDeviceRef?, Int32, Int32, Int32) -> Int32

/// MultitouchSupport 비공개 프레임워크의 함수 포인터 묶음
/// dlopen 핸들과 장치 목록은 프로세스가 끝날 때까지 닫지도 해제하지도 않는다 (해제 시 크래시 보고가 있고, 종료로 충분하다)
struct MTAPI: Sendable {
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

    static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// 프레임워크를 열고 심볼을 모두 찾는다. 없는 심볼이 있으면 이름을 전부 stderr에 적고 nil
    static func load() -> MTAPI? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            let reason = dlerror().map { String(cString: $0) } ?? "알 수 없음"
            Console.error("프레임워크를 열 수 없음: \(reason)")
            return nil
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
            Console.error("심볼 없음: \(missing.joined(separator: ", "))")
            return nil
        }
        return MTAPI(
            createList: createList, createFromDeviceID: fromDeviceID, createFromService: fromService,
            start: start, stop: stop,
            registerCallback: register, unregisterCallback: unregister,
            registerButtonCallback: registerButton, unregisterButtonCallback: unregisterButton,
            isBuiltIn: isBuiltIn, isRunning: isRunning, isAlive: isAlive,
            familyID: familyID, deviceID: deviceID, surfaceDimensions: dimensions
        )
    }
}

/// 장치 하나의 식별 정보. UnsafeRawPointer는 Sendable이 아니라 시그널 핸들러 등에서 쓰려면 이 래퍼가 필요하다
struct MTDevice: @unchecked Sendable {
    let index: Int
    let ref: MTDeviceRef
    let familyID: Int32
    let builtIn: Bool
    let deviceID: UInt64
    /// 센서 표면 크기 (mm). 매직마우스는 가로 51.5, 세로 90.6
    let widthMM: Double
    let heightMM: Double
    /// 어떻게 열었는지 (CreateList / service / deviceID)
    let origin: String

    /// Family ID 112가 매직마우스(1·2세대 공통)
    var isMagicMouse: Bool { familyID == 112 }

    /// 콜백 첫 인자와 맞춰 볼 사전 키
    var key: UInt { UInt(bitPattern: ref) }

    /// 코어 쪽 식별 정보
    var descriptor: InputDeviceDescriptor {
        let kind = DeviceFamily.kind(forFamilyID: familyID)
        return InputDeviceDescriptor(id: deviceID, kind: kind, name: kind.displayName, surface: SurfaceSize(widthMM: widthMM, heightMM: heightMM))
    }

    /// 장치 포인터에서 식별 정보를 읽는다
    init(index: Int, ref: MTDeviceRef, origin: String, api: MTAPI) {
        var family: Int32 = 0
        var id: UInt64 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        _ = api.familyID(ref, &family)
        _ = api.deviceID(ref, &id)
        _ = api.surfaceDimensions(ref, &width, &height)
        self.index = index
        self.ref = ref
        self.familyID = family
        self.builtIn = api.isBuiltIn(ref)
        self.deviceID = id
        self.widthMM = Double(width) / 100
        self.heightMM = Double(height) / 100
        self.origin = origin
    }
}

/// 콜백이 준 접촉 배열의 레이아웃 (모든 공개 구현이 일치하는 96바이트 stride)
enum TouchRecord {
    static let stride = 96
    /// 레이아웃이 바뀌어 쓰레기 count가 와도 폭주하지 않게 상한을 둔다
    static let maxCount = 32

    /// 콜백 동안만 유효한 버퍼에서 접촉을 값으로 복사한다
    static func copy(from base: UnsafeRawPointer?, count: Int32) -> [TouchContact] {
        guard let base, count > 0 else { return [] }
        return (0..<min(Int(count), maxCount)).map { i in
            let p = base + i * stride
            return TouchContact(
                timestamp: p.loadUnaligned(fromByteOffset: 8, as: Double.self),
                pathIndex: p.loadUnaligned(fromByteOffset: 16, as: Int32.self),
                state: p.loadUnaligned(fromByteOffset: 20, as: Int32.self),
                fingerID: p.loadUnaligned(fromByteOffset: 24, as: Int32.self),
                x: p.loadUnaligned(fromByteOffset: 32, as: Float.self),
                y: p.loadUnaligned(fromByteOffset: 36, as: Float.self),
                velX: p.loadUnaligned(fromByteOffset: 40, as: Float.self),
                velY: p.loadUnaligned(fromByteOffset: 44, as: Float.self),
                zTotal: p.loadUnaligned(fromByteOffset: 48, as: Float.self),
                zDensity: p.loadUnaligned(fromByteOffset: 92, as: Float.self)
            )
        }
    }
}
