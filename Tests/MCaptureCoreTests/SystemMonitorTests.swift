import Foundation
import Testing
@testable import MCaptureCore

@Suite("CPULoad")
struct CPULoadTests {
    private func ticks(_ cores: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)]) -> CPUTicks {
        CPUTicks(cores: cores.map { CPUCoreTicks(user: $0.user, system: $0.system, idle: $0.idle, nice: $0.nice) })
    }

    @Test func 틱_차이로_사용률을_구한다() {
        let before = ticks([(100, 50, 850, 0), (0, 0, 1000, 0)])
        let after = ticks([(150, 70, 880, 0), (0, 0, 1100, 0)])
        let usage = CPUUsage(previous: before, current: after, efficiencyCores: 0)!
        // 코어 0: 100틱 중 user 50 + system 20 = 70%, 코어 1: idle만 늘어 0%
        #expect(usage.cores == [70, 0])
        #expect(usage.user == 25)
        #expect(usage.system == 10)
        #expect(usage.total == 35)
    }

    @Test func nice는_사용자에_포함하고_전부_바쁘면_100() {
        let before = ticks([(0, 0, 0, 0)])
        let after = ticks([(30, 20, 0, 50)])
        let usage = CPUUsage(previous: before, current: after, efficiencyCores: 0)!
        #expect(usage.user == 80)
        #expect(usage.system == 20)
        #expect(usage.total == 100)
    }

    @Test func 틱이_늘지_않으면_0이고_코어_수가_다르면_nil() {
        let same = ticks([(10, 10, 10, 0)])
        #expect(CPUUsage(previous: same, current: same, efficiencyCores: 0)?.total == 0)
        #expect(CPUUsage(previous: same, current: ticks([(10, 10, 10, 0), (0, 0, 0, 0)]), efficiencyCores: 0) == nil)
        #expect(CPUUsage(previous: ticks([]), current: ticks([]), efficiencyCores: 0) == nil)
    }

    @Test func 효율_코어는_앞_번호부터_나눈다() {
        let before = ticks([(0, 0, 100, 0), (0, 0, 100, 0), (0, 0, 100, 0)])
        let after = ticks([(80, 0, 120, 0), (20, 0, 180, 0), (0, 0, 200, 0)])
        let usage = CPUUsage(previous: before, current: after, efficiencyCores: 2)!
        #expect(usage.cores == [80, 20, 0])
        #expect(usage.isEfficiencyCore(1))
        #expect(!usage.isEfficiencyCore(2))
        #expect(usage.efficiencyAverage == 50)
        #expect(usage.performanceAverage == 0)
    }

    @Test func 효율_코어가_없으면_성능_평균이_전체_평균() {
        let before = ticks([(0, 0, 100, 0), (0, 0, 100, 0)])
        let after = ticks([(100, 0, 100, 0), (0, 0, 200, 0)])
        let usage = CPUUsage(previous: before, current: after, efficiencyCores: 0)!
        #expect(usage.efficiencyAverage == nil)
        // 코어 0은 100%, 코어 1은 0%
        #expect(usage.performanceAverage == 50)
        // 코어 수보다 큰 값은 코어 수로 자른다
        #expect(CPUUsage(previous: before, current: after, efficiencyCores: 9)!.efficiencyCores == 2)
    }
}

@Suite("MemoryUsage")
struct MemoryUsageTests {
    let page: UInt64 = 16_384
    let gb: UInt64 = 1 << 30

    private func usage(level: Int = 53, pressure: Int = 1) -> MemoryUsage {
        // 24GB 중 앱 5.5GB(익명 6GB에서 퍼지 가능 0.5GB 제외), 와이어드 5.25GB, 압축 9.5GB (모두 페이지 크기의 배수)
        let pages = MemoryPages(wired: 21 * gb / 4 / page, compressor: 19 * gb / 2 / page,
                                internalPages: 6 * gb / page, purgeable: gb / 2 / page,
                                pageins: 1000, pageouts: 10)
        return MemoryUsage(pages: pages, pageSize: page, total: 24 * gb, memoryLevel: level, pressureLevel: pressure,
                           swap: SwapUsage(total: 7 * gb, used: 6_300 * gb / 1000))
    }

    @Test func 앱_와이어드_압축_여유를_나누고_합은_전체() {
        let memory = usage()
        #expect(memory.app == 11 * gb / 2)
        #expect(memory.wired == 21 * gb / 4)
        #expect(memory.compressed == 19 * gb / 2)
        #expect(memory.used == memory.app + memory.wired + memory.compressed)
        #expect(memory.free == memory.total - memory.used)
        // (5.5 + 5.25 + 9.5) / 24
        #expect(abs(memory.usedPercent - 84.375) < 0.01)
        let f = memory.fractions
        #expect(abs(f.app + f.wired + f.compressed + f.free - 1) < 1e-9)
    }

