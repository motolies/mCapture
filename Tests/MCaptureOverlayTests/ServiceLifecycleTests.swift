import AppKit
import Testing
@testable import mCapture

@Suite(.serialized) @MainActor
struct ServiceLifecycleTests {
    @Test func gestureStopRemovesObserversAndAllowsRestart() async throws {
        let name = "mCapture-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        defaults.set(false, forKey: Preferences.Key.gestureEnabled)
        var service: GestureService? = GestureService(preferences: preferences)
        weak let weakService = service
        service?.start()
        service?.stop()
        service?.stop()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(service?.state == .off)
        service?.start()
        #expect(service?.state == .off)
        service?.stop()
        service = nil
        await Task.yield()
        #expect(weakService == nil)
    }

    @Test func monitorStopReleasesItemsAndCanRestart() async throws {
        _ = NSApplication.shared
        let name = "mCapture-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        defaults.set(false, forKey: Preferences.Key.monitorCPUVisible)
        defaults.set(false, forKey: Preferences.Key.monitorMemoryVisible)
        var controller: SystemMonitorController? = SystemMonitorController(preferences: preferences)
        weak let weakController = controller
        controller?.start()
        controller?.stop()
        controller?.stop()
        #expect(controller?.monitor.wantsProcesses == false)
        controller?.start()
        controller?.stop()
        controller = nil
        await Task.yield()
        #expect(weakController == nil)
        var item: MonitorStatusItem? = MonitorStatusItem(kind: .cpu)
        weak let weakItem = item
        item?.update(value: 50, alert: false)
        #expect(item?.button?.toolTip == nil)
        item?.stop()
        item = nil
        #expect(weakItem == nil)
    }
}
