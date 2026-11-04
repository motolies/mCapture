import AppKit
import Combine
import CoreLocation
import SystemConfiguration
import MCaptureCore

@MainActor
final class NetworkMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var rate: NetworkRate?
    @Published private(set) var history: [NetworkRate?] = []
    @Published private(set) var total = NetworkBytes()
    @Published private(set) var startedAt = Date()
    @Published private(set) var connections = NetworkConnections()
    @Published private(set) var apps: [NetworkAppTraffic] = []
    @Published private(set) var appState = "조회 중…"
    @Published private(set) var publicIPv4 = PublicIPState.loading
    @Published private(set) var publicIPv6 = PublicIPState.loading
    @Published private(set) var gatewayPing: NetworkPing?
    @Published private(set) var internetPing: NetworkPing?
    @Published var selectedTab = 0
    @Published private(set) var locationDenied = false
    private(set) var detailsActive = false
    private var accumulator = NetworkAccumulator()
    private var sampleTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var appTask: Task<Void, Never>?
    private var diagnosisTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var store: SCDynamicStore?
    private var generation = 0
    private var connectionGeneration = 0
    private var diagnosisGeneration = 0
    private let ipClient = PublicIPClient()
    private let location = CLLocationManager()
    #if DEBUG
    private(set) var synthetic = false
    #endif

    override init() {
        super.init()
        location.delegate = self
    }
    func start() {
        guard sampleTask == nil else { return }
        accumulator.resetBaseline()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                let counters = await Self.readCounters()
                guard !Task.isCancelled else { return }
                self?.sample(counters)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.connectionChanged() }
        }
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "mCapture NET observer" as CFString, { _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(context).takeUnretainedValue()
            // The store is scheduled on the main queue; do not carry an unretained pointer across a task.
            MainActor.assumeIsolated { monitor.connectionChanged() }
        }, &context)
        if let store {
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/(IPv4|IPv6|DNS)", "State:/Network/Interface/.*/(IPv4|IPv6|Link)"] as CFArray)
            SCDynamicStoreSetDispatchQueue(store, .main)
        }
        refreshConnections()
    }
    func stop() {
        setDetailsActive(false)
        sampleTask?.cancel(); sampleTask = nil
        connectionTask?.cancel(); connectionTask = nil; connectionGeneration += 1
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil
        accumulator.resetBaseline()
    }
    private func sample(_ counters: [String: NetworkBytes]?) {
        #if DEBUG
        guard !synthetic else { return }
        #endif
        rate = accumulator.sample(counters, time: ProcessInfo.processInfo.systemUptime)
        history.append(rate)
        if history.count > 60 { history.removeFirst(history.count - 60) }
        total = accumulator.total; startedAt = accumulator.startedAt
    }
    func resetTotals() {
        accumulator.resetTotals(); total = accumulator.total; startedAt = accumulator.startedAt
    }
    func setDetailsActive(_ active: Bool) {
        guard active != detailsActive else { return }
        detailsActive = active; generation += 1
        appTask?.cancel(); appTask = nil
        diagnosisTask?.cancel(); diagnosisTask = nil; diagnosisGeneration += 1
        connectionTask?.cancel(); connectionTask = nil; connectionGeneration += 1
        guard active else { return }
        #if DEBUG
        guard !synthetic else { return }
        #endif
        apps = []; appState = "조회 중…"
        refreshConnections()
        startApps()
        restartDiagnostics()
    }
    private func connectionChanged() {
        #if DEBUG
        guard !synthetic else { return }
        #endif
        generation += 1
        appTask?.cancel(); appTask = nil
        diagnosisTask?.cancel(); diagnosisTask = nil; diagnosisGeneration += 1
        if detailsActive { apps = []; appState = "조회 중…"; startApps() }
        accumulator.resetBaseline()
        rate = nil; history.append(nil)
        if history.count > 60 { history.removeFirst(history.count - 60) }
        refreshConnections(invalidate: true)
    }
    private func refreshConnections(invalidate: Bool = false) {
        #if DEBUG
        guard !synthetic else { return }
        #endif
        connectionTask?.cancel(); connectionGeneration += 1
        let epoch = connectionGeneration
        connectionTask = Task { [weak self] in
            let result = await Self.readConnections()
            guard !Task.isCancelled, let self, epoch == self.connectionGeneration else { return }
            let changed = result.signature != self.connections.signature
            self.connections = result
            if changed || invalidate {
                await self.ipClient.invalidate()
                guard !Task.isCancelled, epoch == self.connectionGeneration else { return }
                if self.detailsActive { self.restartDiagnostics() }
            }
            guard self.detailsActive else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            self.refreshConnections()
        }
    }
    private func startApps() {
        let epoch = generation
        appTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let before = await Self.readIdentities()
                    let begin = ProcessInfo.processInfo.systemUptime
                    let output = try await NetworkCommand.run("/usr/bin/nettop", ["-P", "-L", "2", "-s", "2", "-x", "-n", "-J", "bytes_in,bytes_out"], timeout: 5)
                    let elapsed = ProcessInfo.processInfo.systemUptime - begin
                    let after = await Self.readIdentities()
                    try Task.checkCancellation()
                    guard let self, epoch == self.generation else { return }
                    let batches = NettopParser.parse(output.output)
                    guard output.status == 0, !output.timedOut, batches.count >= 2 else {
                        self.apps = []; self.appState = "조회 실패"
                        try await Task.sleep(for: .seconds(2)); continue
                    }
                    let paths = before.filter { after[$0.key] == $0.value }.mapValues(\.path)
                    self.apps = NetworkAppRanking.rank(previous: batches[batches.count - 2], current: batches[batches.count - 1], interval: elapsed, paths: paths)
                    self.appState = self.apps.isEmpty ? "현재 전송 없음" : ""
                } catch {
                    if Task.isCancelled { return }
                    guard let self, epoch == self.generation else { return }
                    self.apps = []; self.appState = "조회 실패"
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
        }
    }
    func remeasure() {
        guard detailsActive else { return }
        restartDiagnostics(force: true)
    }
    private func restartDiagnostics(force: Bool = false) {
        diagnosisTask?.cancel(); diagnosisGeneration += 1
        guard detailsActive else { return }
        publicIPv4 = .loading; publicIPv6 = .loading; gatewayPing = nil; internetPing = nil
        let epoch = diagnosisGeneration
        let connection = connections
        diagnosisTask = Task { [weak self, ipClient] in
            if force { await ipClient.invalidate() }
            do {
                while !Task.isCancelled {
                    let began = ContinuousClock.now
                    async let v4 = ipClient.lookup(ipv6: false)
                    async let v6 = ipClient.lookup(ipv6: true, hasRoute: connection.primary6 != nil)
                    async let gateway = Self.ping(connection.gateway)
                    async let internet = Self.ping(connection.ipv6Only ? "2606:4700:4700::1111" : "1.1.1.1")
                    let result = try await (v4, v6, gateway, internet)
                    guard !Task.isCancelled, let self, epoch == self.diagnosisGeneration else { return }
                    self.publicIPv4 = result.0; self.publicIPv6 = result.1
                    self.gatewayPing = result.2; self.internetPing = result.3
                    try await Task.sleep(until: began.advanced(by: .seconds(10)), clock: .continuous)
                }
            } catch { /* Cancellation never marks the entire connection offline. */ }
        }
    }
    private static func ping(_ target: String?) async throws -> NetworkPing? {
        guard let target else { return nil }
        do { return try await NetworkPing.measure(target) }
        catch {
            try Task.checkCancellation()
            return NetworkPing(target: target, summary: nil, measuredAt: Date(), failed: true)
        }
    }
    var wifiPermissionRequired: Bool {
        location.authorizationStatus != .authorizedAlways
    }
    func requestWiFiPermission() {
        if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        } else { location.requestWhenInUseAuthorization() }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.locationDenied = self.location.authorizationStatus == .denied || self.location.authorizationStatus == .restricted
            if self.sampleTask != nil { self.refreshConnections() }
        }
    }
    @concurrent private static func readCounters() async -> [String: NetworkBytes]? { NetworkSystemReader.counters() }
    @concurrent private static func readConnections() async -> NetworkConnections { NetworkSystemReader.connections() }
    @concurrent private static func readIdentities() async -> [Int32: NetworkSystemReader.ProcessIdentity] { NetworkSystemReader.processIdentities() }

    #if DEBUG
    func useSyntheticSample() {
        setDetailsActive(false); synthetic = true
        connectionTask?.cancel(); connectionTask = nil; connectionGeneration += 1
        history = (0..<60).map { (index: Int) -> NetworkRate? in
            if index == 30 { return nil }
            let download = Double(index % 13) * 1_300_000.0
            let upload = Double(index % 7) * 220_000.0
            return NetworkRate(download: download, upload: upload)
        }
        rate = NetworkRate(download: 12_300_000, upload: 640_000)
        total = NetworkBytes(received: 3_456_000_000, sent: 640_000_000)
        connections = NetworkConnections(connections: [NetworkConnection(id: "en0", kind: "Wi-Fi", addresses: ["192.0.2.10", "2001:db8:1234:5678:abcd:ef01:2345:6789"], isDefault: true,
            wifi: WiFiDetails(ssid: "긴 Wi-Fi 이름 · Network Monitor Preview", rssi: -54, transmitRate: 1200, channel: 149, band: "5 GHz"))], gateway4: "192.0.2.1", primary4: "en0", dns: ["1.1.1.1"])
        apps = [NetworkAppTraffic(path: "/Applications/Safari.app", rate: rate!)]; appState = ""
        publicIPv4 = .value("198.51.100.20"); publicIPv6 = .value("2001:db8::1234")
        gatewayPing = NetworkPing(target: "192.0.2.1", summary: PingSummary.parse("5 packets transmitted, 5 packets received\nround-trip min/avg/max/stddev = 1/2/3/1 ms"), measuredAt: Date(), failed: false)
        internetPing = NetworkPing(target: "1.1.1.1", summary: PingSummary.parse("5 packets transmitted, 0 packets received"), measuredAt: Date(), failed: false)
    }
    #endif
}