    @Test func 압력은_100에서_여유_비율을_뺀_값() {
        #expect(usage(level: 53).pressurePercent == 47)
        #expect(usage(level: 120).pressurePercent == 0)
        #expect(usage(level: -5).pressurePercent == 100)
        #expect(usage(pressure: 1).pressureLevel == .normal)
        #expect(usage(pressure: 2).pressureLevel == .warning)
        #expect(usage(pressure: 4).pressureLevel == .critical)
        #expect(usage(pressure: 99).pressureLevel == .normal)
    }

    @Test func 퍼지_가능이_익명보다_크면_앱은_0() {
        let pages = MemoryPages(internalPages: 10, purgeable: 20)
        let memory = MemoryUsage(pages: pages, pageSize: page, total: 0, memoryLevel: 50, pressureLevel: 1,
                                 swap: SwapUsage(total: 0, used: 0))
        #expect(memory.app == 0)
        #expect(memory.usedPercent == 0)
        #expect(memory.swap.fraction == 0)
        #expect(memory.fractions.free == 1)
    }

    @Test func 페이지_입출력_속도는_차이를_초로_나눈다() {
        let before = usage()
        let after = MemoryUsage(pages: MemoryPages(pageins: 1100, pageouts: 10), pageSize: page, total: 24 * gb,
                                memoryLevel: 50, pressureLevel: 1, swap: SwapUsage(total: 0, used: 0))
        let activity = PageActivity(previous: before, current: after, interval: 2)
        #expect(activity.pageinsPerSecond == Double(100 * page) / 2)
        #expect(activity.pageoutsPerSecond == 0)
        #expect(PageActivity(previous: after, current: before, interval: 2) == .zero)
        #expect(PageActivity(previous: before, current: after, interval: 0) == .zero)
    }
}

@Suite("UsageHistory")
struct UsageHistoryTests {
    @Test func 용량을_넘으면_오래된_것부터_버린다() {
        var history = UsageHistory<Int>(capacity: 3)
        for value in 1...5 { history.append(value) }
        #expect(history.elements == [3, 4, 5])
        #expect(history.count == 3)
        #expect(history.last == 5)
        #expect(UsageHistory<Int>(capacity: 0).capacity == 1)
    }
}

@Suite("ProcessUsage")
struct ProcessUsageTests {
    @Test func ps_출력을_파싱하고_경로의_공백을_지킨다() {
        let output = """
          406 _windowserver  8.9 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        32210   12.5 /Users/nwkim/Applications/IntelliJ IDEA.app/Contents/MacOS/idea
            0    5.9 kernel_task
        잘못된 줄
        12 abc /bin/x
        """
        let samples = ProcessListParser.parsePS(output)
        #expect(samples.count == 2)
        #expect(samples[0] == ProcessSample(pid: 32210, path: "/Users/nwkim/Applications/IntelliJ IDEA.app/Contents/MacOS/idea", cpuPercent: 12.5))
        #expect(samples[1] == ProcessSample(pid: 0, path: "kernel_task", cpuPercent: 5.9))
    }

    @Test func 표시_이름은_가장_바깥_app_번들_또는_파일_이름() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(ProcessName.appBundlePath(in: helper) == "/Applications/Google Chrome.app")
        #expect(ProcessName.displayName(forPath: helper) == "Google Chrome")
        #expect(ProcessName.displayName(forPath: "/Applications/Warp.app/Contents/MacOS/stable") == "Warp")
        #expect(ProcessName.displayName(forPath: "/usr/sbin/bluetoothd") == "bluetoothd")
        #expect(ProcessName.displayName(forPath: "kernel_task") == "kernel_task")
        #expect(ProcessName.appBundlePath(in: "/usr/sbin/bluetoothd") == nil)
        // 이름이 ".app"뿐인 구성 요소는 번들로 보지 않는다
        #expect(ProcessName.appBundlePath(in: "/tmp/.app/x") == nil)
    }

    @Test func 같은_앱의_프로세스를_합치고_순위를_매긴다() {
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        let samples = [
            ProcessSample(pid: 1, path: chrome, cpuPercent: 10, footprint: 1000),
            ProcessSample(pid: 2, path: helper, cpuPercent: 5, footprint: 3000),
            ProcessSample(pid: 3, path: "/usr/sbin/bluetoothd", cpuPercent: 20, footprint: 100),
            ProcessSample(pid: 4, path: "kernel_task", cpuPercent: 20),
        ]
        let entries = ProcessRanking.group(samples)
        #expect(entries.map(\.name) == ["Google Chrome", "bluetoothd", "kernel_task"])
        #expect(entries[0] == ProcessEntry(path: "/Applications/Google Chrome.app", name: "Google Chrome", cpuPercent: 15, footprint: 4000, processCount: 2))
        // CPU 같으면 이름순, 상위 2개
        #expect(ProcessRanking.topByCPU(entries, limit: 2).map(\.name) == ["bluetoothd", "kernel_task"])
        #expect(ProcessRanking.topByFootprint(entries, limit: 2).map(\.name) == ["Google Chrome", "bluetoothd"])
    }
}

