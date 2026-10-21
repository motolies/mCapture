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

    var body: some View {
        Form {
            Section("메뉴바") {
                Toggle("CPU 사용률 표시", isOn: $cpuVisible)
                Toggle("메모리 압력 표시", isOn: $memoryVisible)
                Text("항목을 누르면 상세 정보가 뜹니다. ⌘를 누른 채 끌어 자리를 옮기거나 메뉴바 밖으로 빼서 숨길 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("임계값") {
                ThresholdRow(title: "CPU 사용률", enabled: $cpuAlert, threshold: $cpuThreshold)
                ThresholdRow(title: "메모리 압력", enabled: $memoryAlert, threshold: $memoryThreshold)
                Text("임계값 이상이면 그 항목의 메뉴바 글자가 빨간색이 됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("정보") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1초마다 갱신합니다. 메모리 압력은 시스템 전체 여유 비율(kern.memorystatus_level)의 반대값입니다.")
                    Text("프로세스 목록은 상세 정보가 열려 있는 동안만 조회하며, 메모리 목록에는 내 계정의 프로세스만 보입니다.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTab.contentWidth)
    }
}

/// 임계값 한 줄: 사용 토글과 10~100% 슬라이더(5 단위), 값 라벨
private struct ThresholdRow: View {
    let title: String
    @Binding var enabled: Bool
    @Binding var threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            HStack {
                Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Int($0.rounded()) }), in: 10...100, step: 5)
                Text("\(threshold)%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(!enabled)
        }
    }
}
