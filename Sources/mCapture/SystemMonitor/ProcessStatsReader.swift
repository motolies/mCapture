import AppKit
import Darwin
import MCaptureCore
import UniformTypeIdentifiers

/// 프로세스 목록 읽기. 팝오버가 열려 있는 동안만 2초마다 부른다
///
/// CPU는 `/bin/ps`(엔타이틀먼트로 전 프로세스를 읽음, 약 20ms), 메모리는 `proc_pid_rusage`의 phys_footprint다.
/// 다른 사용자의 프로세스(kernel_task·WindowServer·root 데몬)는 공개 API가 EPERM을 주므로 메모리 목록에서 빠진다
enum ProcessStatsReader {
    /// CPU 샘플 (`ps -Aro pid=,pcpu=,comm=`). 실패하면 빈 배열
    static func readCPUSamples() -> [ProcessSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aro", "pid=,pcpu=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.monitor.error("ps 실행 실패: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessListParser.parsePS(String(decoding: data, as: UTF8.self))
    }

    /// 메모리 footprint 샘플. 읽지 못한 프로세스(다른 사용자, 끝난 프로세스)는 건너뛴다
    static func readMemorySamples() -> [ProcessSample] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.size + 64)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var samples: [ProcessSample] = []
        // PROC_PIDPATHINFO_MAXSIZE(4 × MAXPATHLEN)는 매크로라 Swift로 들어오지 않는다
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids[..<(Int(filled) / MemoryLayout<pid_t>.size)] where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard result == 0, info.ri_phys_footprint > 0 else { continue }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = length > 0 ? String(cString: pathBuffer) : "pid \(pid)"
            samples.append(ProcessSample(pid: pid, path: path, footprint: info.ri_phys_footprint))
        }
        return samples
    }
}

/// 프로세스 항목의 아이콘과 현지화된 이름 (경로별 캐시)
@MainActor
final class ProcessIdentityCache {
    static let shared = ProcessIdentityCache()

    struct Identity {
        let name: String
        let icon: NSImage
    }

    private var cache: [String: Identity] = [:]
    private lazy var executableIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    /// `.app` 번들은 Finder가 보이는 이름(현지화)과 앱 아이콘, 실행 파일은 파일 이름과 실행 파일 아이콘
    /// Finder가 "모든 파일 확장자 보기"면 displayName에 `.app`이 붙어 오므로 떼어 낸다
    func identity(for entry: ProcessEntry) -> Identity {
        if let cached = cache[entry.path] { return cached }
        let identity: Identity
        if entry.path.hasPrefix("/"), FileManager.default.fileExists(atPath: entry.path) {
            var name = entry.path.hasSuffix(".app") ? FileManager.default.displayName(atPath: entry.path) : entry.name
            if name.hasSuffix(".app") { name.removeLast(4) }
            identity = Identity(name: name, icon: NSWorkspace.shared.icon(forFile: entry.path))
        } else {
            identity = Identity(name: entry.name, icon: executableIcon)
        }
        cache[entry.path] = identity
        return identity
    }
}
