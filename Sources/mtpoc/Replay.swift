import Foundation

/// --raw 로그를 다시 읽어 인식기에 흘려 넣는다.
/// 사용자가 다시 제스처를 해 주지 않아도, 같은 프레임으로 인식기 수정의 효과를 확인하기 위한 것
enum Replay {
    struct Frame {
        let label: String?
        let timestamp: Double
        let touches: [Touch]
    }

    /// raw 한 줄을 프레임으로 되돌린다. 라벨("[마우스] ")은 따로 떼고 꼬리의 dt는 버린다
    /// 형식: `[라벨] t=  12.839 n=2/2 |  p1 MakeTouch (0.338,0.732) z=0.62 | xp6 OutOfRange (...) z=0.00  dt=0.000,0.000`
    static func parse(line: String) -> Frame? {
        var body = Substring(line)
        var label: String?
        if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
            label = String(body[body.index(after: body.startIndex)..<close])
            body = body[body.index(after: close)...].drop(while: { $0 == " " })
        }
        guard body.hasPrefix("t=") else { return nil }
        if let tail = body.range(of: "  dt=") { body = body[..<tail.lowerBound] }
        let segments = body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = segments.first else { return nil }
        // "t=  12.839 n=2/2" → 공백 패딩 때문에 "t="와 숫자가 갈라질 수 있다
        let headTokens = head.split(separator: " ")
        var timestampText = String(headTokens[0].dropFirst(2))
        if timestampText.isEmpty, headTokens.count > 1 { timestampText = String(headTokens[1]) }
        guard let timestamp = Double(timestampText) else { return nil }
        var touches: [Touch] = []
        for segment in segments.dropFirst() {
            var text = Substring(segment)
            if text.hasPrefix("x") { text = text.dropFirst() }
            let tokens = text.split(separator: " ")
            guard tokens.count >= 4, tokens[0].hasPrefix("p"), let path = Int32(tokens[0].dropFirst()) else { continue }
            let stateName = String(tokens[1])
            let state = Touch.stateNames.firstIndex(of: stateName) ?? Int(stateName.dropFirst(5)) ?? -1
            let coords = tokens[2].dropFirst().dropLast().split(separator: ",")
            guard coords.count == 2, let x = Float(coords[0]), let y = Float(coords[1]),
                  let z = Float(tokens[3].dropFirst(2)) else { continue }
            touches.append(Touch(
                timestamp: timestamp, pathIndex: path, state: Int32(state), fingerID: 0,
                x: x, y: y, velX: 0, velY: 0, zTotal: z, zDensity: 0
            ))
        }
        return Frame(label: label, timestamp: timestamp, touches: touches)
    }

    /// 장치 표의 "Magic Mouse ... 51.5 x 90.6" 줄에서 표면 크기를 읽는다. 없으면 Magic Mouse 2 값
    static func surface(in text: String) -> (width: Double, height: Double) {
        for line in text.split(separator: "\n") where line.contains("Magic Mouse") {
            let numbers = line.split(separator: " ").compactMap { Double($0) }
            if numbers.count >= 2, let x = line.range(of: " x ") {
                let before = line[..<x.lowerBound].split(separator: " ").last.flatMap { Double($0) }
                let after = line[x.upperBound...].split(separator: " ").first.flatMap { Double($0) }
                if let before, let after { return (before, after) }
            }
        }
        return (51.5, 90.6)
    }

    /// 로그 파일의 마우스 프레임을 순서대로 인식기에 넣고 이벤트를 찍는다.
    /// 끊김 정리 타이머는 재생에서 의미가 없어 쓰지 않는다 (떨어짐 판정은 프레임 내용으로 한다)
    static func run(path: String, options: Options) {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            Console.error("로그를 읽을 수 없다: \(path)")
            exit(1)
        }
        let size = surface(in: text)
        var recognizer = GestureRecognizer(config: .init(
            thresholds: options.thresholds, countedStates: options.states, filterResting: options.filter,
            widthMM: size.width, heightMM: size.height
        ))
        var frames = 0
        var events = 0
        for line in text.split(separator: "\n") {
            guard let frame = parse(line: String(line)) else { continue }
            if let label = frame.label, label != "마우스" { continue }
            frames += 1
            for event in recognizer.process(timestamp: frame.timestamp, touches: frame.touches) {
                events += 1
                Console.line(String(format: "[%8.3fs] ", frame.timestamp) + event.description)
            }
        }
        Console.line("재생 끝: 프레임 \(frames)개, 이벤트 \(events)개, 표면 \(size.width) x \(size.height)mm (\(path))")
    }
}
