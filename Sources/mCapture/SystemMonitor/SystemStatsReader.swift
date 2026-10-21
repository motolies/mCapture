import Darwin
import Foundation
import IOKit
import MCaptureCore

/// GPU 상태 (IORegistry `IOAccelerator`의 `PerformanceStatistics`)
struct GPUStats: Sendable, Equatable {
    /// `Device Utilization %`
    let utilization: Double
    /// `In use system memory` (바이트). 없으면 nil
    let memoryInUse: UInt64?
    /// `Alloc system memory` (바이트). 통합 메모리에서 GPU 드라이버가 할당한 양
    let memoryAllocated: UInt64?

    /// 물리 메모리 대비 GPU 할당 비율 % (통합 메모리라 "GPU 메모리 사용률"로 본다)
    func memoryPercent(of total: UInt64) -> Double? {
        guard let memoryAllocated, total > 0 else { return nil }
        return min(100, Double(memoryAllocated) / Double(total) * 100)
    }
}

/// 시스템 상태를 Mach·sysctl·IOKit에서 읽는다. 모두 동기 호출이고 메인 밖에서 불러도 된다
enum SystemStatsReader {
    /// `mach_host_self()`는 부를 때마다 포트 참조를 늘리므로 한 번만 얻어 둔다
    private static let host = mach_host_self()

    /// 효율 코어 수 (앞 번호부터). `hw.nperflevels`가 2 미만이면(Intel) 0
    static let efficiencyCores: Int = {
        guard (sysctlValue("hw.nperflevels") as Int32? ?? 1) >= 2 else { return 0 }
        return Int(sysctlValue("hw.perflevel1.logicalcpu") as Int32? ?? 0)
    }()

    /// 물리 메모리 (`hw.memsize`)
    static let physicalMemory: UInt64 = sysctlValue("hw.memsize") ?? 0

    /// 커널 페이지 크기 (`hw.pagesize`, Apple Silicon 16KB)
    static let pageSize: UInt64 = UInt64(sysctlValue("hw.pagesize") as Int32? ?? 4096)

    /// 코어별 누적 틱
    static func readTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else {
            return nil
        }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(task_self_trap(), vm_address_t(bitPattern: info), bytes)
        }
        let states = Int(CPU_STATE_MAX)
        var cores: [CPUCoreTicks] = []
        cores.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * states
            cores.append(CPUCoreTicks(
                user: UInt64(info[base + Int(CPU_STATE_USER)]),
                system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return CPUTicks(cores: cores)
    }

    /// 메모리 상태 (`host_statistics64` + sysctl 압력·스왑)
    static func readMemory() -> MemoryUsage? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = MemoryPages(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            wired: UInt64(stats.wire_count),
            speculative: UInt64(stats.speculative_count),
            compressor: UInt64(stats.compressor_page_count),
            internalPages: UInt64(stats.internal_page_count),
            purgeable: UInt64(stats.purgeable_count),
            external: UInt64(stats.external_page_count),
            pageins: stats.pageins,
            pageouts: stats.pageouts
        )
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsage = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
            ? SwapUsage(total: swap.xsu_total, used: swap.xsu_used)
            : SwapUsage(total: 0, used: 0)
        return MemoryUsage(
            pages: pages,
            pageSize: pageSize,
            total: physicalMemory,
            memoryLevel: Int(sysctlValue("kern.memorystatus_level") as Int32? ?? 100),
            pressureLevel: Int(sysctlValue("kern.memorystatus_vm_pressure_level") as Int32? ?? 1),
            swap: swapUsage
        )
    }

    /// 로드 평균 1·5·15분
    static func readLoadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return [] }
        return loads
    }

    /// 부팅 시각 (`kern.boottime`)
    static func readBootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// GPU 사용률·메모리. `IOAccelerator` 서비스 중 `Device Utilization %`가 있는 첫 항목
    static func readGPU() -> GPUStats? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { return nil }
            defer { IOObjectRelease(entry) }
            guard let raw = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = raw.takeRetainedValue() as? [String: Any],
                  let utilization = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            let inUse = (stats["In use system memory"] as? NSNumber).map { UInt64(truncatingIfNeeded: $0.int64Value) }
            let allocated = (stats["Alloc system memory"] as? NSNumber).map { UInt64(truncatingIfNeeded: $0.int64Value) }
            return GPUStats(utilization: max(0, min(100, utilization)), memoryInUse: inUse, memoryAllocated: allocated)
        }
    }

    // 정수 sysctl 값
    private static func sysctlValue<T: FixedWidthInteger>(_ name: String) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
