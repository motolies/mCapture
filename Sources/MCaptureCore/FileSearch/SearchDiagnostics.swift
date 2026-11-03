import Foundation
import os

/// Opt in with MCAPTURE_SEARCH_DIAGNOSTICS=1. Never log queries or paths.
public enum SearchDiagnostics {
    public static let enabled = ProcessInfo.processInfo.environment["MCAPTURE_SEARCH_DIAGNOSTICS"] == "1"
    private static let logger = Logger(subsystem: "mCapture", category: "search-performance")
    static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
    public static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.info("\(text, privacy: .public)")
    }
}
