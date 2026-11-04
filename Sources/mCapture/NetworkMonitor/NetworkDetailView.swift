import AppKit
import SwiftUI
import MCaptureCore

struct NetworkDetailView: View {
    @ObservedObject var monitor: NetworkMonitor
    var availableHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                speed("다운로드", value: monitor.rate?.download, color: .blue, arrow: "↓")
                Spacer()
                speed("업로드", value: monitor.rate?.upload, color: .pink, arrow: "↑")
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(NetworkFormat.rate(NetworkFormat.axis(monitor.history))).font(.caption2).foregroundStyle(.secondary)
                NetworkChart(history: monitor.history).frame(height: 65)
                HStack {
                    Text("60초 전"); Spacer(); Text("현재")
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Picker("네트워크 상세", selection: $monitor.selectedTab) {
                Text("트래픽").tag(0); Text("연결").tag(1); Text("진단").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch monitor.selectedTab {
                    case 1: connections
                    case 2: diagnostics
                    default: traffic
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: 360, height: min(600, max(300, availableHeight - 60)))
    }
    private func speed(_ label: String, value: Double?, color: Color, arrow: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(arrow) \(label)").font(.caption).foregroundStyle(color)
            Text(NetworkFormat.rate(value)).font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
    }
    private var traffic: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("상위 앱 5개").font(.headline)
            if !monitor.appState.isEmpty { Text(monitor.appState).foregroundStyle(.secondary) }
            ForEach(monitor.apps) { app in
                let entry = ProcessEntry(path: app.path, name: ProcessName.displayName(forPath: app.path), cpuPercent: 0, footprint: 0, processCount: 1)
                let identity = ProcessIdentityCache.shared.identity(for: entry)
                HStack(spacing: 8) {
                    Image(nsImage: identity.icon).resizable().frame(width: 22, height: 22)
                    Text(identity.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↓ " + NetworkFormat.rate(app.rate.download)).foregroundStyle(.blue)
                        Text("↑ " + NetworkFormat.rate(app.rate.upload)).foregroundStyle(.pink)
                    }.font(.caption).monospacedDigit()
                }
            }
            Text("앱별 값은 TCP/UDP 기준입니다. LAN을 포함한 물리 연결 합계와 다를 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("앱 실행 이후 누적").font(.headline)
                Spacer()
                Button("초기화") { monitor.resetTotals() }.controlSize(.small)
            }
            row("다운로드", NetworkFormat.bytes(Double(monitor.total.received)))
            row("업로드", NetworkFormat.bytes(Double(monitor.total.sent)))
            Text("집계 시작 " + monitor.startedAt.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if monitor.connections.connections.isEmpty { Text("활성 연결 없음").foregroundStyle(.secondary) }
            ForEach(monitor.connections.connections) { connection in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("\(connection.kind) · \(connection.id)").font(.headline)
                        Spacer()
                        if connection.isDefault { Text("기본 연결").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(connection.addresses, id: \.self) { address in
                        row(address.contains(":") ? "IPv6" : "IPv4", address)
                    }
                    if let wifi = connection.wifi {
                        row("SSID", wifi.ssid ?? "권한 필요 또는 확인 불가")
                        if wifi.ssid == nil && monitor.wifiPermissionRequired {
                            Button(monitor.locationDenied ? "Wi-Fi 정보 허용 (설정)" : "Wi-Fi 정보 허용") { monitor.requestWiFiPermission() }
                                .controlSize(.small)
                        }
                        row("신호 세기", wifi.rssi == 0 ? "–" : "\(wifi.rssi) dBm")
                        row("송신 링크 속도", wifi.transmitRate > 0 ? String(format: "%.0f Mbps", wifi.transmitRate) : "–")
                        row("채널 / 대역", wifi.channel > 0 ? "\(wifi.channel) · \(wifi.band)" : "–")
                        Text("링크 속도는 실제 전송 속도가 아닙니다.").font(.caption2).foregroundStyle(.secondary)
                    }
                    if connection.kind == "VPN 터널" {
                        Text("터널 존재가 모든 통신의 VPN 사용을 뜻하지는 않습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            row("IPv4 게이트웨이", monitor.connections.gateway4 ?? "–")
            row("IPv6 게이트웨이", monitor.connections.gateway6 ?? "–")
            row("시스템 DNS", monitor.connections.dns.isEmpty ? "–" : monitor.connections.dns.joined(separator: "\n"))
        }
    }
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("연결 진단").font(.headline); Spacer()
                Button("다시 측정") { monitor.remeasure() }.controlSize(.small)
            }
            ipRow("공인 IPv4", monitor.publicIPv4)
            ipRow("공인 IPv6", monitor.publicIPv6)
            Divider()
            ping("기본 게이트웨이", result: monitor.gatewayPing, fallback: monitor.connections.gateway)
            ping("인터넷 진단 대상", result: monitor.internetPing,
                 fallback: monitor.connections.ipv6Only ? "2606:4700:4700::1111" : "1.1.1.1")
            Text("공인 IP: ipify · 인터넷 ICMP: Cloudflare\n10초마다 최대 5회 요청합니다. ICMP 응답 손실은 실제 데이터 패킷 손실이나 인터넷 전체 장애를 뜻하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func ipRow(_ title: String, _ state: PublicIPState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary); Spacer()
                if case .value(let address) = state {
                    Button("복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string) }
                        .controlSize(.mini)
                }
            }
            Text(state.text).textSelection(.enabled).font(.system(.body, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func ping(_ title: String, result: NetworkPing?, fallback: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(result?.target ?? fallback ?? "기본 경로 없음").font(.caption).textSelection(.enabled)
            Text(result?.text ?? (fallback == nil ? "–" : "측정 중…")).font(.callout)
            if let result { Text(result.measuredAt.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.font(.caption)
    }
}

private struct NetworkChart: View {
    let history: [NetworkRate?]
    var body: some View {
        Canvas { context, size in
            let axis = NetworkFormat.axis(history)
            for (key, color) in [(\NetworkRate.download, Color.blue), (\NetworkRate.upload, Color.pink)] {
                var path = Path(); var continuous = false
                for (index, value) in history.enumerated() {
                    guard let value else { continuous = false; continue }
                    let point = CGPoint(x: Double(index + 60 - history.count) / 59 * size.width,
                                        y: size.height - min(1, value[keyPath: key] / axis) * (size.height - 2) - 1)
                    if continuous { path.addLine(to: point) } else { path.move(to: point) }
                    continuous = true
                }
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
        }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("최근 60초 다운로드 파랑, 업로드 분홍. 최대 " + NetworkFormat.rate(NetworkFormat.axis(history)))
    }
}
