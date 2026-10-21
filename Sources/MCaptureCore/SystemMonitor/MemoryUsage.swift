import Foundation

/// `vm_statistics64`에서 뽑은 페이지 수. 입출력은 부팅 후 누적값
public struct MemoryPages: Sendable, Equatable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var wired: UInt64
    public var speculative: UInt64
    public var compressor: UInt64
    /// 익명(anonymous) 페이지. 활성 상태 보기의 "앱 메모리"는 여기서 purgeable을 뺀 값
    public var internalPages: UInt64
    public var purgeable: UInt64
    /// 파일 기반 페이지 (캐시된 파일)
    public var external: UInt64
    public var pageins: UInt64
    public var pageouts: UInt64

    public init(free: UInt64 = 0, active: UInt64 = 0, inactive: UInt64 = 0, wired: UInt64 = 0, speculative: UInt64 = 0,
                compressor: UInt64 = 0, internalPages: UInt64 = 0, purgeable: UInt64 = 0, external: UInt64 = 0,
                pageins: UInt64 = 0, pageouts: UInt64 = 0) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.wired = wired
        self.speculative = speculative
        self.compressor = compressor
        self.internalPages = internalPages
        self.purgeable = purgeable
        self.external = external
        self.pageins = pageins
        self.pageouts = pageouts
    }
}

/// 스왑 사용량 (바이트, `vm.swapusage`)
public struct SwapUsage: Sendable, Equatable {
    public var total: UInt64
    public var used: UInt64

    public init(total: UInt64, used: UInt64) {
        self.total = total
        self.used = used
    }

    /// 사용 비율 0~1
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// 메모리 압력 단계 (`kern.memorystatus_vm_pressure_level`: 1 보통, 2 경고, 4 위험)
public enum MemoryPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    public init(sysctlValue: Int) {
        switch sysctlValue {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

/// 한 시점의 메모리 상태. 활성 상태 보기와 같은 구분(앱·와이어드·압축됨)으로 나눈다
public struct MemoryUsage: Sendable, Equatable {
    /// 물리 메모리 전체 (`hw.memsize`)
    public let total: UInt64
    public let pageSize: UInt64
    /// 앱 메모리 = (internal − purgeable) 페이지
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    /// 압력 % = 100 − `kern.memorystatus_level`(시스템 전체 여유 비율)
    public let pressurePercent: Double
    public let pressureLevel: MemoryPressureLevel
    public let swap: SwapUsage
    /// 누적 페이지 입출력 (페이지 수)
    public let pageins: UInt64
    public let pageouts: UInt64

    public init(pages: MemoryPages, pageSize: UInt64, total: UInt64, memoryLevel: Int, pressureLevel: Int, swap: SwapUsage) {
        self.total = total
        self.pageSize = pageSize
        let appPages = pages.internalPages > pages.purgeable ? pages.internalPages - pages.purgeable : 0
        app = appPages * pageSize
        wired = pages.wired * pageSize
        compressed = pages.compressor * pageSize
        pressurePercent = Double(max(0, min(100, 100 - memoryLevel)))
        self.pressureLevel = MemoryPressureLevel(sysctlValue: pressureLevel)
        self.swap = swap
        pageins = pages.pageins
        pageouts = pages.pageouts
    }

    /// 사용 중 = 앱 + 와이어드 + 압축됨
    public var used: UInt64 { app + wired + compressed }

    /// 여유 = 전체 − 사용 중 (캐시된 파일도 여유로 본다)
    public var free: UInt64 { total > used ? total - used : 0 }

    public var usedPercent: Double { total > 0 ? min(100, Double(used) / Double(total) * 100) : 0 }

    /// 전체에 대한 비율 (링 분할용). 앱·와이어드·압축·여유 순, 합은 1
    public var fractions: (app: Double, wired: Double, compressed: Double, free: Double) {
        guard total > 0 else { return (0, 0, 0, 1) }
        let t = Double(total)
        return (Double(app) / t, Double(wired) / t, Double(compressed) / t, Double(free) / t)
    }
}

/// 두 샘플 사이의 페이지 입출력 속도 (바이트/초)
public struct PageActivity: Sendable, Equatable {
    public let pageinsPerSecond: Double
    public let pageoutsPerSecond: Double

    public static let zero = PageActivity(pageinsPerSecond: 0, pageoutsPerSecond: 0)

    public init(pageinsPerSecond: Double, pageoutsPerSecond: Double) {
        self.pageinsPerSecond = pageinsPerSecond
        self.pageoutsPerSecond = pageoutsPerSecond
    }

    /// 간격이 0이거나 값이 줄었으면(재부팅 등) 0
    public init(previous: MemoryUsage, current: MemoryUsage, interval: TimeInterval) {
        guard interval > 0, current.pageins >= previous.pageins, current.pageouts >= previous.pageouts else {
            self = .zero
            return
        }
        let page = Double(current.pageSize)
        pageinsPerSecond = Double(current.pageins - previous.pageins) * page / interval
        pageoutsPerSecond = Double(current.pageouts - previous.pageouts) * page / interval
    }
}
