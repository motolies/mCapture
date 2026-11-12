import Foundation
import IOKit
import MCaptureCore

/// IOKit의 비공개 IOAVService 함수 묶음. 공개 헤더가 없어 실행 중에 심볼로 찾는다.
/// 심볼이 하나라도 없으면 nil이고, 그때는 외부 디스플레이 복구 기능만 꺼진다 (앱 실행에는 영향이 없다).
/// 인자 형태는 macOS 27.2의 IOKit을 역어셈블해 확인했다
struct DisplayServiceAPI: Sendable {
    typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias CopyEDIDFn = @convention(c) (CFTypeRef, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
    /// (서비스, I2C 주소, 위치, 받을 버퍼, 길이)
    typealias ReadI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    /// (서비스, 모드, EDID). 모드 1 + 데이터는 덮어쓰기, 모드 0 + nil은 해제
    typealias SetVirtualEDIDModeFn = @convention(c) (CFTypeRef, UInt32, CFData?) -> IOReturn

    let create: CreateFn
    let copyEDID: CopyEDIDFn
    let readI2C: ReadI2CFn
    let setVirtualEDIDMode: SetVirtualEDIDModeFn

    private static let frameworkPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    /// 처음 쓸 때 한 번만 찾는다
    static let shared: DisplayServiceAPI? = load()

    /// 심볼을 모두 찾으면 함수 묶음을 돌려준다. 없는 심볼은 로그에 남긴다
    private static func load() -> DisplayServiceAPI? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            Log.display.error("IOKit을 열 수 없음")
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
        let create = symbol("IOAVServiceCreateWithService", CreateFn.self)
        let copyEDID = symbol("IOAVServiceCopyEDID", CopyEDIDFn.self)
        let readI2C = symbol("IOAVServiceReadI2C", ReadI2CFn.self)
        let setVirtualEDIDMode = symbol("IOAVServiceSetVirtualEDIDMode", SetVirtualEDIDModeFn.self)
        guard let create, let copyEDID, let readI2C, let setVirtualEDIDMode else {
            Log.display.error("IOAVService 심볼 없음: \(missing.joined(separator: ", "), privacy: .public)")
            return nil
        }
        return DisplayServiceAPI(create: create, copyEDID: copyEDID, readI2C: readI2C, setVirtualEDIDMode: setVirtualEDIDMode)
    }
}

/// 외부 디스플레이 연결 하나. 디스플레이 보조 프로세서(DCP)가 연결마다 내놓는 AV 서비스를 감싼다.
/// 서비스는 케이블이 꽂혀 있는 동안에만 있다 (실측: 연결 수와 서비스 수가 같다).
/// IOKit 호출은 커널로 가는 요청이라 스레드를 가리지 않으므로, 메인 밖에서 읽을 수 있게 Sendable로 둔다
final class ExternalDisplayConnection: @unchecked Sendable {
    /// EDID가 들어 있는 I2C 주소 (DDC 표준)
    private static let edidAddress: UInt32 = 0x50
    /// 읽기 시도 사이에 쉬는 시간. 실패한 직후 바로 다시 읽으면 연달아 실패했다
    private static let retryPause: TimeInterval = 0.2
    /// SetVirtualEDIDMode의 모드 값: 넘긴 EDID로 덮어쓴다
    private static let virtualEDIDModeOverride: UInt32 = 1

    private let api: DisplayServiceAPI
    private let service: CFTypeRef
    /// 레지스트리 경로. 로그에서 어느 연결인지 구분한다
    let registryPath: String

    private init(api: DisplayServiceAPI, service: CFTypeRef, registryPath: String) {
        self.api = api
        self.service = service
        self.registryPath = registryPath
    }

    /// 지금 꽂혀 있는 외부 디스플레이 연결을 모두 찾는다. 비공개 함수를 쓸 수 없으면 nil
    static func all() -> [ExternalDisplayConnection]? {
        guard let api = DisplayServiceAPI.shared else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var connections: [ExternalDisplayConnection] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            // 내장 디스플레이의 서비스는 Location이 "Embedded"다
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard location == "External", let service = api.create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            let path = IORegistryEntryCopyPath(entry, kIOServicePlane)?.takeRetainedValue() as String? ?? ""
            connections.append(ExternalDisplayConnection(api: api, service: service, registryPath: path))
        }
        return connections
    }

    /// 시스템이 연결할 때 읽어 둔 EDID. 시스템이 읽지 못했으면 nil이고, 이 상태가 복구 대상이다
    func systemEDIDBytes() -> [UInt8]? {
        var copied: Unmanaged<CFData>?
        guard api.copyEDID(service, &copied) == KERN_SUCCESS, let data = copied?.takeRetainedValue() as Data?, !data.isEmpty else {
            return nil
        }
        return [UInt8](data)
    }

    /// 디스플레이에서 EDID를 직접 읽는다. 작은 단위로 여러 번 읽어 검증하므로 몇 초 걸릴 수 있다 (메인 밖에서 부른다)
    func readEDID() -> Result<EDID, EDIDReader.Failure> {
        EDIDReader.readTrusted(
            from: { [self] offset, length in readI2C(offset: offset, length: length) },
            pause: { Thread.sleep(forTimeInterval: Self.retryPause) }
        )
    }

    /// 넘긴 EDID를 이 연결에 덮어씌운다. 시스템이 그 정보로 디스플레이를 다시 인식한다.
    /// 일회성이라 케이블을 뽑으면 풀린다
    func apply(_ edid: EDID) -> IOReturn {
        api.setVirtualEDIDMode(service, Self.virtualEDIDModeOverride, Data(edid.bytes) as CFData)
    }

    // I2C로 EDID의 offset 위치부터 length바이트를 읽는다. 실패하면 nil
    private func readI2C(offset: Int, length: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: length)
        guard api.readI2C(service, Self.edidAddress, UInt32(offset), &buffer, UInt32(length)) == KERN_SUCCESS else { return nil }
        return buffer
    }
}
