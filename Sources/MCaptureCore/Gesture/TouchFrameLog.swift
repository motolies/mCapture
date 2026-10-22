import Foundation

/// `--raw` 로그 한 줄의 형식. 쓰기와 읽기를 한곳에 둬 CLI 기록·재생·테스트 픽스처가 같은 형식을 쓴다
///
/// 프레임: `[라벨] t=  12.839 n=1/2 |  p1 MakeTouch (0.338,0.732) z=0.62 | xp6 HoverInRange (0.100,0.200) z=0.12  dt=0.000,0.000`
/// (n은 센 접촉/전체, 안 센 접촉은 x 표시, dt는 앞 두 접촉의 timestamp − 프레임 timestamp로 0이면 레코드 오프셋이 맞다는 뜻)
/// 버튼: `[라벨] t=  26.166 버튼=왼쪽 누름 MT` (꼬리표는 출처 표시, 선택)
public enum TouchFrameLog {
    /// 한 줄을 읽은 결과
    public enum Entry: Equatable, Sendable {
        case frame(TouchFrame, label: String?)
        case button(MouseButton, down: Bool, deviceTime: Double, label: String?)
    }

    /// 프레임 한 줄을 만든다. 걸러진 접촉은 x 표시
    public static func frameLine(
        _ frame: TouchFrame, filtered: TouchGestureRecognizer.Filtered, relativeTime: Double, label: String? = nil
    ) -> String {
        let counted = filtered.countedPaths
        let parts = frame.contacts.map { contact -> String in
            let mark = counted.contains(contact.pathIndex) ? " " : "x"
            return "\(mark)p\(contact.pathIndex) \(contact.stateName) (\(GestureFormat.f3(contact.x)),\(GestureFormat.f3(contact.y))) z=\(GestureFormat.f2(contact.zTotal))"
        }
        let deltas = frame.contacts.prefix(2).map { String(format: "%.3f", $0.timestamp - frame.timestamp) }
        var line = prefix(label) + String(format: "t=%8.3f n=%d/%d", relativeTime, filtered.kept.count, frame.contacts.count)
        if filtered.palmFrame { line += " 손바닥→무시" }
        if !parts.isEmpty { line += " | " + parts.joined(separator: " | ") }
        if !deltas.isEmpty { line += "  dt=" + deltas.joined(separator: ",") }
        return line
    }

    /// 버튼 한 줄을 만든다. source는 "MT"처럼 어느 경로가 알려 줬는지 적는 꼬리표
    public static func buttonLine(
        _ button: MouseButton, down: Bool, relativeTime: Double, label: String? = nil, source: String? = nil
    ) -> String {
        var line = prefix(label) + String(format: "t=%8.3f 버튼=", relativeTime) + button.displayName + (down ? " 누름" : " 뗌")
        if let source { line += " " + source }
        return line
    }

    /// 한 줄을 되돌린다. 프레임 줄도 버튼 줄도 아니면 nil. 라벨("[마우스] ")은 따로 떼고 꼬리의 dt는 버린다
    public static func parse(_ line: String) -> Entry? {
        var body = Substring(line)
        var label: String?
        if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
            label = String(body[body.index(after: body.startIndex)..<close])
            body = body[body.index(after: close)...].drop(while: { $0 == " " })
        }
        guard body.hasPrefix("t=") else { return nil }
        if let range = body.range(of: " 버튼=") {
            let tokens = body[range.upperBound...].split(separator: " ")
            let timeText = body[body.index(body.startIndex, offsetBy: 2)..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            guard tokens.count >= 2, let time = Double(timeText) else { return nil }
            return .button(button(named: tokens[0]), down: tokens[1] == "누름", deviceTime: time, label: label)
        }
        if let tail = body.range(of: "  dt=") { body = body[..<tail.lowerBound] }
        let segments = body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = segments.first else { return nil }
        // "t=  12.839 n=2/2" → 공백 패딩 때문에 "t="와 숫자가 갈라질 수 있다
        let headTokens = head.split(separator: " ")
        var timeText = String(headTokens[0].dropFirst(2))
        if timeText.isEmpty, headTokens.count > 1 { timeText = String(headTokens[1]) }
        guard let time = Double(timeText) else { return nil }
        var contacts: [TouchContact] = []
        for segment in segments.dropFirst() {
            var text = Substring(segment)
            if text.hasPrefix("x") { text = text.dropFirst() }
            let tokens = text.split(separator: " ")
            guard tokens.count >= 4, tokens[0].hasPrefix("p"), let path = Int32(tokens[0].dropFirst()) else { continue }
            let stateName = String(tokens[1])
            let state = TouchPhase(name: stateName)?.rawValue ?? Int32(stateName.dropFirst(5)) ?? -1
            let coords = tokens[2].dropFirst().dropLast().split(separator: ",")
            guard coords.count == 2, let x = Float(coords[0]), let y = Float(coords[1]),
                  let z = Float(tokens[3].dropFirst(2)) else { continue }
            contacts.append(TouchContact(timestamp: time, pathIndex: path, state: state, x: x, y: y, zTotal: z))
        }
        return .frame(TouchFrame(timestamp: time, contacts: contacts), label: label)
    }

    /// 장치 표의 "Magic Mouse ... 51.5 x 90.6" 줄에서 표면 크기를 읽는다. 없으면 nil
    public static func surfaceSize(inHeader text: String) -> SurfaceSize? {
        for line in text.split(separator: "\n") where line.contains("Magic Mouse") {
            guard let x = line.range(of: " x ") else { continue }
            let before = line[..<x.lowerBound].split(separator: " ").last.flatMap { Double($0) }
            let after = line[x.upperBound...].split(separator: " ").first.flatMap { Double($0) }
            if let before, let after { return SurfaceSize(widthMM: before, heightMM: after) }
        }
        return nil
    }

    // 라벨 접두사 "[라벨] "
    private static func prefix(_ label: String?) -> String {
        label.map { "[\($0)] " } ?? ""
    }

    // "왼쪽"·"오른쪽"·"버튼N"을 버튼으로
    private static func button(named token: Substring) -> MouseButton {
        switch token {
        case "왼쪽": .left
        case "오른쪽": .right
        default: .other(Int(token.dropFirst(2)) ?? 2)
        }
    }
}
