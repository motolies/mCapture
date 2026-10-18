import AppKit
import MCaptureCore

/// 클립보드 복사와 파일 저장. PNG 인코딩은 메인 스레드 밖에서 한다
@MainActor
final class Exporter {
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// 6K 이미지 인코딩은 수백 ms가 걸려 백그라운드에서 처리한다
    func encodePNG(_ image: CGImage, scale: CGFloat) async -> Data? {
        let box = SendableImage(image)
        return await Task.detached(priority: .userInitiated) {
            ImageEncoder.pngData(box.cgImage, scale: scale)
        }.value
    }

    /// 이미지를 복사·저장하고 결과를 토스트로 알린다. 저장했으면 그 파일 URL을 돌려준다
    /// existing이 있으면 그 파일에 덮어쓴다 (같은 캡처는 같은 파일). 새 파일 이름의 {app}에는 appName을 쓴다
    @discardableResult
    func export(
        _ image: CGImage,
        scale: CGFloat,
        copy: Bool,
        save: Bool,
        overwriting existing: URL?,
        appName: String? = nil,
        screen: NSScreen?
    ) async -> URL? {
        guard copy || save else { return nil }
        guard let png = await encodePNG(image, scale: scale) else {
            ToastPanel.show("이미지 변환 실패", systemImage: "xmark.octagon.fill")
            return nil
        }
        var messages: [String] = []
        if copy {
            self.copy(png)
            messages.append("복사됨")
        }
        var savedURL: URL?
        if save {
            do {
                let url = try self.save(png, overwriting: existing, appName: appName)
                savedURL = url
                messages.append("저장됨 · \(url.lastPathComponent)")
            } catch {
                ToastPanel.show("저장 실패: \(error.localizedDescription)", systemImage: "xmark.octagon.fill")
                return nil
            }
        }
        ToastPanel.show(messages.joined(separator: " · "), on: screen)
        return savedURL
    }

    func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// 텍스트를 클립보드에 넣는다 (색상 문자열, 인식한 텍스트)
    func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 색을 HEX("#RRGGBB") 또는 RGB("rgb(…)") 문자열로 복사하고 색 견본 토스트로 알린다 (컬러 피커, 영역 선택 Tab)
    /// 완전히 투명한 픽셀은 복사하지 않는다
    func copy(color: RGBAColor, asRGB: Bool, screen: NSScreen?) {
        guard color.alpha > 0 else {
            ToastPanel.show("투명한 픽셀이라 복사하지 않았습니다", systemImage: "exclamationmark.triangle.fill", on: screen)
            return
        }
        let text = asRGB ? color.rgbString : color.hex
        copy(text: text)
        ToastPanel.show("\(text) 복사됨", swatch: color.cgColor, on: screen)
    }

    /// existing이 있으면 덮어쓰고, 없으면 저장 폴더에 설정한 형식의 새 이름으로 저장한다
    func save(_ png: Data, overwriting existing: URL?, appName: String?) throws -> URL {
        let url: URL
        if let existing {
            url = existing
        } else {
            let folder = preferences.saveFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = FileNaming.uniqueURL(in: folder, baseName: baseName(appName: appName), ext: "png") {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
        try png.write(to: url, options: .atomic)
        Log.app.info("저장: \(url.path, privacy: .public)")
        return url
    }

    /// 다른 이름으로 저장·끌어놓기 기본 파일 이름
    func suggestedFileName(appName: String?) -> String {
        baseName(appName: appName) + ".png"
    }

    // 설정한 형식으로 지금 시각의 파일 이름(확장자 제외)을 만든다
    private func baseName(appName: String?) -> String {
        FileNaming.baseName(template: preferences.fileNameTemplate, date: Date(), appName: appName)
    }

    func openSaveFolder() {
        let folder = preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
