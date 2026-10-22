import Foundation
import Testing
import os
@testable import MCaptureCore

// MARK: - 도우미

/// 합성 프레임 생성기. 매직마우스 표면 기준, 손가락은 가로로 벌려 놓고 88Hz(11.3ms)로 프레임을 만든다
enum FrameBuilder {
    static let surface = SurfaceSize.magicMouse2
    static let interval = 0.0113

    /// 접촉 하나. z 0.5는 보통 세기
    static func contact(_ path: Int32, state: Int32, x: Float, y: Float, z: Float = 0.5, time: Double = 0) -> TouchContact {
        TouchContact(timestamp: time, pathIndex: path, state: state, x: x, y: y, zTotal: z)
    }

    /// i번째 손가락의 시작 위치 (가장자리·손바닥 영역을 피한다)
    static func origin(_ i: Int) -> (x: Float, y: Float) { (0.3 + 0.15 * Float(i), 0.6) }

    /// 매직마우스 기본 프로필의 인식기
    static func mouseRecognizer() -> TouchGestureRecognizer {
        TouchGestureRecognizer(profile: .default(for: .magicMouse, surface: surface)!)
    }

    /// n손가락이 start에 닿아(MakeTouch) duration 동안 (dxMM, dyMM)만큼 일정하게 움직인 뒤 다음 프레임에서 모두 떨어지는 프레임 열.
    /// gap 구간의 프레임은 빼서 블루투스 공백을 흉내 낸다. initialState 4는 시작 전부터 닿아 있던 손가락이다
    static func gesture(
        fingers: Int, dxMM: Double = 0, dyMM: Double = 0, duration: Double, start: Double = 1.0,
        gap: ClosedRange<Double>? = nil, initialState: Int32 = 3
    ) -> [TouchFrame] {
        let steps = Int((duration / interval).rounded(.up))
        var frames: [TouchFrame] = []
        for step in 0...steps {
            let offset = min(Double(step) * interval, duration)
            let time = start + offset
            if let gap, gap.contains(time) { continue }
            let progress = duration > 0 ? offset / duration : 1
            let dx = Float(dxMM / surface.widthMM * progress)
            let dy = Float(dyMM / surface.heightMM * progress)
            let contacts = (0..<fingers).map { i in
                contact(Int32(i), state: step == 0 ? initialState : 4, x: origin(i).x + dx, y: origin(i).y + dy, time: time)
            }
            frames.append(TouchFrame(timestamp: time, contacts: contacts))
        }
        frames.append(TouchFrame(timestamp: start + duration + interval, contacts: []))
        return frames
    }

    /// 프레임 열을 인식기에 차례로 넣고 나온 이벤트를 모은다
    static func run(_ frames: [TouchFrame], recognizer: inout TouchGestureRecognizer) -> [RecognizedGesture] {
        var events: [RecognizedGesture] = []
        for frame in frames { events += recognizer.process(frame) }
        return events
    }

    /// 실측 로그 조각을 인식기에 흘려 넣는다. 버튼 줄은 누름만 buttonDown으로 넘긴다 (CLI와 같은 순서)
    static func replay(_ fixture: String, recognizer: inout TouchGestureRecognizer) -> [RecognizedGesture] {
        var events: [RecognizedGesture] = []
        for line in fixture.split(separator: "\n") {
            guard let entry = TouchFrameLog.parse(String(line)) else { continue }
            switch entry {
            case .frame(let frame, _):
                events += recognizer.process(frame)
            case .button(let button, let down, let time, _):
                if down { events += recognizer.buttonDown(button, at: time) }
            }
        }
        return events
    }
}

// MARK: - 인식기 (합성 프레임)

@Suite("TouchGestureRecognizer 합성 프레임")
struct TouchGestureRecognizerSyntheticTests {
    @Test func 두_손가락_탭() throws {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(FrameBuilder.gesture(fingers: 2, duration: 0.2), recognizer: &recognizer)
        try #require(events.count == 1)
        #expect(events[0].gesture == .tap(fingers: 2))
        #expect(abs(events[0].metrics.duration - 0.2) < 0.001)
        #expect(!recognizer.isTracking)
    }

