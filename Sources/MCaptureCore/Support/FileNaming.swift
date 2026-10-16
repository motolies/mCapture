import Foundation

public enum FileNaming {
    /// 기본 파일 이름 형식. "mCapture_2026-10-16_11-05-32"
    public static let defaultTemplate = "mCapture_{date}_{time}"

    /// {app}에 넣을 앱 이름이 없을 때 쓰는 이름
    public static let fallbackAppName = "mCapture"

    /// 파일 이름 한도(APFS 255바이트)에서 "_2.png" 같은 접미사 자리를 남긴 길이
    static let maxBytes = 200

    /// 템플릿의 {토큰}을 날짜·앱 이름으로 바꾼 파일 이름 (확장자 제외)
    /// 모르는 토큰은 그대로 두고 파일 이름에 곤란한 글자는 정리한다. 결과가 비면 기본 형식을 쓴다
    /// 사용자 달력 설정과 무관하게 그레고리력으로 만든다
    public static func baseName(template: String, date: Date, appName: String?, timeZone: TimeZone = .current) -> String {
        let values = tokenValues(date: date, appName: appName, timeZone: timeZone)
        let expanded = template.replacing(/\{([A-Za-z]+)\}/) { match in
            values[String(match.1)] ?? String(match.0)
        }
        let name = sanitized(expanded)
        guard name.isEmpty else { return name }
        return template == defaultTemplate ? fallbackAppName : baseName(template: defaultTemplate, date: date, appName: appName, timeZone: timeZone)
    }

    /// 토큰별 값. {MM}은 월, {mm}은 분이다
    static func tokenValues(date: Date, appName: String?, timeZone: TimeZone) -> [String: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let two = { (value: Int?) in String(format: "%02d", value ?? 0) }
        let yyyy = String(format: "%04d", parts.year ?? 0)
        let (month, day) = (two(parts.month), two(parts.day))
        let (hour, minute, second) = (two(parts.hour), two(parts.minute), two(parts.second))
        let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            "date": "\(yyyy)-\(month)-\(day)",
            "time": "\(hour)-\(minute)-\(second)",
            "yyyy": yyyy,
            "yy": String(yyyy.suffix(2)),
            "MM": month,
            "dd": day,
            "HH": hour,
            "mm": minute,
            "ss": second,
            "app": app.isEmpty ? fallbackAppName : app,
        ]
    }

    /// 경로 구분자(/, :)·개행·제어문자는 "-"로 바꾸고, 앞쪽 "."(숨김 파일)과 끝의 ".png"를 떼고, 바이트 한도로 자른다
    static func sanitized(_ name: String) -> String {
        var text = String(name.map { character -> Character in
            let unsafe = character == "/" || character == ":" || character.isNewline
                || character.unicodeScalars.contains { $0.properties.generalCategory == .control }
            return unsafe ? "-" : character
        })
        text = text.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasSuffix(".png") { text.removeLast(4) }
        while text.hasPrefix(".") { text.removeFirst() }
        return truncated(text.trimmingCharacters(in: .whitespaces), maxBytes: maxBytes)
    }

    // UTF-8 바이트 수가 한도를 넘지 않게 글자 단위로 자른다 (한글은 글자당 3바이트)
    private static func truncated(_ text: String, maxBytes: Int) -> String {
        var result = ""
        var bytes = 0
        for character in text {
            let size = String(character).utf8.count
            guard bytes + size <= maxBytes else { break }
            result.append(character)
            bytes += size
        }
        return result
    }

    /// 폴더 안에서 겹치지 않는 파일 경로를 만든다. 이미 있으면 _2, _3을 붙인다
    public static func uniqueURL(in folder: URL, baseName: String, ext: String, exists: (URL) -> Bool) -> URL {
        var candidate = folder.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(baseName)_\(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
