import Foundation

/// 항목들의 실제 디스크 사용량을 더한다 (확인 화면의 "약 2.3GB"). 참고 정보라 예산을 넘으면 그때까지의 값을 돌려준다
public enum FileSizeCalculator {
    public struct Result: Sendable, Equatable {
        public let bytes: Int64
        /// 예산을 넘거나 취소되어 다 세지 못했으면 false (화면에는 "≥"로)
        public let isComplete: Bool
    }

    /// 항목마다 itemBudget개 또는 itemSeconds초까지 센다. 폴더 안 숨김·패키지도 세고 심볼릭 링크는 따라가지 않는다
    public static func size(of paths: [String], itemBudget: Int = 500_000, itemSeconds: Double = 3,
                            isCancelled: () -> Bool = { false }) -> Result {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        var total: Int64 = 0
        var complete = true
        for path in paths {
            if isCancelled() { return Result(bytes: total, isComplete: false) }
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let deadline = ContinuousClock.now + .milliseconds(Int(itemSeconds * 1000))
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                                  errorHandler: { _, _ in true }) else { continue }
            var count = 0
            while let child = enumerator.nextObject() as? URL {
                count += 1
                if count & 1023 == 0, isCancelled() || ContinuousClock.now > deadline {
                    complete = false
                    break
                }
                if count > itemBudget {
                    complete = false
                    break
                }
                total += Int64((try? child.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
            }
        }
        return Result(bytes: total, isComplete: complete && !isCancelled())
    }
}
