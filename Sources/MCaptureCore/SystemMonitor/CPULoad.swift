import Foundation

/// 코어 하나의 누적 틱. `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`의 USER·SYSTEM·IDLE·NICE 값
public struct CPUCoreTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var total: UInt64 { user + system + idle + nice }
}

/// 한 시점의 코어별 누적 틱
public struct CPUTicks: Sendable, Equatable {
    public var cores: [CPUCoreTicks]

    public init(cores: [CPUCoreTicks]) {
        self.cores = cores
    }
}

/// 두 샘플 사이의 CPU 사용률 (0~100). nice는 사용자에 포함한다
///
/// 효율 코어는 앞 번호부터 `efficiencyCores`개다 (Apple Silicon의 논리 CPU 순서).
/// 효율 코어가 없으면(Intel, `hw.nperflevels == 1`) 모든 코어가 성능 그룹이다
public struct CPUUsage: Sendable, Equatable {
    /// 코어별 사용률
    public let cores: [Double]
    /// 효율 코어 수 (앞 번호부터). 0이면 모두 성능 코어
    public let efficiencyCores: Int
    /// 전체 사용률 = 사용자 + 시스템 (코어 평균)
    public let total: Double
    public let user: Double
    public let system: Double

    /// 두 샘플의 차이로 만든다. 코어 수가 다르거나 비어 있으면 nil
    public init?(previous: CPUTicks, current: CPUTicks, efficiencyCores: Int) {
        guard !current.cores.isEmpty, previous.cores.count == current.cores.count else { return nil }
        var cores: [Double] = []
        var userSum = 0.0
        var systemSum = 0.0
        for (before, after) in zip(previous.cores, current.cores) {
            let total = after.total &- before.total
            // 틱이 늘지 않았으면(절전 등) 0으로 본다
            guard total > 0, after.total >= before.total else {
                cores.append(0)
                continue
            }
            let user = Double((after.user &- before.user) &+ (after.nice &- before.nice)) / Double(total) * 100
            let system = Double(after.system &- before.system) / Double(total) * 100
            cores.append(min(100, user + system))
            userSum += user
            systemSum += system
        }
        let count = Double(cores.count)
        self.cores = cores
        self.efficiencyCores = max(0, min(efficiencyCores, cores.count))
        user = min(100, userSum / count)
        system = min(100, systemSum / count)
        total = min(100, user + system)
    }

    /// 코어 번호가 효율 코어인지
    public func isEfficiencyCore(_ index: Int) -> Bool {
        index < efficiencyCores
    }

    /// 효율 코어 평균. 효율 코어가 없으면 nil
    public var efficiencyAverage: Double? {
        guard efficiencyCores > 0 else { return nil }
        return Self.average(cores[..<efficiencyCores])
    }

    /// 성능 코어 평균 (효율 코어가 없으면 전체 평균)
    public var performanceAverage: Double {
        Self.average(cores[efficiencyCores...])
    }

    private static func average(_ values: ArraySlice<Double>) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
