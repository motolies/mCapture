import CoreGraphics

/// Capture overlay only. Input/output use backing pixels; line thickness remains 1 point.
/// Align the leading edge, preserving half-point movement on a 2x display.
public enum OverlayCrosshair {
    public static func frames(at point: CGPoint, in bounds: CGRect, backingScale: CGFloat) -> [CGRect] {
        let thickness = backingScale
        let x = point.x.rounded(.down)
        let y = point.y.rounded(.down)
        return [
            CGRect(x: x + thickness, y: bounds.minY, width: thickness, height: bounds.height),
            CGRect(x: bounds.minX, y: y + thickness, width: bounds.width, height: thickness),
            CGRect(x: x, y: bounds.minY, width: thickness, height: bounds.height),
            CGRect(x: bounds.minX, y: y, width: bounds.width, height: thickness),
        ]
    }
}