    @Test func 스와이프_방향은_우세_축의_부호로_정한다() {
        func swipe(dx: Double, dy: Double) -> RecognizedGesture? {
            var recognizer = FrameBuilder.mouseRecognizer()
            return FrameBuilder.run(FrameBuilder.gesture(fingers: 3, dxMM: dx, dyMM: dy, duration: 0.2), recognizer: &recognizer).first
        }
        #expect(swipe(dx: -10, dy: 0)?.gesture == .swipe(fingers: 3, direction: .left))
        #expect(swipe(dx: 10, dy: 0)?.gesture == .swipe(fingers: 3, direction: .right))
        // +y가 손끝 쪽(앞)이다. 2026-10-22 매직마우스 실측
        #expect(swipe(dx: 0, dy: 15)?.gesture == .swipe(fingers: 3, direction: .up))
        #expect(swipe(dx: 0, dy: -15)?.gesture == .swipe(fingers: 3, direction: .down))
        let left = swipe(dx: -10, dy: 0)
        #expect(left.map { $0.metrics.dxMM < -9.5 && abs($0.metrics.dyMM) < 0.1 } == true)
    }

    @Test func 탭_범위에서_오래_누르면_길게_탭() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(FrameBuilder.gesture(fingers: 3, duration: 0.6), recognizer: &recognizer)
        #expect(events.map(\.gesture) == [.longPress(fingers: 3)])
    }

    @Test func 탭과_스와이프_사이의_이동은_미분류() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(FrameBuilder.gesture(fingers: 2, dxMM: 4.5, duration: 0.2), recognizer: &recognizer)
        #expect(events.map(\.gesture) == [.move(fingers: 2)])
    }

    @Test func 한_손가락은_이벤트를_내지_않는다() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(FrameBuilder.gesture(fingers: 1, dxMM: 20, duration: 0.3), recognizer: &recognizer)
        #expect(events.isEmpty)
    }

    @Test func 시작_때_이미_닿아_있던_손가락은_묶지_않는다() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(FrameBuilder.gesture(fingers: 3, duration: 0.2, initialState: 4), recognizer: &recognizer)
        #expect(events.isEmpty)
    }

    @Test func 블루투스_공백_뒤에도_같은_손가락이면_가짜_탭이_없다() throws {
        // 3손가락을 500ms 누르는 동안 1.10~1.40초 프레임이 통째로 빠진다 (실측 최대 공백 370ms)
        var recognizer = FrameBuilder.mouseRecognizer()
        let frames = FrameBuilder.gesture(fingers: 3, duration: 0.5, gap: 1.1...1.4)
        let events = FrameBuilder.run(frames, recognizer: &recognizer)
        try #require(events.count == 1)
        #expect(events[0].gesture == .longPress(fingers: 3))
        #expect(abs(events[0].metrics.duration - 0.5) < 0.001)
    }

    @Test func 늦게_닿은_손가락도_묶음이_가만히_있으면_같은_제스처() {
        // 3손가락이 1.0초에 닿고 넷째(p3)가 181ms 뒤 닿은 뒤 1.35초에 모두 떨어진다 (groupWindow 150ms 밖, lateJoinWindow 300ms 안)
        var frames: [TouchFrame] = (0..<31).map { step in
            let time = 1.0 + Double(step) * FrameBuilder.interval
            var contacts = (0..<3).map { i in
                FrameBuilder.contact(Int32(i), state: step == 0 ? 3 : 4, x: FrameBuilder.origin(i).x, y: FrameBuilder.origin(i).y, time: time)
            }
            if step >= 16 {
                contacts.append(FrameBuilder.contact(3, state: step == 16 ? 3 : 4, x: FrameBuilder.origin(3).x, y: FrameBuilder.origin(3).y, time: time))
            }
            return TouchFrame(timestamp: time, contacts: contacts)
        }
        frames.append(TouchFrame(timestamp: 1.35, contacts: []))
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(frames, recognizer: &recognizer)
        #expect(events.map(\.gesture) == [.tap(fingers: 4)])
    }

    @Test func 클릭은_닿은_손가락_수와_버튼을_주고_묶음을_닫는다() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let frames = FrameBuilder.gesture(fingers: 3, duration: 0.1)
        _ = FrameBuilder.run(Array(frames.dropLast()), recognizer: &recognizer)
        #expect(recognizer.buttonDown(.left, at: 1.1).map(\.gesture) == [.click(fingers: 3, button: .left)])
        // 150ms 안의 두 번째 알림은 같은 클릭 (MT 콜백 뒤 이벤트 탭)
        #expect(recognizer.buttonDown(.left, at: 1.12).isEmpty)
        #expect(recognizer.buttonDown(.right, at: 1.3).map(\.gesture) == [.click(fingers: 3, button: .right)])
        // 클릭한 손가락이 떨어져도 탭으로 다시 분류되지 않는다
        #expect(FrameBuilder.run([frames.last!], recognizer: &recognizer).isEmpty)
    }

    @Test func flush는_세대가_같을_때만_상태를_비운다() {
        var recognizer = FrameBuilder.mouseRecognizer()
        _ = FrameBuilder.run(Array(FrameBuilder.gesture(fingers: 2, duration: 0.1).dropLast()), recognizer: &recognizer)
        #expect(recognizer.isTracking)
        #expect(recognizer.flush(ifGeneration: recognizer.generation - 1).isEmpty)
        #expect(recognizer.isTracking)
        #expect(recognizer.flush(ifGeneration: recognizer.generation).isEmpty)
        #expect(!recognizer.isTracking)
    }

    @Test func 오래_누른_묶음은_쉬는_손가락으로_버린다() {
        // 2손가락을 1.7초 동안 누르고 있다가 뗀다 (프레임은 100ms 간격)
        var frames: [TouchFrame] = (0...17).map { step in
            let time = 1.0 + Double(step) * 0.1
            let contacts = (0..<2).map { i in
                FrameBuilder.contact(Int32(i), state: step == 0 ? 3 : 4, x: FrameBuilder.origin(i).x, y: FrameBuilder.origin(i).y, time: time)
            }
            return TouchFrame(timestamp: time, contacts: contacts)
        }
        frames.append(TouchFrame(timestamp: 2.8, contacts: []))
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.run(frames, recognizer: &recognizer)
        #expect(events.map(\.gesture) == [.hold(fingers: 2)])
    }

    @Test func 가장자리의_약한_호버_접촉만_접촉으로_센다() {
        let profile = TouchGestureRecognizer.Profile.default(for: .magicMouse, surface: FrameBuilder.surface)!
        let edgeHover = FrameBuilder.contact(10, state: 2, x: 0.009, y: 0.64, z: 0.12)
        let centerHover = FrameBuilder.contact(11, state: 2, x: 0.5, y: 0.64, z: 0.5)
        let touching = FrameBuilder.contact(1, state: 4, x: 0.4, y: 0.7)
        let filtered = TouchGestureRecognizer.filter([edgeHover, centerHover, touching], profile: profile)
        #expect(filtered.countedPaths == [10, 1])
        #expect(filtered.dropped.isEmpty)
    }

    @Test func 큰_접촉이_있으면_손바닥으로_보고_프레임을_무시한다() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let palm = TouchFrame(timestamp: 1, contacts: [
            FrameBuilder.contact(0, state: 3, x: 0.5, y: 0.5, z: 6.0),
            FrameBuilder.contact(1, state: 3, x: 0.6, y: 0.5),
        ])
        #expect(recognizer.filtered(palm).palmFrame)
        #expect(recognizer.process(palm).isEmpty)
        #expect(!recognizer.isTracking)
    }
}