@Suite("MonitorFormat")
struct MonitorFormatTests {
    @Test func 바이트_표시() {
        #expect(MonitorFormat.bytes(0) == "0KB")
        #expect(MonitorFormat.bytes(500) == "0KB")
        #expect(MonitorFormat.bytes(812 * 1024) == "812KB")
        #expect(MonitorFormat.bytes(5_500 * 1024 * 1024 / 1000) == "5.5MB")
        #expect(MonitorFormat.bytes(812 * 1024 * 1024) == "812MB")
        #expect(MonitorFormat.bytes(10_300 * (1 << 30) / 1000) == "10.3GB")
        #expect(MonitorFormat.bytes(4 << 30) == "4.0GB")
    }

    @Test func 퍼센트_가동_시간_로드_평균() {
        #expect(MonitorFormat.percent(23.6) == "24%")
        #expect(MonitorFormat.percent(0) == "0%")
        #expect(MonitorFormat.uptime(4 * 86_400 + 20 * 3600 + 59 * 60) == "4일 20시간")
        #expect(MonitorFormat.uptime(20 * 3600 + 5 * 60 + 30) == "20시간 5분")
        #expect(MonitorFormat.uptime(12 * 60 + 59) == "12분")
        #expect(MonitorFormat.uptime(-5) == "0분")
        #expect(MonitorFormat.loadAverage([2.91, 2.66, 3.18]) == "2.91  2.66  3.18")
    }

    @Test func 임계값_판정() {
        let threshold = MonitorThreshold(enabled: true, percent: 60)
        #expect(threshold.exceeds(60))
        #expect(!threshold.exceeds(59.9))
        #expect(!MonitorThreshold(enabled: false, percent: 0).exceeds(100))
        #expect(MonitorThreshold(enabled: true, percent: 150).percent == 100)
    }
}

@Suite("CoreGridLayout")
struct CoreGridLayoutTests {
    @Test func 코어_수마다_줄이_고르게_차는_열_수() {
        // (코어 수, 열 수): M1·M2·M3 8, M1 Pro·M4 10, M2 Pro·M3 Pro 12, M4 Pro 14, M3 Max·M4 Max 16, Ultra 24·32
        let expected: [(Int, Int)] = [(1, 1), (4, 4), (6, 6), (8, 8), (9, 5), (10, 5), (12, 6), (14, 7), (16, 8), (17, 6), (20, 7), (24, 8), (32, 8)]
        for (count, columns) in expected {
            #expect(CoreGridLayout.columns(for: count) == columns, "코어 \(count)개")
        }
        #expect(CoreGridLayout.columns(for: 0) == 1)
        #expect(CoreGridLayout.columns(for: 14, maxColumns: 7) == 7)
    }

    @Test func 줄_수는_최소이고_그_줄_수를_내는_가장_작은_열_수다() {
        for count in 1...64 {
            let columns = CoreGridLayout.columns(for: count)
            let rows = (count + columns - 1) / columns
            let minimumRows = (count + 7) / 8
            #expect(columns >= 1 && columns <= 8, "코어 \(count)개: \(columns)열")
            #expect(rows == minimumRows, "코어 \(count)개: \(rows)줄 (최소 \(minimumRows))")
            // 열을 하나 줄이면 줄이 늘어나야 한다 (한 줄에 다 들어가는 경우는 제외)
            if columns > 1, count > columns {
                #expect((count + columns - 2) / (columns - 1) > rows, "코어 \(count)개: \(columns - 1)열도 \(rows)줄")
            }
        }
    }

    @Test func 링_지름은_폭에_맞추고_최대를_넘지_않는다() {
        #expect(CoreGridLayout.ringDiameter(columns: 8, availableWidth: 256, spacing: 6) == 26)
        #expect(CoreGridLayout.ringDiameter(columns: 7, availableWidth: 256, spacing: 6) == 30)
        #expect(CoreGridLayout.ringDiameter(columns: 4, availableWidth: 256, spacing: 6) == 30)
        #expect(CoreGridLayout.ringDiameter(columns: 32, availableWidth: 100, spacing: 6) == 12)
    }
}
