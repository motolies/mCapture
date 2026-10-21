import Foundation

/// 시스템 모니터 표시 문자열
public enum MonitorFormat {
    /// 바이트를 iStat식으로: 1KB 미만 `0KB`, KB는 정수, MB는 10 미만이면 소수 1자리, GB는 소수 1자리 (1KB = 1024B)
    public static func bytes(_ value: UInt64) -> String {
        let kb = Double(value) / 1024
        if kb < 1024 { return "\(Int(kb.rounded()))KB" }
        let mb = kb / 1024
        if mb < 1024 {
            return mb < 10 ? String(format: "%.1fMB", mb) : "\(Int(mb.rounded()))MB"
        }
        return String(format: "%.1fGB", mb / 1024)
    }

    /// 사용률 `24%` (반올림)
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// 가동 시간: `4일 20시간`, `20시간 5분`, `12분`
    public static func uptime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = total % 86_400 / 3600
        let minutes = total % 3600 / 60
        if days > 0 { return "\(days)일 \(hours)시간" }
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }

    /// 로드 평균 `2.91 2.66 3.18`
    public static func loadAverage(_ values: [Double]) -> String {
        values.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }
}

/// 메뉴바 글자를 빨간색으로 바꾸는 임계값
public struct MonitorThreshold: Sendable, Equatable {
    public var enabled: Bool
    /// 0~100 %
    public var percent: Int

    public init(enabled: Bool, percent: Int) {
        self.enabled = enabled
        self.percent = max(0, min(100, percent))
    }

    /// 값이 임계값 이상이면 true (꺼져 있으면 항상 false)
    public func exceeds(_ value: Double) -> Bool {
        enabled && value >= Double(percent)
    }
}