// MARK: - 인식기 (실측 로그)

@Suite("TouchGestureRecognizer 실측 로그")
struct TouchGestureRecognizerFixtureTests {
    @Test func 가장자리_새끼손가락이_호버로_이어진_세_손가락_탭은_길게_탭() throws {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.replay(GestureFixtures.threeFingerTapWithEdgeHover, recognizer: &recognizer)
        try #require(events.count == 1)
        #expect(events[0].gesture == .longPress(fingers: 3))
        #expect(abs(events[0].metrics.duration - 0.462) < 0.0005)
    }

    @Test func 두_손가락_탭_135ms() throws {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.replay(GestureFixtures.twoFingerTap, recognizer: &recognizer)
        try #require(events.count == 1)
        #expect(events[0].gesture == .tap(fingers: 2))
        #expect(abs(events[0].metrics.duration - 0.135) < 0.0005)
    }

    @Test func 두_손가락_오른쪽_스와이프() throws {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.replay(GestureFixtures.twoFingerSwipeRight, recognizer: &recognizer)
        try #require(events.count == 1)
        #expect(events[0].gesture == .swipe(fingers: 2, direction: .right))
        #expect((12.0...12.4).contains(events[0].metrics.dxMM))
        #expect((3.2...3.6).contains(events[0].metrics.dyMM))
        #expect(abs(events[0].metrics.duration - 0.157) < 0.0005)
    }

