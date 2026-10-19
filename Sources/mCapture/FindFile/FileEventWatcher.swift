import CoreServices
import Foundation

/// FSEvents 이벤트 하나 (경로·플래그·ID를 값으로 복사한 것)
struct FileEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
    let id: FSEventStreamEventId

    func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }
}

/// FSEvents C API를 감싸 이벤트 묶음을 AsyncStream으로 넘긴다
/// 콜백은 전용 큐에서 순서대로 불리고, 받는 쪽은 Task 하나가 순서대로 처리한다
final class FileEventWatcher: @unchecked Sendable {
    // FSEvents 콜백이 info 포인터로 돌려받는 객체라 Sendable 검사를 할 수 없다. 만든 뒤 바뀌는 값은 stream뿐이고 stop에서만 바꾼다
    let events: AsyncStream<[FileEvent]>
    private let continuation: AsyncStream<[FileEvent]>.Continuation
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "FindFile.events", qos: .utility)

    /// since 이후의 기록부터 감시를 시작한다. 제외 경로는 앞의 8개만 쓴다(FSEvents 제한)
    init?(paths: [String], since: FSEventStreamEventId, exclusions: [String], latency: TimeInterval = 1.0) {
        (events, continuation) = AsyncStream<[FileEvent]>.makeStream()
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf)
        guard let stream = FSEventStreamCreate(nil, Self.callback, &context, paths as CFArray, since, latency, flags) else {
            return nil
        }
        if !exclusions.isEmpty {
            FSEventStreamSetExclusionPaths(stream, Array(exclusions.prefix(8)) as CFArray)
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        stop()
    }

    /// 감시를 멈추고 스트림을 끝낸다
    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        // 큐에서 실행 중인 콜백이 끝날 때까지 기다린 뒤 해제한다 (콜백이 self를 참조하지 않고 넘겨받는다)
        queue.sync {}
        FSEventStreamRelease(stream)
        continuation.finish()
    }

    /// 지금까지 시스템에서 발생한 마지막 이벤트 ID (전체 스캔 직전에 기록해 두고 그 뒤부터 재생한다)
    static var currentEventId: FSEventStreamEventId {
        FSEventsGetCurrentEventId()
    }

    /// 경로가 있는 볼륨의 FSEvents 장치 UUID. 이벤트 DB가 초기화되면 바뀌어 저장한 이벤트 ID를 쓸 수 없다
    static func deviceUUID(for path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    // C 콜백: 경로·플래그·ID를 값 배열로 복사해 스트림에 넣는다
    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }
        let watcher = Unmanaged<FileEventWatcher>.fromOpaque(info).takeUnretainedValue()
        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        var events: [FileEvent] = []
        events.reserveCapacity(count)
        for i in 0..<count {
            guard let path = pathArray[i] as? String else { continue }
            events.append(FileEvent(path: path, flags: flags[i], id: ids[i]))
        }
        watcher.continuation.yield(events)
    }
}
