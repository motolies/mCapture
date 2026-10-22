import Foundation

// 매직마우스 멀티터치 제스처 PoC. 비공개 MultitouchSupport로 접촉 프레임을 받아 2·3·4 손가락 탭·스와이프를 출력한다
let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
guard let api = MTAPI.load() else { exit(1) }

let devices = DeviceTable.enumerate(api: api)
DeviceTable.show(devices)
let selected = DeviceTable.select(devices, options: options)
guard !selected.isEmpty else {
    Console.error("시작할 장치가 없다. 매직마우스(Family 112)가 표에 없으면 블루투스 연결을 확인하고, 다른 장치를 쓰려면 --all 또는 --device N")
    exit(1)
}

sink.configure(options: options, devices: selected)
for device in selected {
    let registered = api.registerCallback(device.ref, frameCallback)
    let status = api.start(device.ref, 0)
    Console.line("장치 \(device.index) 시작: register=\(registered) start=\(status) running=\(api.isRunning(device.ref))")
}
Console.line(options.summary)
Console.line("두·세·네 손가락으로 탭·스와이프 해 보세요. Ctrl+C로 종료")

// 15초 동안 프레임이 하나도 없으면 권한 쪽을 의심하게 안내한다
DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
    guard sink.frameCount == 0 else { return }
    Console.line("15초 동안 프레임이 없음. 마우스를 만졌는데도 그렇다면 시스템 설정 › 개인정보 보호 및 보안 › 입력 모니터링(또는 손쉬운 사용)에서 이 터미널 앱을 확인")
}

// Ctrl+C: 장치를 멈추고 콜백을 해제한 뒤 밀린 출력을 비우고 끝낸다
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler {
    MainActor.assumeIsolated {
        for device in selected {
            _ = api.stop(device.ref)
            _ = api.unregisterCallback(device.ref, frameCallback)
        }
        sink.drain()
        Console.line("\n종료. 프레임 \(sink.frameCount)개 수신")
        exit(0)
    }
}
interrupt.resume()
dispatchMain()
