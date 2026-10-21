import Foundation

/// 프로세스 하나의 샘플. CPU 목록(`ps`)은 cpuPercent만, 메모리 목록(`proc_pid_rusage`)은 footprint만 채운다
public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    /// 실행 파일 경로. kernel_task처럼 경로가 없는 프로세스는 이름만
    public let path: String
    public let cpuPercent: Double?
    public let footprint: UInt64?

    public init(pid: Int32, path: String, cpuPercent: Double? = nil, footprint: UInt64? = nil) {
        self.pid = pid
        self.path = path
        self.cpuPercent = cpuPercent
        self.footprint = footprint
    }
}

/// 같은 앱의 프로세스(브라우저 헬퍼 등)를 합친 항목. 목록에는 이 단위로 보인다
public struct ProcessEntry: Sendable, Equatable, Identifiable {
    /// 아이콘·이름의 기준 경로 (.app 번들 또는 실행 파일)
    public let path: String
    public let name: String
    public let cpuPercent: Double
    public let footprint: UInt64
    public let processCount: Int

    public var id: String { path }

    public init(path: String, name: String, cpuPercent: Double, footprint: UInt64, processCount: Int) {
        self.path = path
        self.name = name
        self.cpuPercent = cpuPercent
        self.footprint = footprint
        self.processCount = processCount
    }
}

/// 프로세스 경로에서 표시 이름·번들을 구한다
public enum ProcessName {
    /// 경로에서 가장 바깥쪽 `.app` 번들 경로. 없으면 nil
    /// 헬퍼(`Google Chrome.app/…/Google Chrome Helper.app/…`)는 바깥 앱으로 모아 활성 상태 보기보다 iStat에 가깝게 보인다
    public static func appBundlePath(in path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else { return nil }
        return parts[...index].joined(separator: "/")
    }

    /// 묶음 기준 경로: `.app` 번들이 있으면 번들, 아니면 실행 파일 경로
    public static func groupPath(for path: String) -> String {
        appBundlePath(in: path) ?? path
    }

    /// 표시 이름: 번들 이름(확장자 뺌) 또는 마지막 경로 구성 요소. 경로가 없으면 그대로
    public static func displayName(forPath path: String) -> String {
        let base = groupPath(for: path)
        guard let last = base.split(separator: "/").last, !last.isEmpty else { return path }
        var name = String(last)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }
}

/// `ps -Aro pid=,pcpu=,comm=` 출력 파서
public enum ProcessListParser {
    /// 한 줄 = `pid pcpu 경로`. 경로에는 공백이 있을 수 있어 앞 두 토큰만 나누고 나머지를 경로로 본다. 잘못된 줄은 건너뛴다
    public static func parsePS(_ output: String) -> [ProcessSample] {
        var samples: [ProcessSample] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let cpu = Double(fields[1]) else { continue }
            let path = fields[2].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            samples.append(ProcessSample(pid: pid, path: path, cpuPercent: cpu))
        }
        return samples
    }
}

/// 프로세스 샘플을 앱 단위로 합치고 순위를 매긴다
public enum ProcessRanking {
    /// 같은 번들·실행 파일의 샘플을 합친다 (CPU·footprint 합, 프로세스 수)
    public static func group(_ samples: [ProcessSample]) -> [ProcessEntry] {
        var order: [String] = []
        var cpu: [String: Double] = [:]
        var footprint: [String: UInt64] = [:]
        var counts: [String: Int] = [:]
        for sample in samples {
            let key = ProcessName.groupPath(for: sample.path)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
            cpu[key, default: 0] += sample.cpuPercent ?? 0
            footprint[key, default: 0] += sample.footprint ?? 0
        }
        return order.map {
            ProcessEntry(path: $0, name: ProcessName.displayName(forPath: $0), cpuPercent: cpu[$0] ?? 0,
                         footprint: footprint[$0] ?? 0, processCount: counts[$0] ?? 0)
        }
    }

    /// CPU 순 상위 N (같으면 이름순)
    public static func topByCPU(_ entries: [ProcessEntry], limit: Int = 5) -> [ProcessEntry] {
        Array(entries.sorted { ($0.cpuPercent, $1.name) > ($1.cpuPercent, $0.name) }.prefix(limit))
    }

    /// 메모리(footprint) 순 상위 N
    public static func topByFootprint(_ entries: [ProcessEntry], limit: Int = 5) -> [ProcessEntry] {
        Array(entries.sorted { ($0.footprint, $1.name) > ($1.footprint, $0.name) }.prefix(limit))
    }
}
