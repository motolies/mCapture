import Combine
import Foundation
import MCaptureCore

/// 한 시점의 시스템 상태 (2초마다 갱신)
struct SystemSnapshot: Sendable {
    let time: ContinuousClock.Instant
    let ticks: CPUTicks
    /// 첫 샘플은 비교 대상이 없어 nil
    let cpu: CPUUsage?
    let memory: MemoryUsage
    let pageActivity: PageActivity
    let loadAverage: [Double]
    let bootTime: Date?
    let gpu: GPUStats?
    /// CPU 온도(섭씨, 코어 센서 평균). SMC를 읽지 못하면 nil
    let temperature: Double?
    /// GPU 온도(섭씨, `Tg*` 평균)
    let gpuTemperature: Double?
    /// 온도를 마지막으로 읽은 시각. SMC 읽기는 키 117개에 약 25ms라 샘플마다 하지 않는다
    let temperatureReadAt: ContinuousClock.Instant?

    /// 부팅 후 지난 시간 (초)
    var uptime: TimeInterval? {
        bootTime.map { Date().timeIntervalSince($0) }
    }
}

/// CPU 기록 막대 한 칸 (사용자·시스템 %)
struct CPUHistoryPoint: Sendable, Equatable {
    let user: Double
    let system: Double
}

/// 시스템 상태 샘플러. 1초마다 메인 밖에서 읽어 메인 액터의 published 값으로 내보낸다
@MainActor
final class SystemMonitor: ObservableObject {
    /// 샘플 간격. 한 샘플이 0.3~0.6ms라 1초여도 CPU 0.1% 안팎
    nonisolated static let interval: Duration = .seconds(1)
    /// 온도 읽기 간격 (SMC 호출 비용 때문에 샘플 간격보다 길다)
    nonisolated static let temperatureInterval: Duration = .seconds(10)
    /// 프로세스 목록은 몇 샘플마다 읽는지 (`ps`가 약 20ms라 1초마다는 하지 않는다)
    nonisolated static let processEverySamples = 2
    /// 기록 막대 칸 수 (1초 간격이라 1분)
    nonisolated static let historyLength = 60

    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var history = UsageHistory<CPUHistoryPoint>(capacity: SystemMonitor.historyLength)
    /// CPU·메모리 상위 프로세스 (팝오버가 열려 있는 동안만 채운다)
    @Published private(set) var topCPU: [ProcessEntry] = []
    @Published private(set) var topMemory: [ProcessEntry] = []
    /// 팝오버가 열려 있는 동안 true. 켜지면 바로 한 번 조회하고 그 뒤로는 2샘플마다 조회한다
    var wantsProcesses = false {
        didSet {
            if wantsProcesses, !oldValue {
                refreshProcesses()
            } else if !wantsProcesses {
                processTask?.cancel()
                processTask = nil
            }
        }
    }
    private var task: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    /// CPU·GPU 온도 센서 키. 시작할 때 한 번 찾는다
    private(set) var temperatureKeys = SMCTemperature.Keys()

    /// 샘플링을 시작한다. 이미 돌고 있으면 그대로
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            let keys = await Self.discoverTemperatureKeys()
            self?.temperatureKeys = keys
            var previous: SystemSnapshot?
            var count = 0
            while !Task.isCancelled {
                let snapshot = await Self.read(previous: previous, temperatureKeys: keys)
                previous = snapshot
                count += 1
                guard let self else { return }
                self.publish(snapshot)
                if self.wantsProcesses, count % Self.processEverySamples == 0 { self.refreshProcesses() }
                do { try await Task.sleep(for: Self.interval) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // 스냅샷을 내보내고 CPU 기록에 더한다
    private func publish(_ snapshot: SystemSnapshot) {
        if let cpu = snapshot.cpu {
            history.append(CPUHistoryPoint(user: cpu.user, system: cpu.system))
        }
        self.snapshot = snapshot
    }

    // 프로세스 목록을 메인 밖에서 읽어 온다. 이전 조회가 아직 끝나지 않았으면 취소한다
    private func refreshProcesses() {
        processTask?.cancel()
        processTask = Task { [weak self] in
            let lists = await Self.readProcesses()
            guard !Task.isCancelled, let self else { return }
            self.topCPU = lists.cpu
            self.topMemory = lists.memory
        }
    }

    @concurrent
    private static func readProcesses() async -> (cpu: [ProcessEntry], memory: [ProcessEntry]) {
        let cpu = ProcessRanking.topByCPU(ProcessRanking.group(ProcessStatsReader.readCPUSamples()))
        let memory = ProcessRanking.topByFootprint(ProcessRanking.group(ProcessStatsReader.readMemorySamples()))
        return (cpu, memory)
    }

    /// 시스템 값을 읽는다. @concurrent라 협력 스레드 풀에서 돈다 (FileSearcher와 같은 방식)
    @concurrent
    private static func discoverTemperatureKeys() async -> SMCTemperature.Keys {
        let keys = SMCTemperature.discoverKeys()
        Log.monitor.info("온도 센서 CPU \(keys.cpu.count)개, GPU \(keys.gpu.count)개: \(keys.cpu.map(\.key).joined(separator: " "), privacy: .public) / \(keys.gpu.map(\.key).joined(separator: " "), privacy: .public)")
        return keys
    }

    @concurrent
    private static func read(previous: SystemSnapshot?, temperatureKeys: SMCTemperature.Keys) async -> SystemSnapshot {
        let now = ContinuousClock.now
        let clock = ContinuousClock()
        let ticks = SystemStatsReader.readTicks() ?? CPUTicks(cores: [])
        let memory = SystemStatsReader.readMemory()
            ?? MemoryUsage(pages: MemoryPages(), pageSize: SystemStatsReader.pageSize, total: SystemStatsReader.physicalMemory,
                           memoryLevel: 100, pressureLevel: 1, swap: SwapUsage(total: 0, used: 0))
        var cpu: CPUUsage?
        var activity = PageActivity.zero
        if let previous {
            cpu = CPUUsage(previous: previous.ticks, current: ticks, efficiencyCores: SystemStatsReader.efficiencyCores)
            activity = PageActivity(previous: previous.memory, current: memory, interval: (now - previous.time).milliseconds / 1000)
        }
        let loadAverage = SystemStatsReader.readLoadAverage()
        let bootTime = SystemStatsReader.readBootTime()
        let gpu = SystemStatsReader.readGPU()
        // 온도는 10초에 한 번만 읽고 그 사이에는 이전 값을 쓴다
        var temperature = previous?.temperature
        var gpuTemperature = previous?.gpuTemperature
        var temperatureReadAt = previous?.temperatureReadAt
        if let readAt = temperatureReadAt, now - readAt < temperatureInterval {
            // 이전 값 유지
        } else {
            temperature = SMCTemperature.readAverage(keys: temperatureKeys.cpu)
            gpuTemperature = SMCTemperature.readAverage(keys: temperatureKeys.gpu)
            temperatureReadAt = now
        }
        Log.monitor.debug("샘플 \((clock.now - now).milliseconds, format: .fixed(precision: 1))ms, 온도 읽음 \(temperatureReadAt == now)")
        return SystemSnapshot(
            time: now,
            ticks: ticks,
            cpu: cpu,
            memory: memory,
            pageActivity: activity,
            loadAverage: loadAverage,
            bootTime: bootTime,
            gpu: gpu,
            temperature: temperature,
            gpuTemperature: gpuTemperature,
            temperatureReadAt: temperatureReadAt
        )
    }
}