    @Test func 가장자리_호버_손가락을_포함한_네_손가락_클릭은_한_번만() {
        var recognizer = FrameBuilder.mouseRecognizer()
        let events = FrameBuilder.replay(GestureFixtures.fourFingerClickWithEdgeHover, recognizer: &recognizer)
        #expect(events.map(\.gesture) == [.click(fingers: 4, button: .left)])
    }
}

// MARK: - 로그 형식

@Suite("TouchFrameLog")
struct TouchFrameLogTests {
    @Test func 프레임_줄은_쓰고_읽으면_같은_접촉이_된다() throws {
        let frame = TouchFrame(timestamp: 100.5, contacts: [
            FrameBuilder.contact(1, state: 3, x: 0.338, y: 0.732, z: 0.62, time: 100.5),
            FrameBuilder.contact(6, state: 2, x: 0.1, y: 0.2, z: 0.12, time: 100.5),
        ])
        let filtered = TouchGestureRecognizer.Filtered(kept: [frame.contacts[0]], dropped: [], palmFrame: false)
        let line = TouchFrameLog.frameLine(frame, filtered: filtered, relativeTime: 12.839)
        #expect(line == "t=  12.839 n=1/2 |  p1 MakeTouch (0.338,0.732) z=0.62 | xp6 HoverInRange (0.100,0.200) z=0.12  dt=0.000,0.000")
        let entry = try #require(TouchFrameLog.parse(line))
        guard case .frame(let parsed, let label) = entry else { Issue.record("프레임 줄이어야 한다"); return }
        #expect(label == nil)
        #expect(parsed.timestamp == 12.839)
        #expect(parsed.contacts.map(\.pathIndex) == [1, 6])
        #expect(parsed.contacts.map(\.state) == [3, 2])
        #expect(parsed.contacts.map(\.x) == [0.338, 0.1])
        #expect(parsed.contacts.map(\.y) == [0.732, 0.2])
        #expect(parsed.contacts.map(\.zTotal) == [0.62, 0.12])
    }

    @Test func 라벨과_손바닥_표시가_있는_줄() throws {
        let frame = TouchFrame(timestamp: 3, contacts: [FrameBuilder.contact(2, state: 4, x: 0.5, y: 0.5, z: 6, time: 3)])
        let filtered = TouchGestureRecognizer.Filtered(kept: [], dropped: frame.contacts, palmFrame: true)
        let line = TouchFrameLog.frameLine(frame, filtered: filtered, relativeTime: 1, label: "마우스")
        #expect(line.hasPrefix("[마우스] t=   1.000 n=0/1 손바닥→무시 | xp2 Touching"))
        guard case .frame(let parsed, let label) = try #require(TouchFrameLog.parse(line)) else { Issue.record("프레임 줄이어야 한다"); return }
        #expect(label == "마우스")
        #expect(parsed.contacts.count == 1)
    }

