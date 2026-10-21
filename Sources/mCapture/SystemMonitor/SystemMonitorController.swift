import AppKit
import Combine
import MCaptureCore
import SwiftUI

/// 메뉴바 CPU·MEM 항목을 설정에 따라 만들고 샘플러 값을 반영하며, 항목을 누르면 상세 팝오버를 띄운다
///
/// 설정 키는 UserDefaults KVO로 지켜봐 설정 창에서 바꾸거나 `defaults write`로 바꿔도 바로 반영된다.
/// 팝오버는 `.transient`지만 이 앱은 상주 앱이라 활성 상태가 아니면 바깥 클릭을 받지 못하므로,
/// 전역 마우스 모니터로 다른 앱을 누를 때도 닫는다
@MainActor
final class SystemMonitorController: NSObject, NSPopoverDelegate {
    private let preferences: Preferences
    let monitor = SystemMonitor()
    private var cpuItem: MonitorStatusItem?
    private var memoryItem: MonitorStatusItem?
    private var subscription: AnyCancellable?
    private var observing = false
    private var popover: NSPopover?
    private var popoverItem: MonitorStatusItem?
    private var outsideClickMonitor: Any?

    private static let observedKeys = [
        Preferences.Key.monitorCPUVisible, Preferences.Key.monitorMemoryVisible,
        Preferences.Key.monitorCPUAlert, Preferences.Key.monitorCPUThreshold,
        Preferences.Key.monitorMemoryAlert, Preferences.Key.monitorMemoryThreshold,
    ]

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    /// 항목을 만들고 샘플링을 시작한다. MEM을 먼저 만들어 왼쪽부터 CPU, MEM 순으로 놓인다
    func start() {
        guard cpuItem == nil else { return }
        let memory = MonitorStatusItem(kind: .memory)
        let cpu = MonitorStatusItem(kind: .cpu)
        memoryItem = memory
        cpuItem = cpu
        for item in [cpu, memory] {
            item.onClick = { [weak self] in self?.itemClicked(item) }
            item.onVisibilityChange = { [weak self] visible in self?.itemVisibilityChanged(item, visible: visible) }
        }
        applyPreferences()
        for key in Self.observedKeys {
            preferences.defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        observing = true
        subscription = monitor.$snapshot.sink { [weak self] snapshot in
            guard let snapshot else { return }
            self?.render(snapshot)
        }
        monitor.start()
    }

    /// 설정(표시 여부·임계값)을 다시 읽어 항목에 반영한다
    func applyPreferences() {
        cpuItem?.isVisible = preferences.monitorCPUVisible
        memoryItem?.isVisible = preferences.monitorMemoryVisible
        if let snapshot = monitor.snapshot { render(snapshot) }
    }

    // 스냅샷 값을 두 항목의 글자·색·툴팁에 반영한다
    private func render(_ snapshot: SystemSnapshot) {
        if let cpu = snapshot.cpu {
            let alert = preferences.monitorCPUThreshold.exceeds(cpu.total)
            let tooltip = "CPU \(MonitorFormat.percent(cpu.total)) · 사용자 \(MonitorFormat.percent(cpu.user)) 시스템 \(MonitorFormat.percent(cpu.system))"
            cpuItem?.update(value: cpu.total, alert: alert, tooltip: tooltip)
        }
        let memory = snapshot.memory
        let alert = preferences.monitorMemoryThreshold.exceeds(memory.pressurePercent)
        let tooltip = "메모리 압력 \(MonitorFormat.percent(memory.pressurePercent)) · 사용 중 \(MonitorFormat.bytes(memory.used)) / \(MonitorFormat.bytes(memory.total))"
        memoryItem?.update(value: memory.pressurePercent, alert: alert, tooltip: tooltip)
    }

    // 항목을 누르면 그 항목의 팝오버를 토글한다. 다른 항목의 팝오버가 열려 있으면 닫고 새로 연다
    private func itemClicked(_ item: MonitorStatusItem) {
        let wasOpen = popoverItem === item
        closePopover()
        if !wasOpen { showPopover(for: item) }
    }

    // 팝오버를 항목 아래에 띄우고 프로세스 조회를 켠다
    private func showPopover(for item: MonitorStatusItem) {
        guard let button = item.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let root: AnyView = switch item.kind {
        case .cpu: AnyView(CPUDetailView(monitor: monitor))
        case .memory: AnyView(MemoryDetailView(monitor: monitor))
        }
        popover.contentViewController = NSHostingController(rootView: root)
        monitor.wantsProcesses = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        item.setHighlighted(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }
        self.popover = popover
        popoverItem = item
    }

    /// 열린 팝오버를 닫는다 (없으면 아무것도 안 함). 상태는 바로 정리해 곧이어 새 팝오버를 열어도 섞이지 않는다
    func closePopover() {
        guard let popover else { return }
        cleanUp()
        popover.performClose(nil)
    }

    /// 팝오버가 스스로 닫히면(바깥 클릭·Esc) 정리한다. 닫기 애니메이션 뒤에 오므로 지금 열린 팝오버일 때만
    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        cleanUp()
    }

