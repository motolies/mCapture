import Foundation
import IOKit
import MCaptureCore

/// 장치 목록 조회·표시·선택
enum DeviceTable {
    /// IORegistry의 AppleMultitouchDevice 항목. "Multitouch ID"는 MTDeviceGetDeviceID와 같은 값이다
    struct RegistryEntry: Sendable {
        let service: io_service_t
        let multitouchID: UInt64
        let familyID: Int32
        let product: String
    }

    /// CreateList의 장치에 IORegistry에만 보이는 장치(블루투스 매직마우스)를 보탠다
    /// 돌려받은 CFArray와 장치 포인터, io_service_t는 해제하지 않고 프로세스 끝까지 둔다
    static func enumerate(api: MTAPI) -> [MTDevice] {
        var devices: [MTDevice] = []
        if let list = api.createList()?.takeUnretainedValue() {
            for index in 0..<CFArrayGetCount(list) {
                guard let ref = CFArrayGetValueAtIndex(list, index) else { continue }
                devices.append(MTDevice(index: devices.count, ref: ref, origin: "CreateList", api: api))
            }
        }
        let known = Set(devices.map(\.deviceID))
        let entries = registryEntries()
        Console.line("IORegistry AppleMultitouchDevice \(entries.count)개: " + entries.map { String(format: "0x%016llx(Family %d, \"%@\")", $0.multitouchID, $0.familyID, $0.product) }.joined(separator: ", "))
        for entry in entries where !known.contains(entry.multitouchID) {
            let id = String(format: "0x%016llx", entry.multitouchID)
            if let ref = api.createFromService(entry.service) {
                devices.append(MTDevice(index: devices.count, ref: ref, origin: "service", api: api))
                Console.line("IORegistry 장치 \(id) (Family \(entry.familyID))는 CreateList에 없어 MTDeviceCreateFromService로 열었음")
            } else if let ref = api.createFromDeviceID(entry.multitouchID) {
                devices.append(MTDevice(index: devices.count, ref: ref, origin: "deviceID", api: api))
                Console.line("IORegistry 장치 \(id) (Family \(entry.familyID))는 CreateList에 없어 MTDeviceCreateFromDeviceID로 열었음")
            } else {
                Console.line("IORegistry 장치 \(id) (Family \(entry.familyID))를 어느 방법으로도 열 수 없음")
            }
        }
        return devices
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

    /// 표로 출력한다
    static func show(_ devices: [MTDevice]) {
        Console.line("멀티터치 장치 \(devices.count)개")
        Console.line("번호  Family  종류              내장    DeviceID            표면(mm)      열기")
        for d in devices {
            let family = String(d.familyID).padding(toLength: 6, withPad: " ", startingAt: 0)
            let name = familyName(d.familyID).padding(toLength: 17, withPad: " ", startingAt: 0)
            let builtIn = (d.builtIn ? "예" : "아니오").padding(toLength: 6, withPad: " ", startingAt: 0)
            let id = String(format: "0x%016llx", d.deviceID)
            let size = String(format: "%.1f x %.1f", d.widthMM, d.heightMM).padding(toLength: 13, withPad: " ", startingAt: 0)
            Console.line("\(d.index)     \(family)  \(name) \(builtIn)  \(id)  \(size) \(d.origin)")
        }
    }

    /// 옵션에 따라 시작할 장치를 고른다. 기본은 매직마우스만
    static func select(_ devices: [MTDevice], options: Options) -> [MTDevice] {
        if options.all { return devices }
        if let index = options.device { return devices.filter { $0.index == index } }
        return devices.filter(\.isMagicMouse)
    }

    /// 표에 적을 장치 종류 이름. "Magic Mouse"는 재생이 표면 크기를 읽는 열쇠이므로 바꾸지 않는다
    static func familyName(_ id: Int32) -> String {
        switch DeviceFamily.kind(forFamilyID: id) {
        case .magicMouse: "Magic Mouse"
        case .magicTrackpad: "Magic Trackpad"
        case .builtInTrackpad: "내장 트랙패드"
        case .unknown: "알 수 없음"
        }
    }
}
