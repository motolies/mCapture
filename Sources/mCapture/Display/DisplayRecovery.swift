import AppKit
import MCaptureCore

/// 시스템이 정보를 읽지 못해 저해상도로 붙은 외부 디스플레이를 복구한다 (F36).
/// 디스플레이의 EDID를 작은 단위로 직접 읽어 검증한 뒤 그 연결에 덮어씌운다.
/// 메뉴에서 고르거나, 자동 복구를 켜 두면 화면 구성이 바뀔 때 인식 실패한 연결을 찾아 실행한다.
///
/// 알려진 한계: 일회성 적용이라 케이블을 다시 꽂으면 풀린다 (자동 복구가 그때 다시 적용한다).
/// 확장 블록이 2개 이상인 EDID는 읽지 못한다.
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
    /// 화면 구성이 바뀐 뒤 자동 확인까지 기다리는 시간. 알림이 연달아 오는 것을 하나로 모으고, 시스템이 스스로 인식할 틈을 준다
    private static let settleDelay: Duration = .seconds(2)

    /// 복구가 진행 중이면 true. 한 번에 하나만 실행한다
    private static var isRunning = false
    private static var policy = DisplayAutoRecoveryPolicy()
    private static var pendingCheck: Task<Void, Never>?
    /// 횟수 제한 알림을 이미 띄웠으면 true. 제한이 풀릴 때까지 다시 띄우지 않는다
    private static var limitNotified = false

    /// 메뉴에서 고른 연결을 복구하고 결과를 토스트·로그로 알린다. 읽기는 메인 밖에서 한다
    static func recover(_ connection: ExternalDisplayConnection) {
        guard !isRunning else {
            ToastPanel.show("이미 디스플레이를 복구하는 중입니다", systemImage: "display", tint: .secondary)
            return
        }
        isRunning = true
        // 이 복구가 일으키는 화면 변경으로 자동 복구가 같은 연결을 또 시도하지 않게 한다
        policy.markAttempted(connection.id)
        Task {
            await run(connection, automatic: false)
            isRunning = false
        }
    }

    /// 자동 복구를 켜거나 끈다. 켜면 지금 인식 실패한 연결이 있는지 바로 확인한다
    static func setAutomatic(_ enabled: Bool) {
        Preferences.shared.displayAutoRecovery = enabled
        Log.display.info("자동 복구 \(enabled ? "켬" : "끔", privacy: .public)")
        ToastPanel.show("외부 디스플레이 자동 복구 \(enabled ? "켬" : "끔")", systemImage: "display", tint: .secondary)
        if enabled {
            scheduleAutomaticCheck()
        } else {
            pendingCheck?.cancel()
        }
    }

    /// 화면 구성이 바뀌었을 때(연결·해제·잠자기에서 깨어남) 부른다.
    /// 자동 복구가 켜져 있으면 잠시 뒤 인식 실패한 연결을 찾아 복구한다. 연달아 불리면 마지막 호출만 남는다
    static func scheduleAutomaticCheck() {
        guard Preferences.shared.displayAutoRecovery else { return }
        pendingCheck?.cancel()
        pendingCheck = Task {
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            await recoverUnrecognizedAutomatically()
        }
    }

    // 인식 실패한 연결 가운데 규칙(같은 연결은 한 번, 일정 시간 안의 횟수 제한)이 허락한 것을 차례로 복구한다
    private static func recoverUnrecognizedAutomatically() async {
        // 기다리는 사이에 설정이 꺼졌을 수 있다. 복구 중이면 그 복구가 화면 구성을 바꿔 다시 불린다
        guard Preferences.shared.displayAutoRecovery, !isRunning, let connections = ExternalDisplayConnection.all() else { return }
        let unrecognized = connections.filter { $0.systemEDIDBytes() == nil }
        let decision = policy.evaluate(unrecognized: Set(unrecognized.map(\.id)), now: ProcessInfo.processInfo.systemUptime)
        Log.display.info("자동 복구 확인: 외부 연결 \(connections.count)개, 인식 실패 \(unrecognized.count)개, 시도 \(decision.attempts.count)개")
        notifyLimit(decision.limited)

        let targets = unrecognized.filter { decision.attempts.contains($0.id) }
        guard !targets.isEmpty else { return }
        isRunning = true
        for connection in targets {
            await run(connection, automatic: true)
        }
        isRunning = false
    }

    // 횟수 제한에 걸리면 한 번만 알린다. 제한이 풀리면 다음에 다시 알릴 수 있게 한다
    private static func notifyLimit(_ limited: Bool) {
        guard limited else {
            limitNotified = false
            return
        }
        guard !limitNotified else { return }
        limitNotified = true
        Log.display.error("자동 복구 횟수 제한에 걸려 멈춤")
        ToastPanel.show(
            "자동 복구를 잠시 멈췄습니다 — 메뉴에서 직접 복구할 수 있습니다",
            systemImage: "exclamationmark.triangle.fill", tint: .orange, duration: .seconds(4)
        )
    }

    // 연결 하나를 복구하고 결과를 알린다. 부르는 쪽이 isRunning을 관리한다
    private static func run(_ connection: ExternalDisplayConnection, automatic: Bool) async {
        Log.display.info("복구 시작(\(automatic ? "자동" : "수동", privacy: .public)): \(connection.registryPath, privacy: .public)")
        let progress = automatic ? "인식 실패한 디스플레이를 자동으로 복구하는 중…" : "디스플레이 정보를 다시 읽는 중…"
        ToastPanel.show(progress, systemImage: "display", tint: .secondary, duration: progressDuration)
        let result = await Task.detached(priority: .userInitiated) { readAndApply(connection) }.value
        report(result, automatic: automatic)
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
        // 읽는 데 몇 초 걸리므로 그 사이에 시스템이 스스로 인식했는지 한 번 더 본다
        guard connection.systemEDIDBytes() == nil else { return .failure(.alreadyRecognized) }
        let status = connection.apply(edid)
        return status == KERN_SUCCESS ? .success(edid) : .failure(.applyFailed(status))
    }

    #if DEBUG
    /// 디버그용 상태 (debug/display-status): 하위 메뉴 항목, 자동 복구 설정, 연결마다 직접 읽은 EDID가 시스템이 가진 것과 같은지.
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
        return ["menu": menu, "autoRecovery": Preferences.shared.displayAutoRecovery, "connections": reads]
    }
    #endif

    // 결과를 토스트와 로그로 알린다. 진행 알림이 떠 있으므로 어떤 결과든 알림을 바꿔 준다
    private static func report(_ result: Result<EDID, Failure>, automatic: Bool) {
        let warning = "exclamationmark.triangle.fill"
        switch result {
        case .success(let edid):
            let name = edid.displayName ?? "외부 디스플레이"
            let mode = edid.preferredMode.map { " — \($0.width)×\($0.height) \(Int($0.refreshRate.rounded()))Hz" } ?? ""
            Log.display.info("복구 적용: \(name, privacy: .public)\(mode, privacy: .public)")
            ToastPanel.show("\(name) 정보를 적용했습니다\(mode)", duration: .seconds(3))
        case .failure(.alreadyRecognized):
            Log.display.info("이미 인식된 디스플레이라 복구하지 않음")
            // 자동 복구는 사용자가 고른 것이 아니므로 "이미"라고 하지 않는다
            let message = automatic ? "디스플레이가 정상 인식됐습니다" : "이미 정상 인식된 디스플레이입니다"
            ToastPanel.show(message, systemImage: "display", tint: .secondary)
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