    @Test func 버튼_줄은_쓰고_읽으면_같다() throws {
        let line = TouchFrameLog.buttonLine(.left, down: true, relativeTime: 26.166, source: "MT")
        #expect(line == "t=  26.166 버튼=왼쪽 누름 MT")
        #expect(TouchFrameLog.parse(line) == .button(.left, down: true, deviceTime: 26.166, label: nil))
        let up = TouchFrameLog.buttonLine(.right, down: false, relativeTime: 0.5, label: "마우스")
        #expect(up == "[마우스] t=   0.500 버튼=오른쪽 뗌")
        #expect(TouchFrameLog.parse(up) == .button(.right, down: false, deviceTime: 0.5, label: "마우스"))
        #expect(TouchFrameLog.parse(TouchFrameLog.buttonLine(.other(4), down: true, relativeTime: 2)) == .button(.other(4), down: true, deviceTime: 2, label: nil))
    }

    @Test func 프레임도_버튼도_아닌_줄은_nil() {
        #expect(TouchFrameLog.parse("[   2.425s] 3손가락 탭            270ms") == nil)
        #expect(TouchFrameLog.parse("설정: 탭 ≤3.0mm") == nil)
        #expect(TouchFrameLog.parse("") == nil)
    }

    @Test func 실측_줄을_읽는다() throws {
        let line = "t=  26.110 n=4/4 |  p3 Touching (0.342,0.750) z=0.50 |  p7 Touching (0.893,0.602) z=0.62 |  p10 HoverInRange (0.009,0.643) z=0.12 |  p11 Touching (0.619,0.724) z=0.38  dt=0.000,0.000"
        guard case .frame(let frame, _) = try #require(TouchFrameLog.parse(line)) else { Issue.record("프레임 줄이어야 한다"); return }
        #expect(frame.timestamp == 26.110)
        #expect(frame.contacts.map(\.pathIndex) == [3, 7, 10, 11])
        #expect(frame.contacts[2].phase == .hoverInRange)
        #expect(frame.contacts[2].x == 0.009)
    }

    @Test func 장치_표에서_표면_크기를_읽는다() {
        let header = """
        번호  Family  종류              내장    DeviceID            표면(mm)      열기
        0     111     내장 트랙패드           예       0x070000000000006f  156.0 x 96.0  CreateList
        1     112     Magic Mouse       아니오     0x0400000074bdfd82  51.5 x 90.6   CreateList
        """
        #expect(TouchFrameLog.surfaceSize(inHeader: header) == SurfaceSize(widthMM: 51.5, heightMM: 90.6))
        #expect(TouchFrameLog.surfaceSize(inHeader: "t=   1.000 n=0/0") == nil)
    }
}

// MARK: - 장치·제스처 모델

@Suite("InputDevice")
struct InputDeviceTests {
    @Test func Family_ID를_장치_종류로_바꾼다() {
        #expect(DeviceFamily.kind(forFamilyID: 112) == .magicMouse)
        #expect(DeviceFamily.kind(forFamilyID: 129) == .magicTrackpad)
        #expect(DeviceFamily.kind(forFamilyID: 111) == .builtInTrackpad)
        #expect(DeviceFamily.kind(forFamilyID: 999) == .unknown)
    }

    @Test func 기본_프로필은_매직마우스만_있다() {
        let surface = SurfaceSize.magicMouse2
        let mouse = TouchGestureRecognizer.Profile.default(for: .magicMouse, surface: surface)
        #expect(mouse?.surface == surface)
        #expect(mouse?.countedStates == [3, 4])
        #expect(mouse?.filterResting == true)
        #expect(TouchGestureRecognizer.Profile.default(for: .magicTrackpad, surface: surface) == nil)
        #expect(TouchGestureRecognizer.Profile.default(for: .unknown, surface: surface) == nil)
    }

