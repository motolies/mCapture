import AppKit
import SwiftUI
import Testing
import MCaptureCore
@testable import mCapture

struct NetworkDiagnosticsTests {
    @Test func commandTimeoutAndCancellation() async throws {
        let start = ContinuousClock.now
        let result = try await NetworkCommand.run("/bin/sh", ["-c", "echo $$; exec /bin/sleep 10"], timeout: 0.1)
        #expect(result.timedOut)
        let pid = try #require(Int32(result.output.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1)
        #expect(start.duration(to: .now) < .seconds(2))
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("network-child-\(UUID()).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let task = Task {
            try await NetworkCommand.run("/bin/sh", ["-c", "echo $$ > \"$1\"; exec /bin/sleep 10", "network-test", pidFile.path], timeout: 7)
        }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled process returned success") }
        catch { #expect(error is CancellationError) }
        let child = try #require(Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(child, 0) == -1)

    }

    @Test func nativeNettopAndLoopbackPing() async throws {
        let output = try await NetworkCommand.run("/usr/bin/nettop", ["-P", "-L", "2", "-s", "2", "-x", "-n", "-J", "bytes_in,bytes_out"], timeout: 5)
        #expect(output.status == 0)
        #expect(NettopParser.parse(output.output).count == 2)
        let ping = try await NetworkPing.measure("127.0.0.1")
        #expect(ping.summary?.received == 5)
        #expect(ping.summary?.lossPercent == 0)
    }

    @Test func commandDrainsLargeOutputAndReportsExit() async throws {
        let result = try await NetworkCommand.run("/usr/bin/seq", ["1", "50000"], timeout: 3)
        #expect(result.status == 0); #expect(!result.timedOut)
        #expect(result.output.hasSuffix("50000\n"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MCAPTURE_IPIFY_SIMULATION"] != nil))
    func ipifyAgainstLocalSimulation() async throws {
        // Opt-in integration: run the checked-in Postman simulation, then set this URL.
        guard let base = ProcessInfo.processInfo.environment["MCAPTURE_IPIFY_SIMULATION"] else { return }
        func endpoint(_ path: String) -> URL { URL(string: base + "/" + path + "?format=json")! }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = PublicIPClient(session: session, ipv4URL: endpoint("v4"), ipv6URL: endpoint("v6"))
        let now = Date()
        #expect(try await client.lookup(ipv6: false, now: now) == .value("198.51.100.42"))
        #expect(try await client.lookup(ipv6: true, now: now) == .value("2001:db8::42"))
        #expect(try await client.lookup(ipv6: true, hasRoute: false) == .noRoute)
        let caching = PublicIPClient(session: session, ipv4URL: endpoint("cache"))
        let first = try await caching.lookup(ipv6: false, now: now)
        #expect(try await caching.lookup(ipv6: false, now: now.addingTimeInterval(299)) == first)
        let expired = try await caching.lookup(ipv6: false, now: now.addingTimeInterval(301))
        #expect(expired != first)
        await caching.invalidate()
        #expect(try await caching.lookup(ipv6: false, now: now.addingTimeInterval(302)) != expired)
        for path in ["invalid", "malformed", "error", "v6"] {
            let invalid = PublicIPClient(ipv4URL: endpoint(path))
            #expect(try await invalid.lookup(ipv6: false) == .failed)
        }
        let delayed = PublicIPClient(ipv4URL: endpoint("delayed"))
        let oldConnection = Task { try await delayed.lookup(ipv6: false) }
        try await Task.sleep(for: .milliseconds(100))
        await delayed.invalidate()
        do { _ = try await oldConnection.value; Issue.record("Previous connection result survived invalidation") }
        catch { #expect(error is CancellationError) }
        #expect(try await delayed.lookup(ipv6: false) == .value("198.51.100.43"))
        let slow = PublicIPClient(ipv4URL: endpoint("slow"))
        let began = ContinuousClock.now
        #expect(try await slow.lookup(ipv6: false) == .failed)
        #expect(began.duration(to: .now) >= .seconds(4))
        #expect(began.duration(to: .now) < .seconds(6))
        let pending = Task { try await slow.lookup(ipv6: false) }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        do { _ = try await pending.value; Issue.record("Cancelled HTTP request returned success") }
        catch { #expect(error is CancellationError) }
    }

    @Test func localCountersExcludeTunnels() throws {
        let physical = NetworkSystemReader.physicalInterfaces()
        #expect(!physical.keys.contains { $0.hasPrefix("utun") || $0.hasPrefix("awdl") || $0.hasPrefix("bridge") || $0 == "lo0" })
        let counters = try #require(NetworkSystemReader.counters())
        #expect(Set(counters.keys).isSubset(of: Set(physical.keys)))
    }
}

@Suite(.serialized) @MainActor
struct NetworkMonitorUITests {
    @Test func lifecycleAndResetPreserveHistoryAndSelection() async throws {
        var monitor: NetworkMonitor? = NetworkMonitor()
        weak let weakMonitor = monitor
        monitor?.useSyntheticSample()
        let history = monitor?.history
        monitor?.selectedTab = 2
        for _ in 0..<5 { monitor?.start(); monitor?.setDetailsActive(true); monitor?.setDetailsActive(false); monitor?.stop() }
        #expect(monitor?.detailsActive == false)
        #expect(monitor?.selectedTab == 2)
        monitor?.resetTotals()
        #expect(monitor?.total == NetworkBytes())
        #expect(monitor?.history == history)
        monitor = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(weakMonitor == nil)
    }

    @Test func controllerSwitchAndHideStopNetworkDetails() throws {
        _ = NSApplication.shared
        let name = "network-controller-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let controller = SystemMonitorController(preferences: preferences)
        controller.start()
        defer { controller.stop() }
        controller.debugShow(kind: .network, snapshotTo: nil, synthetic: true)
        #expect(controller.networkMonitor.detailsActive)
        #expect(!controller.monitor.wantsProcesses)
        controller.debugShow(kind: .cpu, snapshotTo: nil)
        #expect(!controller.networkMonitor.detailsActive)
        #expect(controller.monitor.wantsProcesses)
        controller.debugShow(kind: .network, snapshotTo: nil, synthetic: true)
        preferences.monitorNetworkVisible = false
        controller.applyPreferences()
        #expect(!controller.networkMonitor.detailsActive)
        #expect(!controller.monitor.wantsProcesses)
    }

    @Test func networkStatusItemAndPreference() throws {
        _ = NSApplication.shared
        let name = "network-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.monitorNetworkVisible)
        #expect(!preferences.monitorNetworkPerSecond)
        #expect(!preferences.monitorNetworkThreshold.enabled)
        defaults.set(true, forKey: Preferences.Key.monitorNetworkPerSecond)
        defaults.set(true, forKey: Preferences.Key.monitorNetworkAlert)
        defaults.set(640, forKey: Preferences.Key.monitorNetworkThreshold)
        defaults.set("KB/s", forKey: Preferences.Key.monitorNetworkThresholdUnit)
        #expect(preferences.monitorNetworkPerSecond)
        #expect(preferences.monitorNetworkThreshold.exceeds(NetworkRate(upload: 640_000)))
        preferences.monitorNetworkVisible = false
        #expect(!preferences.monitorNetworkVisible)
        let item = MonitorStatusItem(kind: .network)
        defer { item.stop() }
        item.updateNetwork(NetworkRate(download: 12_300_000, upload: 640_000))
        #expect(item.button?.image?.size == NSSize(width: MonitorStatusItem.Metrics.networkWidth, height: 22))
        #expect(item.button?.toolTip == nil)
        #expect(item.button?.accessibilityLabel()?.contains("다운로드 12.3 MB/s") == true)
        #expect(item.button?.image?.isTemplate == true)
        item.updateNetwork(NetworkRate(download: 12_300_000, upload: 640_000), perSecond: true, alert: true)
        #expect(item.button?.image?.size.width == MonitorStatusItem.Metrics.networkPerSecondWidth)
        #expect(item.button?.image?.isTemplate == false)
        #expect(item.alert)
        item.updateNetwork(NetworkRate(download: 12_300_000, upload: 640_000), perSecond: true, alert: false)
        #expect(item.button?.image?.isTemplate == true)
        item.updateNetwork(nil, perSecond: false)
        #expect(item.button?.image?.size.width == MonitorStatusItem.Metrics.networkWidth)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MCAPTURE_NETWORK_SNAPSHOTS"] != nil))
    func renderSyntheticTabs() async throws {
        guard let folder = ProcessInfo.processInfo.environment["MCAPTURE_NETWORK_SNAPSHOTS"] else { return }
        _ = NSApplication.shared
        let monitor = NetworkMonitor(); monitor.useSyntheticSample()
        for dark in [false, true] {
            for tab in 0...2 {
                monitor.selectedTab = tab
                let host = NSHostingView(rootView: NetworkDetailView(monitor: monitor))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host; window.orderFront(nil)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                DebugSnapshot.render(view: host, to: URL(fileURLWithPath: "\(folder)/network-\(dark ? "dark" : "light")-\(tab).png"))
                window.orderOut(nil)
            }
        }
    }
}
