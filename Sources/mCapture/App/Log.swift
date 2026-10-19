import MCaptureCore
import os

/// `log stream --predicate 'subsystem == "com.motolies.mcapture"'`로 확인한다 (개발 빌드는 `com.motolies.mcapture.dev`)
enum Log {
    static let app = Logger(subsystem: AppVariant.current.bundleIdentifier, category: "app")
    static let capture = Logger(subsystem: AppVariant.current.bundleIdentifier, category: "capture")
    static let editor = Logger(subsystem: AppVariant.current.bundleIdentifier, category: "editor")
    static let findFile = Logger(subsystem: AppVariant.current.bundleIdentifier, category: "findfile")
}

extension Duration {
    /// 로그용 밀리초 값
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
