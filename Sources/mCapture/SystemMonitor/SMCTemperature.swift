import Darwin
import Foundation
import IOKit
import MCaptureCore

/// AppleSMC 사용자 클라이언트로 온도 센서를 읽는다
///
/// CPU 온도 키는 칩마다 다르다(M1 `Tp0*`, M2 `Tp1*`, M3 `Te*`·`Tf*`, M4 `Te*`·`Tp*`, Intel `TC*C`). GPU는 `Tg*`
/// 그래서 키를 모두 열거해 CPU 코어 센서(`Tp`·`Te`·`Tf`)와 GPU 센서(`Tg`)로 보이는 키만 골라 두고,
/// 10초마다 그 키들만 읽어 평균을 낸다. 하나도 없으면 온도를 보이지 않는다
enum SMCTemperature {
    /// SMC 호출 구조체 (80바이트, 커널 드라이버 `SMCKeyData_t`와 같은 배치)
    private struct KeyData {
        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Version()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        /// C에서는 keyInfo가 12바이트(끝 패딩 3)지만 Swift는 9바이트로 붙이므로 result가 C와 같은 40에 오도록 채운다
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    /// `kSMCHandleYPCEvent`
    private static let selector: UInt32 = 2

    /// 센서 한 개의 값
    struct Sensor: Sendable, Equatable {
        let key: String
        let type: String
        let size: Int
        let value: Double
    }

    /// 샘플마다 읽을 키. 자료형·크기를 같이 두어 읽을 때 키 정보 조회를 건너뛴다 (M4 Pro는 118개라 호출 수가 반으로 준다)
    struct SensorKey: Sendable, Equatable {
        let key: String
        let type: String
        let size: Int
    }

    /// CPU 코어 온도로 볼 키 접두어
    private static let cpuPrefixes = ["Tp", "Te", "Tf"]
    /// GPU 온도로 볼 키 접두어
    private static let gpuPrefixes = ["Tg"]

    /// 발견한 센서 키 묶음
    struct Keys: Sendable, Equatable {
        var cpu: [SensorKey] = []
        var gpu: [SensorKey] = []
    }
    /// 센서 값으로 인정하는 섭씨 범위
    private static let plausibleRange = 5.0...125.0

    /// 모든 온도 키(`T`로 시작, 숫자형)를 읽는다. 연결에 실패하면 nil
    static func readAllTemperatures() -> [Sensor]? {
        guard let connection = open() else { return nil }
        defer { IOServiceClose(connection) }
        guard let count = readValue(connection, key: "#KEY").map({ Int($0) }), count > 0 else { return [] }
        var sensors: [Sensor] = []
        for index in 0..<min(count, 4096) {
            guard let key = keyName(connection, at: index), key.hasPrefix("T") else { continue }
            guard let info = keyInfo(connection, key: key) else { continue }
            guard let value = readValue(connection, key: key, info: info) else { continue }
            sensors.append(Sensor(key: key, type: info.type, size: info.size, value: value))
        }
        return sensors
    }

    /// CPU 코어·GPU 센서로 보이는 키들 (앱 시작 때 한 번 찾는다). 이름·자료형으로만 고른다
    /// 값은 보지 않는다: 유휴 상태에서는 꺼진 코어 클러스터의 센서가 0°를 주므로(M4 Pro `Tp1*`·`Tp2*`) 읽을 때 걸러 낸다
    static func discoverKeys() -> Keys {
        guard let sensors = readAllTemperatures() else { return Keys() }
        func select(_ prefixes: [String]) -> [SensorKey] {
            sensors
                .filter { sensor in prefixes.contains { sensor.key.hasPrefix($0) } && sensor.type == "flt " }
                .map { SensorKey(key: $0.key, type: $0.type, size: $0.size) }
        }
        return Keys(cpu: select(cpuPrefixes), gpu: select(gpuPrefixes))
    }

    /// 주어진 키들의 평균 온도. 읽히는 값이 없으면 nil
    static func readAverage(keys: [SensorKey]) -> Double? {
        guard !keys.isEmpty, let connection = open() else { return nil }
        defer { IOServiceClose(connection) }
        var values: [Double] = []
        for sensor in keys {
            if let value = readValue(connection, key: sensor.key, info: (sensor.type, sensor.size)), plausibleRange.contains(value) {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - SMC 호출

    // AppleSMC 서비스에 연결한다
    private static func open() -> io_connect_t? {
        assert(MemoryLayout<KeyData>.size == 80, "SMCKeyData_t 배치가 다름")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, task_self_trap(), 0, &connection) == KERN_SUCCESS else { return nil }
        return connection
    }

    // 구조체를 보내고 응답을 받는다
    private static func call(_ connection: io_connect_t, _ input: KeyData) -> KeyData? {
        var input = input
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.size
        let result = IOConnectCallStructMethod(connection, selector, &input, MemoryLayout<KeyData>.size, &output, &outputSize)
        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    // index번째 키 이름
    private static func keyName(_ connection: io_connect_t, at index: Int) -> String? {
        var input = KeyData()
        input.data8 = Command.keyFromIndex.rawValue
        input.data32 = UInt32(index)
        guard let output = call(connection, input) else { return nil }
        return string(from: output.key)
    }

    // 키의 자료형과 크기
    private static func keyInfo(_ connection: io_connect_t, key: String) -> (type: String, size: Int)? {
        var input = KeyData()
        input.key = code(for: key)
        input.data8 = Command.keyInfo.rawValue
        guard let output = call(connection, input) else { return nil }
        return (string(from: output.keyInfo.dataType), Int(output.keyInfo.dataSize))
    }

    // 키 값을 읽어 숫자로 바꾼다. info가 없으면 먼저 조회한다
    private static func readValue(_ connection: io_connect_t, key: String, info: (type: String, size: Int)? = nil) -> Double? {
        guard let info = info ?? keyInfo(connection, key: key) else { return nil }
        var input = KeyData()
        input.key = code(for: key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Command.readKey.rawValue
        guard let output = call(connection, input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(info.size)) }
        return decode(bytes, type: info.type)
    }

    // SMC 자료형 → 숫자. flt(리틀 엔디언 Float, Apple Silicon), sp78(고정 소수점, Intel), 부호 없는 정수
    private static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    // "#KEY" 같은 4글자 키 → 빅 엔디언 UInt32
    private static func code(for key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
