import MCaptureCore
import SwiftUI

/// 설정 창의 "시스템 모니터" 탭. 값은 @AppStorage로 바로 저장되고 SystemMonitorController가 KVO로 반영한다
struct SystemMonitorSettingsView: View {
    @AppStorage(Preferences.Key.monitorCPUVisible) private var cpuVisible = true
    @AppStorage(Preferences.Key.monitorMemoryVisible) private var memoryVisible = true
    @AppStorage(Preferences.Key.monitorCPUAlert) private var cpuAlert = true
    @AppStorage(Preferences.Key.monitorCPUThreshold) private var cpuThreshold = Preferences.Default.monitorCPUThreshold
    @AppStorage(Preferences.Key.monitorMemoryAlert) private var memoryAlert = true
    @AppStorage(Preferences.Key.monitorMemoryThreshold) private var memoryThreshold = Preferences.Default.monitorMemoryThreshold

    @AppStorage(Preferences.Key.monitorNetworkVisible) private var networkVisible = true

    @AppStorage(Preferences.Key.monitorNetworkPerSecond) private var networkPerSecond = false
    @AppStorage(Preferences.Key.monitorNetworkAlert) private var networkAlert = false
    @AppStorage(Preferences.Key.monitorNetworkThreshold) private var networkThreshold = Preferences.Default.monitorNetworkThreshold
    @AppStorage(Preferences.Key.monitorNetworkThresholdUnit) private var networkUnit = NetworkRateUnit.megabytes.rawValue

    var body: some View {
        Form {
            Section("CPU") {
                Toggle("메뉴바에 표시", isOn: $cpuVisible)
                    .accessibilityLabel("CPU 메뉴바에 표시")
                ThresholdRow(title: "사용률 기준", accessibilityTitle: "CPU 사용률 기준",
                             enabled: $cpuAlert, threshold: $cpuThreshold)
                    .disabled(!cpuVisible)
            }

            Section("메모리(RAM)") {
                Toggle("메뉴바에 표시", isOn: $memoryVisible)
                    .accessibilityLabel("메모리 메뉴바에 표시")
                ThresholdRow(title: "메모리 압력 기준", accessibilityTitle: "메모리 압력 기준",
                             enabled: $memoryAlert, threshold: $memoryThreshold)
                    .disabled(!memoryVisible)
                Text("메모리 압력은 RAM 사용률과 다른 지표입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("메뉴바에 표시", isOn: $networkVisible)
                    .accessibilityLabel("네트워크 메뉴바에 표시")
                Toggle("속도 단위에 /s 표시", isOn: $networkPerSecond)
                    .disabled(!networkVisible)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("기준 이상일 때 빨간색으로 강조", isOn: $networkAlert)
                        .accessibilityLabel("네트워크 기준 이상일 때 빨간색으로 강조")
                    HStack(spacing: 8) {
                        Text("속도 기준")
                            .fixedSize()
                        Text("1~999")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: 12)
                        TextField("네트워크 속도 기준", value: $networkThreshold, format: .number.grouping(.never))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 64)
                            .onChange(of: networkThreshold) { _, value in
                                networkThreshold = max(1, min(999, value))
                            }
                        Picker("네트워크 속도 기준 단위", selection: $networkUnit) {
                            ForEach(NetworkRateUnit.allCases, id: \.rawValue) { unit in
                                Text(unit.rawValue).tag(unit.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 88)
                    }.disabled(!networkAlert)
                }
                .disabled(!networkVisible)
                Text("다운로드 또는 업로드가 기준 이상이면 강조합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("네트워크")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("1초마다 갱신합니다.")
                        Image(systemName: "info.circle")
                            .help(Self.measurementHelp)
                            .accessibilityLabel("측정 정보")
                            .accessibilityHint(Self.measurementHelp)
                    }
                    Text("메뉴바 항목을 누르면 상세 정보를 볼 수 있습니다. ⌘를 누른 채 끌어 위치를 옮기거나 메뉴바 밖으로 빼서 숨길 수 있습니다.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
    }

    private static let measurementHelp = "메모리 압력은 시스템 전체 여유 비율(kern.memorystatus_level)의 반대값입니다. 프로세스 목록은 상세 정보가 열려 있는 동안만 조회하며, 메모리 목록에는 내 계정의 프로세스만 보입니다."
}

/// 임계값 한 줄: 사용 토글과 10~100% 슬라이더(5 단위), 값 라벨
private struct ThresholdRow: View {
    let title: String
    let accessibilityTitle: String
    @Binding var enabled: Bool
    @Binding var threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("기준 이상일 때 빨간색으로 강조", isOn: $enabled)
                .accessibilityLabel("\(accessibilityTitle) 이상일 때 빨간색으로 강조")
            HStack {
                Text(title).fixedSize()
                Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Int($0.rounded()) }), in: 10...100, step: 5)
                    .accessibilityLabel(accessibilityTitle)
                    .accessibilityValue("\(threshold)%")
                Text("\(threshold)%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(!enabled)
        }
    }
}
