import CoreGraphics
import Testing
@testable import MCaptureCore

@Suite("Capture overlay crosshair backing alignment")
struct OverlayCrosshairTests {
    @Test(arguments: [CGFloat(1), 2])
    func alignedEdgesAndOnePointThickness(scale: CGFloat) {
        let bounds = CGRect(x: 0, y: 0, width: 100 * scale, height: 80 * scale)
        for point in [CGPoint.zero, CGPoint(x: 12.75, y: 31.25), CGPoint(x: 99.75, y: 79.75)] {
            let frames = OverlayCrosshair.frames(at: CGPoint(x: point.x * scale, y: point.y * scale),
                                                 in: bounds, backingScale: scale)
            #expect(frames.count == 4)
            #expect(frames[2].width / scale == 1)
            #expect(frames[3].height / scale == 1)
            #expect(frames[2].minX == floor(point.x * scale))
            #expect(frames[3].minY == floor(point.y * scale))
            #expect(frames[0].minX - frames[2].minX == scale)
            #expect(frames[1].minY - frames[3].minY == scale)
            #expect(frames[2].height == bounds.height)
            #expect(frames[3].width == bounds.width)
        }
    }

    @Test func retinaPreservesHalfPointSteps() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
        let first = OverlayCrosshair.frames(at: CGPoint(x: 20, y: 20), in: bounds, backingScale: 2)
        let next = OverlayCrosshair.frames(at: CGPoint(x: 21, y: 21), in: bounds, backingScale: 2)
        #expect((next[2].minX - first[2].minX) / 2 == 0.5)
        #expect((next[3].minY - first[3].minY) / 2 == 0.5)
    }
}
