import CoreGraphics

/// 원본 이미지와 편집 상태를 합쳐 최종 이미지를 만든다
public enum DocumentRenderer {
    /// y 아래 방향 컨텍스트에 이미지를 뒤집히지 않게 그린다
    public static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// region(기본값: 크롭 영역)만큼의 비트맵에 원본과 주석을 그린다. 실패하면 nil
    public static func render(image: CGImage, state: EditState, scale: CGFloat, region: CGRect? = nil) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let target = RectMath.clamp(RectMath.pixelAligned(region ?? state.visibleRect(imageBounds: bounds)), to: bounds)
        else { return nil }

        let width = Int(target.width)
        let height = Int(target.height)
        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // 이미지 픽셀 좌표(왼쪽 위 원점)로 그릴 수 있게 좌표계를 뒤집고 영역만큼 이동
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -target.minX, y: -target.minY)

        if let cropped = image.cropping(to: target) {
            drawImage(cropped, in: target, ctx: ctx)
        }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        let redactions = RedactionCache(source: image)
        for annotation in state.annotations {
            AnnotationRenderer.draw(annotation, in: ctx, pointScale: scale, redactions: redactions)
        }
        return ctx.makeImage()
    }
}
