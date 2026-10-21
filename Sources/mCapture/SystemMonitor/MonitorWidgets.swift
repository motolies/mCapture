import MCaptureCore
import SwiftUI

/// 팝오버 공통 색. 사용자·성능 코어·앱 = 파랑, 시스템·효율 코어·와이어드 = 분홍, 압축 = 노랑, 여유 = 회색
enum MonitorPalette {
    static let user = Color.blue
    static let system = Color.pink
    static let compressed = Color.yellow
    static let free = Color.gray
    static let heading = Color.blue

    /// 압력 단계 색 (활성 상태 보기의 압력 그래프와 같은 의미)
    static func pressure(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

/// 둥근 바탕의 카드
struct MonitorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 카드 제목 줄: 왼쪽 강조색 제목, 오른쪽 값
struct CardHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MonitorPalette.heading)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }
}

/// 링 한 조각 (전체에 대한 비율과 색)
struct RingSegment: Identifiable {
    let fraction: Double
    let color: Color
    var id: Int { Int(color.hashValue) }
}

/// 링 게이지. 조각을 12시부터 시계 방향으로 이어 붙인다. 조각이 하나면 끝을 둥글게
struct RingGauge: View {
    let segments: [RingSegment]
    var lineWidth: CGFloat = 6
    var trackOpacity: Double = 0.12

    init(segments: [RingSegment], lineWidth: CGFloat = 6) {
        self.segments = segments
        self.lineWidth = lineWidth
    }

    /// 값 하나짜리 링
    init(fraction: Double, color: Color, lineWidth: CGFloat = 6) {
        self.init(segments: [RingSegment(fraction: fraction, color: color)], lineWidth: lineWidth)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(trackOpacity), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: start(of: index), to: min(1, start(of: index) + max(0, segment.fraction)))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: segments.count == 1 ? .round : .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // index번째 조각이 시작하는 위치 (0~1)
    private func start(of index: Int) -> Double {
        segments[..<index].reduce(0) { $0 + max(0, $1.fraction) }
    }
}

/// 가운데에 큰 값과 작은 설명을 둔 링 (압력·메모리·GPU)
struct LabeledRing: View {
    let segments: [RingSegment]
    let value: String
    let caption: String
    var diameter: CGFloat = 88
    var lineWidth: CGFloat = 8
    var valueSize: CGFloat = 24

    var body: some View {
        ZStack {
            RingGauge(segments: segments, lineWidth: lineWidth)
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// CPU 기록 막대. 오른쪽이 최신이고, 사용자(파랑) 위에 시스템(분홍)을 쌓는다
struct HistoryBars: View {
    let points: [CPUHistoryPoint]
    let capacity: Int

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(max(1, capacity))
            let barWidth = max(1, (slot * 0.6).rounded())
            for (index, point) in points.enumerated() {
                let x = (size.width - CGFloat(points.count - index) * slot + (slot - barWidth) / 2).rounded()
                let userHeight = size.height * CGFloat(min(100, point.user)) / 100
                let systemHeight = size.height * CGFloat(min(100 - point.user, point.system)) / 100
                context.fill(Path(CGRect(x: x, y: size.height - userHeight, width: barWidth, height: userHeight)),
                             with: .color(MonitorPalette.user))
                context.fill(Path(CGRect(x: x, y: size.height - userHeight - systemHeight, width: barWidth, height: systemHeight)),
                             with: .color(MonitorPalette.system))
            }
        }
        .frame(height: 56)
    }
}

/// 범례 점 + 이름 + 값
struct LegendRow: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// 프로세스 한 줄: 아이콘, 이름, 값
struct ProcessRow: View {
    let entry: ProcessEntry
    let value: String

    var body: some View {
        let identity = ProcessIdentityCache.shared.identity(for: entry)
        HStack(spacing: 8) {
            Image(nsImage: identity.icon)
                .resizable()
                .frame(width: 18, height: 18)
            Text(identity.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// 프로세스 카드. 목록이 아직 없으면 안내 문구
struct ProcessCard: View {
    let entries: [ProcessEntry]
    let value: (ProcessEntry) -> String

    var body: some View {
        MonitorCard {
            CardHeader(title: "프로세스")
            if entries.isEmpty {
                Text("조회 중…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    ProcessRow(entry: entry, value: value(entry))
                }
            }
        }
    }
}

/// 제목과 값만 있는 한 줄 카드 (로드 평균, 가동 시간)
struct ValueCard: View {
    let title: String
    let value: String

    var body: some View {
        MonitorCard {
            CardHeader(title: title, trailing: value)
        }
    }
}