    @Test func 접촉_상태_이름은_왕복한다() {
        for phase in TouchPhase.allCases {
            #expect(TouchPhase(name: phase.name) == phase)
        }
        #expect(TouchPhase(name: "없는이름") == nil)
        #expect(FrameBuilder.contact(0, state: 9, x: 0, y: 0).stateName == "state9")
    }
}

@Suite("InputGesture")
struct InputGestureTests {
    @Test func 표시_이름은_장치에_따라_앞뒤_위아래가_바뀐다() {
        #expect(InputGesture.swipe(fingers: 3, direction: .up).displayName(for: .magicMouse) == "3손가락 스와이프 앞 ↑")
        #expect(InputGesture.swipe(fingers: 3, direction: .up).displayName(for: .magicTrackpad) == "3손가락 스와이프 위 ↑")
        #expect(InputGesture.swipe(fingers: 2, direction: .left).displayName(for: .magicMouse) == "2손가락 스와이프 왼쪽 ←")
        #expect(InputGesture.click(fingers: 4, button: .right).displayName(for: .magicMouse) == "4손가락 클릭(오른쪽)")
        #expect(InputGesture.longPress(fingers: 2).displayName(for: .magicMouse) == "2손가락 길게 탭")
        #expect(InputGesture.hold(fingers: 3).displayName(for: .magicMouse) == "3손가락 길게 누름")
    }

    @Test func 진단용_종류는_트리거로_고를_수_없다() {
        #expect(GestureKind.allCases.filter(\.isAssignable) == [.tap, .longPress, .click, .swipe])
    }

    @Test func 이벤트_설명은_CLI_출력_형식이다() {
        let device = InputDeviceDescriptor(id: 1, kind: .magicMouse, name: "매직마우스", surface: .magicMouse2)
        let tap = GestureEvent(device: device, gesture: .tap(fingers: 2), metrics: GestureMetrics(dxMM: 0.1, dyMM: -0.2, duration: 0.135), deviceTime: 64.399)
        #expect(tap.description == "2손가락 탭            135ms")
        let swipe = GestureEvent(device: device, gesture: .swipe(fingers: 2, direction: .right), metrics: GestureMetrics(dxMM: 12.2, dyMM: 3.4, duration: 0.157), deviceTime: 75.021)
        #expect(swipe.description == "2손가락 스와이프 오른쪽 →  dx=+12.2mm dy=+3.4mm 157ms")
        let click = GestureEvent(device: device, gesture: .click(fingers: 4, button: .left), metrics: .zero, deviceTime: 26.166)
        #expect(click.description == "4손가락 클릭(왼쪽)")
    }
}

// MARK: - 파이프라인

@Suite("GesturePipeline")
struct GesturePipelineTests {
    /// 큐 위에서 오는 관찰자 호출을 모은다
    final class Collector: Sendable {
        let events = OSAllocatedUnfairLock(initialState: [(event: GestureEvent, sessionTime: Double)]())
        let buttons = OSAllocatedUnfairLock(initialState: [(device: InputDeviceDescriptor, down: Bool, fromDevice: Bool)]())

        var observer: GesturePipeline.Observer {
            GesturePipeline.Observer(
                button: { device, _, down, fromDevice, _ in self.buttons.withLock { $0.append((device, down, fromDevice)) } },
                event: { event, time in self.events.withLock { $0.append((event, time)) } }
            )
        }
    }

    static let mouse = InputDeviceDescriptor(id: 0x0400, kind: .magicMouse, name: "마우스", surface: .magicMouse2)
    static let pad = InputDeviceDescriptor(id: 0x0700, kind: .magicMouse, name: "패드", surface: SurfaceSize(widthMM: 156, heightMM: 96))

