import os

/// `log stream --predicate 'subsystem == "com.motolies.mcapture"'`로 확인한다
enum Log {
    static let app = Logger(subsystem: "com.motolies.mcapture", category: "app")
    static let capture = Logger(subsystem: "com.motolies.mcapture", category: "capture")
    static let editor = Logger(subsystem: "com.motolies.mcapture", category: "editor")
}

extension Duration {
    /// 로그용 밀리초 값
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
