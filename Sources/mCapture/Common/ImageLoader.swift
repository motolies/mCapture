import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 읽어 들인 이미지와 Retina 배율 (DPI / 72)
struct LoadedImage {
    let image: CGImage
    let scale: CGFloat
}

/// 파일·클립보드에서 이미지를 읽는다. 파일 열기, 드롭, 붙여넣기가 함께 쓴다
@MainActor
enum ImageLoader {
    /// 이미지 파일을 읽는다. 읽을 수 없으면 nil
    static func load(url: URL) -> LoadedImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(load(source:))
    }

    /// PNG·TIFF 등 이미지 데이터를 읽는다
    static func load(data: Data) -> LoadedImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(load(source:))
    }

    /// 클립보드 이미지를 읽는다. 이미지 데이터를 먼저 보고, 없으면 복사한 이미지 파일을 읽는다
    static func load(from pasteboard: NSPasteboard) -> LoadedImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let loaded = load(data: data) { return loaded }
        }
        return imageFileURLs(from: pasteboard).lazy.compactMap(load(url:)).first
    }

    /// 클립보드에 읽을 수 있는 이미지가 있는지 (메뉴 활성화용, 실제로 디코딩하지는 않는다)
    static func canLoad(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil || !imageFileURLs(from: pasteboard).isEmpty
    }

    /// 클립보드·드래그에 담긴 파일 URL 중 이미지 파일만 고른다
    static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    // 첫 프레임과 DPI를 읽는다. DPI 정보가 없으면 72(1배)로 본다
    private static func load(source: CGImageSource) -> LoadedImage? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return LoadedImage(image: image, scale: max(1, (dpi / 72).rounded()))
    }
}
