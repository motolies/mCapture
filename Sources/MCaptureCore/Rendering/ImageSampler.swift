import CoreGraphics

/// 원본 이미지의 픽셀을 읽는다
public enum ImageSampler {
    /// 같은 색으로 이어진 가로·세로 구간 (이미지 픽셀, 시작 포함·끝 제외)
    public struct Span: Equatable, Sendable {
        public var horizontal: Range<Int>
        public var vertical: Range<Int>

        public init(horizontal: Range<Int>, vertical: Range<Int>) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    /// 알파가 0이 아닌 픽셀을 모두 담는 가장 작은 사각형 (이미지 픽셀, 왼쪽 위 원점). 모두 투명하면 nil
    /// 그림자를 넣어 넉넉하게 받은 창 캡처에서 투명한 가장자리를 잘라낼 때 쓴다
    public static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] != 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // 알파 전용 비트맵도 첫 행이 이미지 맨 위다
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 이미지 픽셀 하나의 sRGB 색 (왼쪽 위 원점, 소수 좌표는 내림). 이미지 밖이면 nil
    /// 반투명 픽셀은 premultiply를 되돌려 원래 색과 알파를 돌려준다. 완전히 투명하면 알파 0인 검정
    public static func color(at pixel: CGPoint, in image: CGImage) -> RGBAColor? {
        let x = pixel.x.rounded(.down)
        let y = pixel.y.rounded(.down)
        guard x >= 0, y >= 0, x < CGFloat(image.width), y < CGFloat(image.height),
              let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let bytes = rgbaBytes(of: cropped, width: 1, height: 1, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        else { return nil }

        let alpha = Double(bytes[3])
        guard alpha > 0 else { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
        // 비트맵 컨텍스트는 premultiplied만 지원하므로 알파로 나눠 원래 색으로 되돌린다
        func channel(_ value: UInt8) -> Double { min(Double(value) / alpha, 1) }
        return RGBAColor(red: channel(bytes[0]), green: channel(bytes[1]), blue: channel(bytes[2]), alpha: alpha / 255)
    }

    /// pixel에서 좌우·상하로 시작 픽셀과 같은 색(채널별 차이가 tolerance 이하)이 이어지는 구간을 찾는다 (픽셀 자 자동 간격)
    /// 이웃끼리가 아니라 시작 색과 비교해 그라디언트에서 끝없이 번지지 않게 하고, within(보이는 영역) 밖으로는 나가지 않는다
    /// 커서가 있는 행과 열의 1px 띠만 원본 색 공간으로 읽는다. sRGB로 바꾸면 넓은 색역의 서로 다른 색이 같은 값으로 잘릴 수 있다
    public static func span(at pixel: CGPoint, in image: CGImage, within bounds: CGRect, tolerance: Int = 0) -> Span? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let area = RectMath.clamp(RectMath.pixelAligned(bounds), to: imageBounds) else { return nil }
        let x = Int(pixel.x.rounded(.down))
        let y = Int(pixel.y.rounded(.down))
        let minX = Int(area.minX), maxX = Int(area.maxX), minY = Int(area.minY), maxY = Int(area.maxY)
        guard (minX..<maxX).contains(x), (minY..<maxY).contains(y) else { return nil }

        let space = image.colorSpace.flatMap { $0.supportsOutput && $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let row = image.cropping(to: CGRect(x: minX, y: y, width: maxX - minX, height: 1))
                .flatMap({ rgbaBytes(of: $0, width: maxX - minX, height: 1, space: space) }),
              let column = image.cropping(to: CGRect(x: x, y: minY, width: 1, height: maxY - minY))
                .flatMap({ rgbaBytes(of: $0, width: 1, height: maxY - minY, space: space) })
        else { return nil }

        let horizontal = run(in: row, from: x - minX, tolerance: tolerance)
        let vertical = run(in: column, from: y - minY, tolerance: tolerance)
        return Span(
            horizontal: (horizontal.lowerBound + minX)..<(horizontal.upperBound + minX),
            vertical: (vertical.lowerBound + minY)..<(vertical.upperBound + minY)
        )
    }

    // 이미지를 premultiplied RGBA 8비트 버퍼로 읽는다. 첫 픽셀이 이미지 왼쪽 위
    private static func rgbaBytes(of image: CGImage, width: Int, height: Int, space: CGColorSpace) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    // RGBA 픽셀 목록에서 start 픽셀과 같은 색이 이어지는 구간
    private static func run(in pixels: [UInt8], from start: Int, tolerance: Int) -> Range<Int> {
        let count = pixels.count / 4
        let base = start * 4
        func same(_ index: Int) -> Bool {
            let offset = index * 4
            for channel in 0..<4 where abs(Int(pixels[offset + channel]) - Int(pixels[base + channel])) > tolerance {
                return false
            }
            return true
        }
        var lower = start
        var upper = start + 1
        while lower > 0, same(lower - 1) { lower -= 1 }
        while upper < count, same(upper) { upper += 1 }
        return lower..<upper
    }
}
