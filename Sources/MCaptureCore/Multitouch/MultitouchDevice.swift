import Foundation
import IOKit

/// 멀티터치 장치 하나. 장치 포인터는 비트로 보관해 Sendable 검사를 통과한다 (프로세스가 끝날 때까지 해제하지 않으므로 늘 유효하다)
public struct MultitouchDevice: Sendable, Equatable {
    public let descriptor: InputDeviceDescriptor
    public let familyID: Int32
    public let builtIn: Bool
    /// 어떻게 열었는지 (CreateList / service / deviceID)
    public let origin: String
    /// 장치 포인터 비트. 콜백 첫 인자와 맞춰 보는 키이기도 하다
    let handle: UInt

    var ref: MTDeviceRef { UnsafeRawPointer(bitPattern: handle)! }

    /// 장치 포인터에서 식별 정보를 읽는다. 이름은 IORegistry의 Product, 없으면 종류 이름
    init(ref: MTDeviceRef, origin: String, api: MultitouchAPI, registry: [MultitouchDeviceEnumerator.RegistryEntry]) {
        var family: Int32 = 0
        var id: UInt64 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        _ = api.familyID(ref, &family)
        _ = api.deviceID(ref, &id)
        _ = api.surfaceDimensions(ref, &width, &height)
        let kind = DeviceFamily.kind(forFamilyID: family)
        let product = registry.first { $0.multitouchID == id }?.product ?? ""
        descriptor = InputDeviceDescriptor(
            id: id, kind: kind, name: product.isEmpty ? kind.displayName : product,
            surface: SurfaceSize(widthMM: Double(width) / 100, heightMM: Double(height) / 100)
        )
        familyID = family
        builtIn = api.isBuiltIn(ref)
        self.origin = origin
        handle = UInt(bitPattern: ref)
    }
}

/// 콜백이 준 접촉 배열의 레이아웃 (모든 공개 구현이 일치하는 96바이트 stride)
enum TouchRecord {
    static let stride = 96
    /// 레이아웃이 바뀌어 쓰레기 count가 와도 폭주하지 않게 상한을 둔다
    static let maxCount = 32

    /// 콜백 동안만 유효한 버퍼에서 접촉을 값으로 복사한다. Swift struct로 겹쳐 읽지 않고 오프셋으로 읽는다
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

/// 장치 열거. CreateList의 장치에 IORegistry에만 보이는 장치(블루투스 매직마우스)를 보탠다.
/// 돌려받은 CFArray와 장치 포인터, io_service_t는 해제하지 않고 프로세스 끝까지 둔다
public enum MultitouchDeviceEnumerator {
    /// 찾은 장치와 진단 메모 (CLI가 그대로 찍는다)
    public struct Outcome: Sendable {
        public var devices: [MultitouchDevice]
        public var notes: [String]
    }

    /// IORegistry의 AppleMultitouchDevice 항목. "Multitouch ID"는 MTDeviceGetDeviceID와 같은 값이다
    struct RegistryEntry: Sendable {
        let service: io_service_t
        let multitouchID: UInt64
        let familyID: Int32
        let product: String
    }

    /// 멀티터치 장치를 모두 찾는다. 연결된 매직마우스는 보통 CreateList에 바로 나오고, 빠지면 IORegistry 경로로 연다
    public static func enumerate(api: MultitouchAPI) -> Outcome {
        let registry = registryEntries()
        var notes = [
            "IORegistry AppleMultitouchDevice \(registry.count)개: "
                + registry.map { String(format: "0x%016llx(Family %d, \"%@\")", $0.multitouchID, $0.familyID, $0.product) }.joined(separator: ", ")
        ]
        var devices: [MultitouchDevice] = []
        if let list = api.createList()?.takeUnretainedValue() {
            for index in 0..<CFArrayGetCount(list) {
                guard let ref = CFArrayGetValueAtIndex(list, index) else { continue }
                devices.append(MultitouchDevice(ref: ref, origin: "CreateList", api: api, registry: registry))
            }
        }
        let known = Set(devices.map(\.descriptor.id))
        for entry in registry where !known.contains(entry.multitouchID) {
            let id = String(format: "0x%016llx", entry.multitouchID)
            if let ref = api.createFromService(entry.service) {
                devices.append(MultitouchDevice(ref: ref, origin: "service", api: api, registry: registry))
                notes.append("IORegistry 장치 \(id) (Family \(entry.familyID))는 CreateList에 없어 MTDeviceCreateFromService로 열었음")
            } else if let ref = api.createFromDeviceID(entry.multitouchID) {
                devices.append(MultitouchDevice(ref: ref, origin: "deviceID", api: api, registry: registry))
                notes.append("IORegistry 장치 \(id) (Family \(entry.familyID))는 CreateList에 없어 MTDeviceCreateFromDeviceID로 열었음")
            } else {
                notes.append("IORegistry 장치 \(id) (Family \(entry.familyID))를 어느 방법으로도 열 수 없음")
            }
        }
        return Outcome(devices: devices, notes: notes)
    }

    /// IOServiceMatching("AppleMultitouchDevice")로 멀티터치 장치를 모두 찾는다
    static func registryEntries() -> [RegistryEntry] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var entries: [RegistryEntry] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            // service는 MTDeviceCreateFromService에 넘겨야 하므로 release하지 않는다
            entries.append(RegistryEntry(
                service: service,
                multitouchID: (property(service, "Multitouch ID") as? NSNumber)?.uint64Value ?? 0,
                familyID: (property(service, "Family ID") as? NSNumber)?.int32Value ?? 0,
                product: property(service, "Product") as? String ?? ""
            ))
        }
        return entries
    }

    // IORegistry 속성 하나를 읽는다
    private static func property(_ service: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
