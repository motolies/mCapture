import AppKit
import MCaptureCore

/// 시스템이 정보를 읽지 못해 저해상도로 붙은 외부 디스플레이를 복구한다 (F36).
/// 디스플레이의 EDID를 작은 단위로 직접 읽어 검증한 뒤 그 연결에 덮어씌운다.
///
/// 알려진 한계: 일회성 적용이라 케이블을 다시 꽂으면 풀린다. 확장 블록이 2개 이상인 EDID는 읽지 못한다.
/// 비공개 IOKit 함수를 쓰므로 macOS가 바뀌면 동작하지 않을 수 있다 (심볼이 없으면 메뉴에 지원하지 않는다고 표시된다)
@MainActor
enum DisplayRecovery {
    enum Failure: Error, Equatable {
        /// 읽는 사이에 시스템이 디스플레이를 인식함
        case alreadyRecognized
        case unreadable
        case unsupportedExtensionCount(Int)
        case applyFailed(IOReturn)
    }

    /// 읽기가 오래 걸려도 진행 알림이 남아 있도록 넉넉히 잡는다. 결과 알림이 뜨면 바뀐다
    private static let progressDuration: Duration = .seconds(60)
    private static var isRunning = false

    /// 연결 하나를 복구하고 결과를 토스트·로그로 알린다. 읽기는 메인 밖에서 한다
    static func recover(_ connection: ExternalDisplayConnection) {
        guard !isRunning else {
            ToastPanel.show("이미 디스플레이를 복구하는 중입니다", systemImage: "display", tint: .secondary)
            return
        }
        isRunning = true
        Log.display.info("복구 시작: \(connection.registryPath, privacy: .public)")
        ToastPanel.show("디스플레이 정보를 다시 읽는 중…", systemImage: "display", tint: .secondary, duration: progressDuration)
        Task {
            let result = await Task.detached(priority: .userInitiated) { readAndApply(connection) }.value
            isRunning = false
            report(result)
        }
    }

    // 시스템이 아직 인식하지 못한 연결이면 EDID를 읽어 덮어씌운다. 정상 인식된 디스플레이는 건드리지 않는다
    private nonisolated static func readAndApply(_ connection: ExternalDisplayConnection) -> Result<EDID, Failure> {
        guard connection.systemEDIDBytes() == nil else { return .failure(.alreadyRecognized) }
        let edid: EDID
        switch connection.readEDID() {
        case .success(let read): edid = read
        case .failure(.unreadable): return .failure(.unreadable)
        case .failure(.unsupportedExtensionCount(let count)): return .failure(.unsupportedExtensionCount(count))
        }
        let status = connection.apply(edid)
        return status == KERN_SUCCESS ? .success(edid) : .failure(.applyFailed(status))
    }

    #if DEBUG
    /// 디버그용 상태 (debug/display-status): 하위 메뉴 항목과, 연결마다 직접 읽은 EDID가 시스템이 가진 것과 같은지.
    /// 읽기만 하고 적용하지 않으므로 정상 디스플레이에서 읽기 경로를 확인하는 데 쓴다
    static func debugStatus() async -> [String: Any] {
        let menu = DisplayRecoveryMenu.debugItems()
        let connections = ExternalDisplayConnection.all() ?? []
        let reads = await Task.detached(priority: .userInitiated) {
            connections.map { connection -> [String: String] in
                let system = connection.systemEDIDBytes()
                var entry = ["system": system.flatMap { EDID(validating: $0)?.displayName } ?? (system == nil ? "없음" : "이름 없음")]
                switch connection.readEDID() {
                case .success(let edid):
                    entry["direct"] = "\(edid.displayName ?? "이름 없음") \(edid.bytes.count)바이트"
                    entry["match"] = system.map { $0 == edid.bytes ? "일치" : "불일치" } ?? "비교 불가"
                case .failure(let failure):
                    entry["direct"] = "실패: \(failure)"
                }
                return entry
            }
        }.value
        return ["menu": menu, "connections": reads]
    }
    #endif

    // 결과를 토스트와 로그로 알린다
    private static func report(_ result: Result<EDID, Failure>) {
        let warning = "exclamationmark.triangle.fill"
        switch result {
        case .success(let edid):
            let name = edid.displayName ?? "외부 디스플레이"
            let mode = edid.preferredMode.map { " — \($0.width)×\($0.height) \(Int($0.refreshRate.rounded()))Hz" } ?? ""
            Log.display.info("복구 적용: \(name, privacy: .public)\(mode, privacy: .public)")
            ToastPanel.show("\(name) 정보를 적용했습니다\(mode)", duration: .seconds(3))
        case .failure(.alreadyRecognized):
            Log.display.info("이미 인식된 디스플레이라 복구하지 않음")
            ToastPanel.show("이미 정상 인식된 디스플레이입니다", systemImage: "display", tint: .secondary)
        case .failure(.unreadable):
            Log.display.error("EDID를 읽지 못함")
            ToastPanel.show(
                "디스플레이 정보를 읽지 못했습니다 — 케이블을 다시 꽂고 시도하세요",
                systemImage: warning, tint: .orange, duration: .seconds(4)
            )
        case .failure(.unsupportedExtensionCount(let count)):
            Log.display.error("확장 블록 \(count)개인 EDID는 지원하지 않음")
            ToastPanel.show("지원하지 않는 디스플레이 정보 형식입니다 (확장 블록 \(count)개)", systemImage: warning, tint: .orange, duration: .seconds(4))
        case .failure(.applyFailed(let status)):
            let code = String(UInt32(bitPattern: status), radix: 16)
            Log.display.error("EDID 적용 실패: 0x\(code, privacy: .public)")
            ToastPanel.show("디스플레이 정보를 적용하지 못했습니다 (오류 0x\(code))", systemImage: warning, tint: .orange, duration: .seconds(4))
        }
    }
}
