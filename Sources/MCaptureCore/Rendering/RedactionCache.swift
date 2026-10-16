import CoreGraphics
import CoreImage

/// 픽셀화·블러 가리기 결과를 원본에서 만들어 둔다
/// 캔버스는 다시 그릴 때마다 같은 결과를 쓰도록 문서마다 하나를 유지하고, 내보내기는 렌더링마다 새로 만든다
public final class RedactionCache {
    public let source: CGImage

    private struct Key: Equatable {
        let region: CGRect
        let mode: RedactMode
        let size: AnnotationSize
        let pointScale: CGFloat
    }

    /// 드래그하는 동안 프레임마다 새 키가 생기므로 개수와 픽셀 총량(약 96MB)을 제한한다. 먼저 넣은 것부터 버린다
    private static let capacity = 32
    private static let pixelBudget = 24_000_000
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private var entries: [(key: Key, image: CGImage)] = []
    private var cachedPixels = 0

    public init(source: CGImage) {
        self.source = source
    }

    private var bounds: CGRect {
        CGRect(x: 0, y: 0, width: source.width, height: source.height)
    }

    /// rect(이미지 픽셀)를 가린 결과를 ctx(이미지 픽셀 좌표, y 아래 방향)에 그린다. 원본 밖 부분은 그리지 않는다
    public func draw(_ rect: CGRect, mode: RedactMode, size: AnnotationSize, pointScale: CGFloat, in ctx: CGContext) {
        guard let region = RectMath.clamp(RectMath.pixelAligned(rect), to: bounds),
              let image = image(for: Key(region: region, mode: mode, size: size, pointScale: pointScale))
        else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        DocumentRenderer.drawImage(image, in: region, ctx: ctx)
        ctx.restoreGState()
    }

    // 캐시에 있으면 쓰고, 없으면 만들어 넣는다
    private func image(for key: Key) -> CGImage? {
        if let hit = entries.first(where: { $0.key == key }) { return hit.image }
        let made: CGImage?
        switch key.mode {
        case .pixelate: made = pixelate(key.region, block: max(1, (key.size.pixelateBlock * key.pointScale).rounded()))
        case .blur: made = blur(key.region, radius: key.size.blurRadius * key.pointScale)
        }
        guard let made else { return nil }
        entries.append((key, made))
        cachedPixels += made.width * made.height
        // 방금 만든 결과는 남긴다
        while entries.count > 1, entries.count > Self.capacity || cachedPixels > Self.pixelBudget {
            let dropped = entries.removeFirst().image
            cachedPixels -= dropped.width * dropped.height
        }
        return made
    }

    /// 블록 하나가 한 픽셀이 되게 줄였다가 보간 없이 키운다. 블록은 영역 왼쪽 위에 맞춰 정렬된다
    func pixelate(_ region: CGRect, block: CGFloat) -> CGImage? {
        let columns = max(1, Int((region.width / block).rounded(.up)))
        let rows = max(1, Int((region.height / block).rounded(.up)))
        // 마지막 블록이 영역 밖으로 걸치면 원본에서 그만큼 더 읽어 블록 평균이 맞게 한다
        let covered = CGRect(x: region.minX, y: region.minY, width: CGFloat(columns) * block, height: CGFloat(rows) * block)
        guard let readable = RectMath.clamp(covered, to: bounds),
              let piece = source.cropping(to: readable),
              let small = Self.bitmap(width: columns, height: rows, like: source),
              let output = Self.bitmap(width: Int(region.width), height: Int(region.height), like: source)
        else { return nil }

        // CG 비트맵은 왼쪽 아래 원점이라 위쪽에 맞춰 배치한다
        let exact = CGRect(
            x: 0,
            y: CGFloat(rows) - readable.height / block,
            width: readable.width / block,
            height: readable.height / block
        )
        small.interpolationQuality = .high
        // 이미지 경계에 걸려 비는 칸이 없도록 먼저 늘려 채운 뒤 정확한 배율로 덮는다
        small.draw(piece, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        small.setBlendMode(.copy)
        small.draw(piece, in: exact)
        guard let blocks = small.makeImage() else { return nil }

        output.interpolationQuality = .none
        output.draw(blocks, in: CGRect(x: 0, y: region.height - CGFloat(rows) * block, width: CGFloat(columns) * block, height: CGFloat(rows) * block))
        return output.makeImage()
    }

    /// 가장자리가 투명하게 번지지 않도록 주변까지 읽고 끝 픽셀을 늘인 뒤 흐린다
    func blur(_ region: CGRect, radius: CGFloat) -> CGImage? {
        let padding = (radius * 3).rounded(.up)
        guard let padded = RectMath.clamp(region.insetBy(dx: -padding, dy: -padding), to: bounds),
              let piece = source.cropping(to: padded)
        else { return nil }
        let blurred = CIImage(cgImage: piece).clampedToExtent().applyingGaussianBlur(sigma: Double(radius))
        // Core Image 좌표도 왼쪽 아래 원점이다
        let local = CGRect(x: region.minX - padded.minX, y: padded.maxY - region.maxY, width: region.width, height: region.height)
        let colorSpace = source.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return Self.context.createCGImage(blurred, from: local, format: .RGBA8, colorSpace: colorSpace)
    }

    // 원본과 같은 색 공간의 비트맵 컨텍스트
    private static func bitmap(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