    @Test func 장치의_프레임을_인식해_장치가_붙은_이벤트로_전달한다() throws {
        let collector = Collector()
        let pipeline = GesturePipeline(observer: collector.observer)
        pipeline.addDevice(Self.mouse, recognizer: FrameBuilder.mouseRecognizer())
        let frames = FrameBuilder.gesture(fingers: 2, duration: 0.2, start: 10)
        for frame in frames { pipeline.ingest(frame, from: Self.mouse.id) }
        pipeline.drain()
        let events = collector.events.withLock { $0 }
        try #require(events.count == 1)
        #expect(events[0].event.device == Self.mouse)
        #expect(events[0].event.gesture == .tap(fingers: 2))
        #expect(events[0].event.deviceTime == frames.last!.timestamp)
        // 세션 시각은 첫 프레임(10.0초) 기준이다
        #expect(abs(events[0].sessionTime - (frames.last!.timestamp - 10)) < 0.0001)
        #expect(pipeline.frameCount == frames.count)
        #expect(pipeline.deviceList == [Self.mouse])
    }

    @Test func 장치를_모르는_버튼은_최근에_프레임을_보낸_장치로_간다() throws {
        let collector = Collector()
        let pipeline = GesturePipeline(observer: collector.observer)
        pipeline.addDevice(Self.mouse, recognizer: FrameBuilder.mouseRecognizer())
        pipeline.addDevice(Self.pad, recognizer: TouchGestureRecognizer(profile: .init(surface: Self.pad.surface)))
        for frame in FrameBuilder.gesture(fingers: 3, duration: 0.1).dropLast() { pipeline.ingest(frame, from: Self.pad.id) }
        pipeline.buttonChanged(.left, down: true)
        pipeline.buttonChanged(.left, down: false)
        pipeline.drain()
        let events = collector.events.withLock { $0 }
        try #require(events.count == 1)
        #expect(events[0].event.device == Self.pad)
        #expect(events[0].event.gesture == .click(fingers: 3, button: .left))
        let buttons = collector.buttons.withLock { $0 }
        #expect(buttons.map(\.down) == [true, false])
        #expect(buttons.allSatisfy { $0.device == Self.pad && !$0.fromDevice })
    }

    @Test func 장치_버튼은_그_장치로_가고_같은_클릭의_두_번째_알림은_버린다() throws {
        let collector = Collector()
        let pipeline = GesturePipeline(observer: collector.observer)
        pipeline.addDevice(Self.mouse, recognizer: FrameBuilder.mouseRecognizer())
        for frame in FrameBuilder.gesture(fingers: 2, duration: 0.1).dropLast() { pipeline.ingest(frame, from: Self.mouse.id) }
        pipeline.buttonChanged(.right, down: true, device: Self.mouse.id)
        pipeline.buttonChanged(.right, down: true)
        pipeline.drain()
        let events = collector.events.withLock { $0 }
        try #require(events.count == 1)
        #expect(events[0].event.gesture == .click(fingers: 2, button: .right))
        #expect(collector.buttons.withLock { $0 }.map(\.fromDevice) == [true, false])
    }

    @Test func 뺀_장치의_프레임은_세기만_하고_무시한다() {
        let collector = Collector()
        let pipeline = GesturePipeline(observer: collector.observer)
        pipeline.addDevice(Self.mouse, recognizer: FrameBuilder.mouseRecognizer())
        pipeline.removeDevice(Self.mouse.id)
        let frames = FrameBuilder.gesture(fingers: 2, duration: 0.2)
        for frame in frames { pipeline.ingest(frame, from: Self.mouse.id) }
        pipeline.buttonChanged(.left, down: true)
        pipeline.drain()
        #expect(collector.events.withLock { $0 }.isEmpty)
        #expect(collector.buttons.withLock { $0 }.isEmpty)
        #expect(pipeline.frameCount == frames.count)
        #expect(pipeline.deviceList.isEmpty)
    }
}
