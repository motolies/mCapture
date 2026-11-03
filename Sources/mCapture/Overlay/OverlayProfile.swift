import AppKit

/// Per-overlay CPU/request telemetry. Neither request nor draw completion measures scanout.
@MainActor
final class OverlayProfile {
    #if DEBUG
    private let enabled = ProcessInfo.processInfo.environment["MCAPTURE_OVERLAY_PROFILE"] == "1"
    private var samples: [String: [Double]] = [:]
    #endif

    func start() -> TimeInterval {
        #if DEBUG
        return enabled ? ProcessInfo.processInfo.systemUptime : 0
        #else
        return 0
        #endif
    }

    func end(_ metric: String, since start: TimeInterval) {
        #if DEBUG
        guard enabled, start > 0 else { return }
        record(metric + ".ms", (ProcessInfo.processInfo.systemUptime - start) * 1000)
        #endif
    }

    func record(_ metric: String, _ value: Double) {
        #if DEBUG
        guard enabled else { return }
        samples[metric, default: []].append(value)
        #endif
    }

    func drawing(_ view: NSView) {
        #if DEBUG
        guard enabled else { return }
        var rects: UnsafePointer<NSRect>?
        var count = 0
        view.getRectsBeingDrawn(&rects, count: &count)
        record("draw.rectCount", Double(count))
        if let rects {
            let area = (0..<count).reduce(CGFloat.zero) {
                let rect = rects[$1].intersection(view.bounds)
                return $0 + (rect.isNull ? 0 : rect.width * rect.height)
            }
            record("draw.area.pt2", Double(area))
        }
        #endif
    }

    func report(context: String) {
        #if DEBUG
        guard enabled else { return }
        var lines = ["OverlayProfile \(context)", "CPU/request timing only; not presentation latency."]
        for key in samples.keys.sorted() {
            let values = samples[key]!.sorted()
            let p95 = values[Int(ceil(Double(values.count) * 0.95)) - 1]
            let middle = values.count / 2
            let median = values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
            lines.append(String(format: "%@: n=%d median=%.3f p95=%.3f max=%.3f", key, values.count, median, p95, values.last!))
        }
        let message = lines.joined(separator: "\n")
        Log.capture.info("\(message, privacy: .public)")
        fputs(message + "\n", stderr)
        samples.removeAll()
        #endif
    }
}
