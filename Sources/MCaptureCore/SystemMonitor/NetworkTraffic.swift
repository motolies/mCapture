import Foundation

public struct NetworkBytes: Sendable, Equatable {
    public var received: UInt64
    public var sent: UInt64
    public init(received: UInt64 = 0, sent: UInt64 = 0) { self.received = received; self.sent = sent }
}

public struct NetworkRate: Sendable, Equatable {
    public var download: Double
    public var upload: Double
    public init(download: Double = 0, upload: Double = 0) { self.download = download; self.upload = upload }
}

/// Only physical, currently active interfaces supplied by the OS reader enter this accumulator.
public struct NetworkAccumulator: Sendable {
    public private(set) var total = NetworkBytes()
    public private(set) var startedAt: Date
    private var previous: [String: NetworkBytes] = [:]
    private var previousTime: TimeInterval?
    public init(now: Date = Date()) { startedAt = now }
    public mutating func resetTotals(now: Date = Date()) { total = NetworkBytes(); startedAt = now }
    public mutating func resetBaseline() { previous = [:]; previousTime = nil }
    public mutating func sample(_ counters: [String: NetworkBytes]?, time: TimeInterval) -> NetworkRate? {
        guard let counters else { resetBaseline(); return nil }
        defer { previous = counters; previousTime = time }
        guard let previousTime, time > previousTime, time - previousTime < 5 else { return nil }
        var delta = NetworkBytes()
        var comparable = counters.isEmpty && previous.isEmpty
        for (name, current) in counters {
            guard let old = previous[name], current.received >= old.received, current.sent >= old.sent else { continue }
            comparable = true
            delta.received += current.received - old.received
            delta.sent += current.sent - old.sent
        }
        guard comparable else { return nil }
        total.received += delta.received; total.sent += delta.sent
        return NetworkRate(download: Double(delta.received) / (time - previousTime), upload: Double(delta.sent) / (time - previousTime))
    }
}

public enum NetworkFormat {
    /// Decimal bytes, shared by the menu bar, chart axis and traffic rows.
    public static func bytes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0 KB" }
        let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
        var amount = value / 1000
        var index = 0
        while amount >= 999.95, index < units.count - 1 { amount /= 1000; index += 1 }
        return String(format: amount < 100 && index > 0 ? "%.1f %@" : "%.0f %@", amount, units[index])
    }
    /// 메뉴바 전용: 초당 바이트를 공백·소수점 없이 최대 세 자리로 표시한다.
    public static func menuRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "–" }
        let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
        var amount = value / 1000
        var index = 0
        while amount.rounded() >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        return String(format: "%.0f%@", min(999, amount), units[index])
    }

    public static func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "–" }
    public static func axis(_ history: [NetworkRate?]) -> Double {
        let maximum = history.compactMap { $0 }.map { max($0.download, $0.upload) }.max() ?? 0
        guard maximum > 1000 else { return 1000 }
        let magnitude = pow(10, floor(log10(maximum)))
        return ceil(maximum / magnitude) * magnitude
    }
}

public struct NetworkProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bytes: NetworkBytes
    public init(pid: Int32, name: String, bytes: NetworkBytes) { self.pid = pid; self.name = name; self.bytes = bytes }
}

public enum NettopParser {
    /// nettop -P -L N -x -J bytes_in,bytes_out. A timestamp header starts each sample.
    public static func parse(_ text: String) -> [[NetworkProcessSample]] {
        var batches: [[NetworkProcessSample]] = []
        var inputIndex: Int?
        var outputIndex: Int?
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = csv(String(line))
            if let incoming = fields.firstIndex(of: "bytes_in"), let outgoing = fields.firstIndex(of: "bytes_out") {
                inputIndex = incoming; outputIndex = outgoing; batches.append([]); continue
            }
            guard let i = inputIndex, let o = outputIndex, fields.count > max(i, o), !batches.isEmpty,
                  let dot = fields[0].lastIndex(of: "."), let pid = Int32(fields[0][fields[0].index(after: dot)...]),
                  let received = UInt64(fields[i]), let sent = UInt64(fields[o]) else { continue }
            batches[batches.count - 1].append(NetworkProcessSample(pid: pid, name: String(fields[0][..<dot]), bytes: NetworkBytes(received: received, sent: sent)))
        }
        return batches
    }
    private static func csv(_ line: String) -> [String] {
        var fields: [String] = []; var field = ""; var quoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" { quoted.toggle() }
            else if character == ",", !quoted { fields.append(field); field = "" }
            else { field.append(character) }
        }
        fields.append(field)
        return fields
    }
}

