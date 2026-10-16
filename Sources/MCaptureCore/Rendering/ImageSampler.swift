import CoreGraphics

/// 원본 이미지의 픽셀을 읽는다
public enum ImageSampler {
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
}
