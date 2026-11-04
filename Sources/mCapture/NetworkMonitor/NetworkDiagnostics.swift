import Foundation
import Darwin
import MCaptureCore

struct NetworkCommandResult: Sendable {
    let output: String
    let status: Int32
    let timedOut: Bool
}

/// Bounded subprocesses, drained off the main actor. Cancellation always reaps the child and closes pipes.
enum NetworkCommand {
    @concurrent
    static func run(_ executable: String, _ arguments: [String], timeout: Double, interruptOnTimeout: Bool = false) async throws -> NetworkCommandResult {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        try process.run()
        try? pipe.fileHandleForWriting.close()
        let reader = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }
        let start = ProcessInfo.processInfo.systemUptime
        var timedOut = false
        while process.isRunning {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime - start >= timeout {
                timedOut = !Task.isCancelled
                if timedOut && interruptOnTimeout { process.interrupt() } else { process.terminate() }
                let deadline = ProcessInfo.processInfo.systemUptime + 0.2
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        process.waitUntilExit()
        let data = await reader.value
        try Task.checkCancellation()
        return NetworkCommandResult(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus, timedOut: timedOut)
    }
}

enum PublicIPState: Sendable, Equatable {
    case loading, value(String), noRoute, failed
    var text: String {
        switch self {
        case .loading: "조회 중…"
        case .value(let value): value
        case .noRoute: "IPv6 경로 없음"
        case .failed: "조회 실패"
        }
    }
}

/// Success-only, in-memory cache. Invalidation generation prevents old requests repopulating it.
actor PublicIPClient {
    private struct Entry { let address: String; let time: Date }
    private var cache: [Bool: Entry] = [:]
    private var generation = 0
    private let session: URLSession
    private let endpoints: [Bool: URL]
    init(session: URLSession = .shared, ipv4URL: URL = URL(string: "https://api.ipify.org?format=json")!,
         ipv6URL: URL = URL(string: "https://api6.ipify.org?format=json")!) {
        self.session = session; endpoints = [false: ipv4URL, true: ipv6URL]
    }
    func invalidate() { generation += 1; cache = [:] }
    func lookup(ipv6: Bool, hasRoute: Bool = true, now: Date = Date()) async throws -> PublicIPState {
        guard !ipv6 || hasRoute else { return .noRoute }
        if let entry = cache[ipv6], now.timeIntervalSince(entry.time) < 300 { return .value(entry.address) }
        let epoch = generation
        var request = URLRequest(url: endpoints[ipv6]!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard epoch == generation else { throw CancellationError() }
            struct Response: Decodable { let ip: String }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try? JSONDecoder().decode(Response.self, from: data), Self.valid(body.ip, ipv6: ipv6) else { return .failed }
            cache[ipv6] = Entry(address: body.ip, time: now)
            return .value(body.ip)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return .failed
        }
    }
    private static func valid(_ address: String, ipv6: Bool) -> Bool {
        var storage = in6_addr()
        return address.withCString { inet_pton(ipv6 ? AF_INET6 : AF_INET, $0, &storage) } == 1
    }
}

struct NetworkPing: Sendable {
    let target: String
    let summary: PingSummary?
    let measuredAt: Date
    let failed: Bool
    var text: String {
        guard let summary else { return failed ? "측정 실패" : "응답 없음 — ICMP 차단 가능" }
        guard summary.received > 0, let average = summary.average else { return "응답 없음 — ICMP 차단 가능 (응답 손실 100%)" }
        return String(format: "평균 %.1f ms · 응답 손실 %.0f%%", average, summary.lossPercent)
    }
    static func measure(_ target: String) async throws -> NetworkPing {
        let ipv6 = target.contains(":")
        let result = try await NetworkCommand.run(ipv6 ? "/sbin/ping6" : "/sbin/ping",
                                                   ["-n", "-c", "5", "-i", "1", target], timeout: 7, interruptOnTimeout: true)
        let summary = PingSummary.parse(result.output)
        return NetworkPing(target: target, summary: summary, measuredAt: Date(), failed: summary == nil && !result.timedOut && result.status != 0)
    }
}