public struct NetworkAppTraffic: Sendable, Equatable, Identifiable {
    public let path: String
    public let rate: NetworkRate
    public var id: String { path }
    public init(path: String, rate: NetworkRate) { self.path = path; self.rate = rate }
}

public enum NetworkAppRanking {
    public static func rank(previous: [NetworkProcessSample], current: [NetworkProcessSample], interval: Double,
                            paths: [Int32: String]) -> [NetworkAppTraffic] {
        guard interval > 0 else { return [] }
        let old = Dictionary(previous.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        var groups: [String: NetworkRate] = [:]
        for sample in current {
            guard let prior = old[sample.pid], prior.name == sample.name, let path = paths[sample.pid],
                  sample.bytes.received >= prior.bytes.received, sample.bytes.sent >= prior.bytes.sent else { continue }
            let key = ProcessName.groupPath(for: path)
            var rate = groups[key, default: NetworkRate()]
            rate.download += Double(sample.bytes.received - prior.bytes.received) / interval
            rate.upload += Double(sample.bytes.sent - prior.bytes.sent) / interval
            groups[key] = rate
        }
        return groups.map { NetworkAppTraffic(path: $0.key, rate: $0.value) }
            .filter { $0.rate.download + $0.rate.upload > 0 }
            .sorted { a, b in
                let lhs = a.rate.download + a.rate.upload, rhs = b.rate.download + b.rate.upload
                return lhs == rhs ? a.path < b.path : lhs > rhs
            }.prefix(5).map { $0 }
    }
}

public struct PingSummary: Sendable, Equatable {
    public let transmitted: Int
    public let received: Int
    public let average: Double?
    public var lossPercent: Double { transmitted > 0 ? Double(transmitted - received) / Double(transmitted) * 100 : 0 }
    public static func parse(_ output: String) -> PingSummary? {
        let pattern = #"(\d+) packets transmitted, (\d+) (?:packets )?received"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let txRange = Range(match.range(at: 1), in: output), let rxRange = Range(match.range(at: 2), in: output),
              let tx = Int(output[txRange]), let rx = Int(output[rxRange]), tx > 0, rx <= tx else { return nil }
        let average = output.split(whereSeparator: \.isNewline).first { $0.contains("min/avg/max") }
            .flatMap { $0.split(separator: "=").last?.split(separator: "/").dropFirst().first }
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return PingSummary(transmitted: tx, received: rx, average: average)
    }
}

public enum NetworkRateUnit: String, CaseIterable, Sendable {
    case kilobytes = "KB/s"
    case megabytes = "MB/s"

    public var bytesPerSecond: Double { self == .kilobytes ? 1000 : 1_000_000 }
}

public struct NetworkThreshold: Sendable, Equatable {
    public let enabled: Bool
    public let amount: Int
    public let unit: NetworkRateUnit

    public init(enabled: Bool, amount: Int, unit: NetworkRateUnit) {
        self.enabled = enabled
        self.amount = max(1, min(999, amount))
        self.unit = unit
    }

    /// 반올림 전의 다운로드·업로드 중 하나라도 기준 이상일 때 강조한다.
    public func exceeds(_ rate: NetworkRate?) -> Bool {
        guard enabled, let rate else { return false }
        let limit = Double(amount) * unit.bytesPerSecond
        return rate.download >= limit || rate.upload >= limit
    }
}
