import MCaptureCore
import SwiftUI

/// 메뉴바 CPU 항목의 팝오버: 기록 막대, 코어 링, 프로세스, GPU, 로드 평균, 가동 시간
struct CPUDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    static let width: CGFloat = 300
    /// 카드 안쪽 폭 (팝오버 여백 10 + 카드 여백 12를 양쪽에서 뺀 값)
    private static let cardContentWidth: CGFloat = width - 2 * 10 - 2 * 12
    /// 코어 링 사이 간격
    private static let coreSpacing: CGFloat = 6

    var body: some View {
        let snapshot = monitor.snapshot
        let cpu = snapshot?.cpu
        VStack(spacing: 8) {
            MonitorCard {
                CardHeader(title: "CPU", trailing: snapshot?.temperature.map { "\(Int($0.rounded()))°" } ?? cpu.map { MonitorFormat.percent($0.total) })
                HistoryBars(points: monitor.history.elements, capacity: monitor.history.capacity)
                HStack(spacing: 16) {
                    LegendRow(color: MonitorPalette.user, title: "사용자", value: cpu.map { MonitorFormat.percent($0.user) } ?? "–")
                    LegendRow(color: MonitorPalette.system, title: "시스템", value: cpu.map { MonitorFormat.percent($0.system) } ?? "–")
                }
            }

            if let cpu {
                coresCard(cpu)
            }

            ProcessCard(entries: monitor.topCPU) { MonitorFormat.percent($0.cpuPercent) }

            if let gpu = snapshot?.gpu, let snapshot {
                gpuCard(gpu, memoryTotal: snapshot.memory.total, temperature: snapshot.gpuTemperature)
            }

            ValueCard(title: "LOAD AVERAGE", value: snapshot.map { MonitorFormat.loadAverage($0.loadAverage) } ?? "–")
            ValueCard(title: "컴퓨터 가동 시간", value: snapshot?.uptime.map(MonitorFormat.uptime) ?? "–")
        }
        .padding(10)
        .frame(width: Self.width)
    }

    // 코어별 링 격자와 효율·성능 평균. 열 수와 링 크기는 코어 수에 맞춘다 (8코어 한 줄, 14코어 7+7, 16코어 8+8)
    private func coresCard(_ cpu: CPUUsage) -> some View {
        let cores = Self.debugCores(cpu.cores)
        let columns = CoreGridLayout.columns(for: cores.count)
        let diameter = CGFloat(CoreGridLayout.ringDiameter(columns: columns, availableWidth: Self.cardContentWidth, spacing: Self.coreSpacing))
        return MonitorCard {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(diameter), spacing: Self.coreSpacing), count: columns), spacing: 8) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                    RingGauge(fraction: usage / 100, color: cpu.isEfficiencyCore(index) ? MonitorPalette.system : MonitorPalette.user, lineWidth: 4)
                        .frame(width: diameter, height: diameter)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            if let efficiency = cpu.efficiencyAverage {
                LegendRow(color: MonitorPalette.system, title: "효율 코어", value: MonitorFormat.percent(efficiency))
                LegendRow(color: MonitorPalette.user, title: "성능 코어", value: MonitorFormat.percent(cpu.performanceAverage))
            } else {
                LegendRow(color: MonitorPalette.user, title: "코어 평균", value: MonitorFormat.percent(cpu.performanceAverage))
            }
        }
    }

    #if DEBUG
    /// 다른 칩의 코어 수를 흉내 낸다 (mcapture-dev://debug/monitor-show?kind=cpu&cores=8). 모자라면 앞 값을 되풀이해 채운다
    nonisolated(unsafe) static var debugCoreCount: Int?

    private static func debugCores(_ cores: [Double]) -> [Double] {
        guard let count = debugCoreCount, count > 0, !cores.isEmpty else { return cores }
        return (0..<count).map { cores[$0 % cores.count] }
    }
    #else
    private static func debugCores(_ cores: [Double]) -> [Double] { cores }
    #endif

    // GPU 사용률·메모리(통합 메모리 중 GPU 할당 비율)·온도 링. FPS·클럭은 공개 API가 없어 두지 않는다
    private func gpuCard(_ gpu: GPUStats, memoryTotal: UInt64, temperature: Double?) -> some View {
        MonitorCard {
            CardHeader(title: "GPU")
            // 링 사이는 일정한 간격, 전체는 가운데
            HStack(spacing: Self.gpuRingSpacing) {
                gpuRing(fraction: gpu.utilization / 100, value: MonitorFormat.percent(gpu.utilization), caption: "GPU")
                if let percent = gpu.memoryPercent(of: memoryTotal) {
                    gpuRing(fraction: percent / 100, value: MonitorFormat.percent(percent), caption: "메모리")
                }
                if let temperature {
                    gpuRing(fraction: temperature / 100, value: "\(Int(temperature.rounded()))°", caption: "온도")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            if let allocated = gpu.memoryAllocated {
                let inUse = gpu.memoryInUse.map { " · 사용 중 \(MonitorFormat.bytes($0))" } ?? ""
                Text("메모리: 전체 \(MonitorFormat.bytes(memoryTotal)) 중 GPU 할당 \(MonitorFormat.bytes(allocated))\(inUse)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// GPU 링 지름과 사이 간격 (3개 + 간격 2개 = 240pt, 카드 안쪽 256pt)
    private static let gpuRingDiameter: CGFloat = 66
    private static let gpuRingSpacing: CGFloat = 21

    // GPU 카드의 링. FPS·클럭 자리를 비워 두는 대신 링 세 개로 폭을 채운다
    private func gpuRing(fraction: Double, value: String, caption: String) -> some View {
        LabeledRing(segments: [RingSegment(fraction: fraction, color: MonitorPalette.user)],
                    value: value, caption: caption, diameter: Self.gpuRingDiameter, lineWidth: 6, valueSize: 17)
    }
}
