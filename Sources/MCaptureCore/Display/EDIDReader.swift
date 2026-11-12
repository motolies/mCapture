import Foundation

/// 디스플레이에서 EDID를 읽어 오는 절차.
///
/// 일부 변환 어댑터는 16바이트를 한꺼번에 요청하면 엉뚱한 위치의 조각을 돌려준다
/// (실측: 조각 내용은 온전하고 순서만 뒤섞이며, 읽을 때마다 순서가 달라진다).
/// 시스템은 16바이트 단위로 읽어 매번 실패하므로, 여기서는 작은 단위로 위치를 지정해 읽고
/// 검증을 통과한 결과가 두 번 똑같이 나올 때만 믿는다
public enum EDIDReader {
    /// offset부터 length바이트를 읽는다. 읽지 못하면 nil
    public typealias Source = (_ offset: Int, _ length: Int) -> [UInt8]?

    public enum Failure: Error, Equatable, Sendable {
        /// 검증을 통과한 같은 결과를 두 번 얻지 못함
        case unreadable
        /// 확장 블록이 읽을 수 있는 범위보다 많음 (확장 블록 수)
        case unsupportedExtensionCount(Int)
    }

    /// 위치를 1바이트로 지정하므로 256바이트(기본 블록 + 확장 블록 1개)까지만 읽을 수 있다
    public static let maxExtensionCount = 1
    /// 시도마다 쓸 읽기 단위(바이트). 실측에서 8바이트가 빠르고 안정적이었다. 1바이트는 느리지만 다른 경로라 사이에 섞는다
    public static let defaultChunkPlan = [8, 8, 8, 8, 1, 8, 8, 8, 1, 8, 8, 8]

    /// chunkPlan 순서대로 읽기를 시도해, 검증을 통과한 결과가 두 번 똑같이 나오면 그 결과를 돌려준다.
    /// 체크섬은 조각 순서가 바뀌어도 통과할 수 있어 한 번의 통과만으로는 믿지 않는다.
    /// pause는 시도 사이에 불린다 (장치가 다음 요청을 받을 틈을 준다)
    public static func readTrusted(
        from source: Source,
        chunkPlan: [Int] = defaultChunkPlan,
        pause: () -> Void = {}
    ) -> Result<EDID, Failure> {
        var candidates: [EDID] = []
        var unsupportedCount: Int?
        for (attempt, chunk) in chunkPlan.enumerated() {
            if attempt > 0 { pause() }
            switch readOnce(from: source, chunk: chunk) {
            case .success(let edid):
                if candidates.contains(edid) { return .success(edid) }
                candidates.append(edid)
            case .failure(.unsupportedExtensionCount(let count)):
                // 기본 블록은 검증을 통과한 상태다. 같은 값이 두 번 나오면 실제로 읽을 수 없는 형식이다
                if unsupportedCount == count { return .failure(.unsupportedExtensionCount(count)) }
                unsupportedCount = count
            case .failure(.unreadable):
                continue
            }
        }
        return .failure(.unreadable)
    }

    /// EDID 전체를 chunk 바이트 단위로 한 번 읽어 검증한다.
    /// 기본 블록이 검증을 통과해야 확장 블록을 읽는다 (실패한 시도를 빨리 끝낸다)
    static func readOnce(from source: Source, chunk: Int) -> Result<EDID, Failure> {
        guard let base = read(source, from: 0, count: EDID.blockSize, chunk: chunk),
              let extensions = EDID.extensionCount(ofBaseBlock: base)
        else { return .failure(.unreadable) }
        guard extensions <= maxExtensionCount else { return .failure(.unsupportedExtensionCount(extensions)) }
        guard let rest = read(source, from: EDID.blockSize, count: extensions * EDID.blockSize, chunk: chunk),
              let edid = EDID(validating: base + rest)
        else { return .failure(.unreadable) }
        return .success(edid)
    }

    /// start부터 count바이트를 chunk 단위로, 매번 위치를 지정해 읽는다. 한 번이라도 실패하면 nil
    private static func read(_ source: Source, from start: Int, count: Int, chunk: Int) -> [UInt8]? {
        let step = max(1, chunk)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        var offset = start
        while offset < start + count {
            let length = min(step, start + count - offset)
            guard let part = source(offset, length), part.count == length else { return nil }
            bytes += part
            offset += length
        }
        return bytes
    }
}