    // 전역 마우스 모니터·강조·프로세스 조회를 정리한다
    private func cleanUp() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        popoverItem?.setHighlighted(false)
        popoverItem = nil
        popover = nil
        monitor.wantsProcesses = false
    }

    // 사용자가 메뉴바에서 끌어내면 설정도 꺼서 다음 실행 때 다시 나타나지 않게 한다
    private func itemVisibilityChanged(_ item: MonitorStatusItem, visible: Bool) {
        switch item.kind {
        case .cpu where preferences.monitorCPUVisible != visible:
            preferences.monitorCPUVisible = visible
        case .memory where preferences.monitorMemoryVisible != visible:
            preferences.monitorMemoryVisible = visible
        default:
            break
        }
    }

    // UserDefaults KVO. 바뀐 스레드와 무관하게 메인에서 반영한다
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in self?.applyPreferences() }
    }

    #if DEBUG
    /// 팝오버를 열고(이미 열려 있으면 닫고) path가 있으면 1.5초 뒤 내용을 PNG로 쓴다 (mcapture-dev://debug/monitor-show?kind=&path=)
    func debugShow(kind: MonitorStatusItem.Kind, snapshotTo url: URL?) {
        guard let item = kind == .cpu ? cpuItem : memoryItem else { return }
        itemClicked(item)
        guard let url else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let view = self?.popover?.contentViewController?.view else { return }
            DebugSnapshot.render(view: view, to: url)
        }
    }

    /// 최신 스냅샷과 항목 상태를 JSON으로 쓴다 (mcapture-dev://debug/monitor-stats?path=). 먼저 설정을 다시 읽는다
    func debugWriteStats(to url: URL) {
        applyPreferences()
        var result: [String: Any] = [
            "efficiencyCores": SystemStatsReader.efficiencyCores,
            "historyCount": monitor.history.count,
            "items": [
                "cpu": itemState(cpuItem, threshold: preferences.monitorCPUThreshold),
                "memory": itemState(memoryItem, threshold: preferences.monitorMemoryThreshold),
            ],
        ]
        if let snapshot = monitor.snapshot {
            if let cpu = snapshot.cpu {
                result["cpu"] = [
                    "total": cpu.total, "user": cpu.user, "system": cpu.system, "cores": cpu.cores,
                    "efficiencyAverage": cpu.efficiencyAverage ?? -1, "performanceAverage": cpu.performanceAverage,
                ]
            }
            let memory = snapshot.memory
            result["memory"] = [
                "total": memory.total, "app": memory.app, "wired": memory.wired, "compressed": memory.compressed,
                "free": memory.free, "usedPercent": memory.usedPercent, "pressurePercent": memory.pressurePercent,
                "pressureLevel": "\(memory.pressureLevel)", "swapTotal": memory.swap.total, "swapUsed": memory.swap.used,
                "pageinsPerSecond": snapshot.pageActivity.pageinsPerSecond, "pageoutsPerSecond": snapshot.pageActivity.pageoutsPerSecond,
            ]
            result["processesCPU"] = monitor.topCPU.map { ["name": $0.name, "path": $0.path, "cpu": $0.cpuPercent, "count": $0.processCount] }
            result["processesMemory"] = monitor.topMemory.map { ["name": $0.name, "path": $0.path, "footprint": Int64($0.footprint), "count": $0.processCount] }
            result["temperature"] = snapshot.temperature ?? -1
            result["gpuTemperature"] = snapshot.gpuTemperature ?? -1
            result["temperatureKeys"] = monitor.temperatureKeys.cpu.map(\.key)
            result["gpuTemperatureKeys"] = monitor.temperatureKeys.gpu.map(\.key)
            result["loadAverage"] = snapshot.loadAverage
            result["uptimeSeconds"] = snapshot.uptime ?? -1
            if let gpu = snapshot.gpu {
                result["gpu"] = ["utilization": gpu.utilization, "memoryInUse": gpu.memoryInUse.map { Int64($0) } ?? -1,
                                 "memoryAllocated": gpu.memoryAllocated.map { Int64($0) } ?? -1,
                                 "memoryPercent": gpu.memoryPercent(of: snapshot.memory.total) ?? -1]
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            Log.monitor.info("모니터 상태: \(url.path, privacy: .public)")
        }
    }

    /// 메뉴바 글자 이미지(평소·임계값 초과)를 메뉴바색 바탕에 2배로 그려 PNG로 쓴다 (mcapture-dev://debug/monitor-stats?image=)
    func debugWriteItemImages(to url: URL) {
        let images = [
            MonitorStatusItem.image(label: "CPU", value: "24%", alert: false),
            MonitorStatusItem.image(label: "MEM", value: "100%", alert: false),
            MonitorStatusItem.image(label: "CPU", value: "87%", alert: true),
            MonitorStatusItem.image(label: "MEM", value: "–", alert: false),
        ]
        let scale: CGFloat = 2
        let width = MonitorStatusItem.Metrics.width * CGFloat(images.count) + 8
        let size = NSSize(width: width, height: MonitorStatusItem.Metrics.height)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: 0.85, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, image) in images.enumerated() {
            image.draw(at: NSPoint(x: 4 + MonitorStatusItem.Metrics.width * CGFloat(index), y: 0), from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// SMC 온도 키 전부를 JSON으로 쓴다 (mcapture-dev://debug/monitor-smc?path=). 칩별 CPU 키를 고를 때 본다
    func debugWriteSMC(to url: URL) {
        Task.detached {
            let sensors = SMCTemperature.readAllTemperatures()
            let list = (sensors ?? []).map { ["key": $0.key, "type": $0.type, "value": $0.value] }
            let result: [String: Any] = ["connected": sensors != nil, "sensors": list]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
            }
        }
    }

    private func itemState(_ item: MonitorStatusItem?, threshold: MonitorThreshold) -> [String: Any] {
        ["visible": item?.isVisible ?? false, "value": item?.value ?? -1, "alert": item?.alert ?? false,
         "thresholdEnabled": threshold.enabled, "threshold": threshold.percent]
    }
    #endif
}
