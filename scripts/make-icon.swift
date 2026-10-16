// mCapture 앱 아이콘(Resources/AppIcon.icns)을 생성한다.
// 사용법: swift scripts/make-icon.swift
// 1024px 원본을 CoreGraphics로 그리고 크기별 PNG(build/AppIcon.iconset)를 만든 뒤 iconutil로 묶는다.
// Command Line Tools에는 actool이 없어 Icon Composer(.icon) 형식 대신 .icns를 쓴다.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

/// sRGB 색
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// 투명 배경 RGBA 비트맵 컨텍스트
func makeContext(size: Int) -> CGContext {
    CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

/// 1024px 원본: macOS 격자(824px 둥근 사각형 + 그림자) 위에 파란 그라디언트, 흰 뷰파인더 모서리와 십자
func drawMaster() -> CGImage {
    let ctx = makeContext(size: Int(canvas))
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 그림자 (CG 좌표는 y 위쪽이 양수라 아래로 내리려면 음수)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2F49D1))
    ctx.fillPath()
    ctx.restoreGState()

    // 위에서 아래로 밝은 파랑 → 남색
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x5AA0FF), color(0x3A5BE0), color(0x2B37B8)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.restoreGState()

    // 뷰파인더 모서리 4개
    let frame = body.insetBy(dx: 170, dy: 170)
    let arm: CGFloat = 130
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(52)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
        (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
        (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
    ]
    for (corner, sx, sy) in corners {
        ctx.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
    }
    ctx.strokePath()

    // 가운데 십자
    let center = CGPoint(x: body.midX, y: body.midY)
    let half: CGFloat = 78
    ctx.setLineWidth(40)
    ctx.move(to: CGPoint(x: center.x - half, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + half, y: center.y))
    ctx.move(to: CGPoint(x: center.x, y: center.y - half))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + half))
    ctx.strokePath()

    return ctx.makeImage()!
}

/// 원본을 size 픽셀로 줄여 PNG로 쓴다
func writePNG(_ master: CGImage, size: Int, to url: URL) throws {
    let ctx = makeContext(size: size)
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let master = drawMaster()
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(master, size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(master, size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("❌ iconutil 실패 (\(iconutil.terminationStatus))")
    exit(1)
}
print("✅ \(output.path)")
print("   미리보기: \(iconset.appendingPathComponent("icon_512x512@2x.png").path)")
