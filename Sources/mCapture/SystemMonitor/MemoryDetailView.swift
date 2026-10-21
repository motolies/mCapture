import MCaptureCore
import SwiftUI

/// 메뉴바 MEM 항목의 팝오버: 압력·사용 링, 내역, 프로세스, 페이지 입출력, 스왑
struct MemoryDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    static let width: CGFloat = 300

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(spacing: 8) {
            if let memory = snapshot?.memory {
                ringsCard(memory)
                breakdownCard(memory)
            }

            ProcessCard(entries: monitor.topMemory) { MonitorFormat.bytes($0.footprint) }

            if let activity = snapshot?.pageActivity {
                MonitorCard {
                    LegendTextRow(title: "페이지 입력", value: MonitorFormat.bytes(UInt64(activity.pageinsPerSecond)) + "/s")
                    LegendTextRow(title: "페이지 출력", value: MonitorFormat.bytes(UInt64(activity.pageoutsPerSecond)) + "/s")
                }
            }

            if let swap = snapshot?.memory.swap {
                swapCard(swap)
            }
        }
        .padding(10)
        .frame(width: Self.width)
    }

    // 압력 링(단계 색)과 사용 링(앱·와이어드·압축·여유 분할)
    private func ringsCard(_ memory: MemoryUsage) -> some View {
        let fractions = memory.fractions
        return MonitorCard {
            HStack(spacing: 0) {
                Spacer()
                LabeledRing(segments: [RingSegment(fraction: memory.pressurePercent / 100, color: MonitorPalette.pressure(memory.pressureLevel))],
                            value: MonitorFormat.percent(memory.pressurePercent), caption: "압력")
                Spacer()
                LabeledRing(segments: [
                    RingSegment(fraction: fractions.app, color: MonitorPalette.user),
                    RingSegment(fraction: fractions.wired, color: MonitorPalette.system),
                    RingSegment(fraction: fractions.compressed, color: MonitorPalette.compressed),
                ], value: MonitorFormat.percent(memory.usedPercent), caption: "메모리")
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // 앱·와이어드·압축됨·여유
    private func breakdownCard(_ memory: MemoryUsage) -> some View {
        MonitorCard {
            LegendRow(color: MonitorPalette.user, title: "앱", value: MonitorFormat.bytes(memory.app))
            LegendRow(color: MonitorPalette.system, title: "와이어드", value: MonitorFormat.bytes(memory.wired))
            LegendRow(color: MonitorPalette.compressed, title: "압축됨", value: MonitorFormat.bytes(memory.compressed))
            LegendRow(color: MonitorPalette.free, title: "여유", value: MonitorFormat.bytes(memory.free))
        }
    }

    // 사용된 스왑과 막대
    private func swapCard(_ swap: SwapUsage) -> some View {
        MonitorCard {
            CardHeader(title: "사용된 스왑 공간", trailing: "\(MonitorFormat.bytes(swap.used))/\(MonitorFormat.bytes(swap.total))")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(MonitorPalette.user).frame(width: geometry.size.width * CGFloat(swap.fraction))
                }
            }
            .frame(height: 8)
        }
    }
}

/// 점 없이 제목과 값만 있는 줄
struct LegendTextRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}
