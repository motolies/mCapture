import AppKit
import Testing
@testable import mCapture

@Suite(.serialized)
@MainActor
struct SelectionViewTests {
    private func fixture() throws -> (OverlayPanel, SelectionView) {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let panel = OverlayPanel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = SelectionView(shot: ScreenShot(screen: screen, image: image),
                                 frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        panel.contentView = view
        return (panel, view)
    }

    private func move(_ view: SelectionView, in panel: NSWindow) throws {
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 20.5, y: 30.5),
                                                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber, context: nil,
                                                    eventNumber: 1, clickCount: 0, pressure: 0))
        view.mouseMoved(with: event)
    }

    private func lines(_ view: SelectionView) -> [CALayer] {
        view.subviews.last?.layer?.sublayers ?? []
    }

    @Test func crossingPanelsWithoutExitClearsPreviousCrosshair() throws {
        let (firstPanel, first) = try fixture()
        let (secondPanel, second) = try fixture()
        // Same ownership callbacks installed by the overlay controller, with no mouseExited.
        first.onPointerActivity = { second.clearPointer() }
        second.onPointerActivity = { first.clearPointer() }
        try move(first, in: firstPanel)
        #expect(lines(first).count == 4)
        #expect(lines(first).allSatisfy { !$0.isHidden })
        try move(second, in: secondPanel)
        #expect(lines(first).allSatisfy { $0.isHidden })
        #expect(lines(second).allSatisfy { !$0.isHidden })
        try move(first, in: firstPanel)
        #expect(lines(second).allSatisfy { $0.isHidden })
        #expect(lines(first).allSatisfy { !$0.isHidden })
        first.finishPresentation()
        #expect(lines(first).allSatisfy { $0.isHidden })
    }

    @Test func dragAndResetHideCrosshair() throws {
        let (panel, view) = try fixture()
        try move(view, in: panel)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 40, y: 40),
                                                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: panel.windowNumber, context: nil,
                                                  eventNumber: 2, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        #expect(lines(view).allSatisfy { $0.isHidden })
        view.resetInteraction()
        #expect(lines(view).allSatisfy { $0.isHidden })
        try move(view, in: panel)
        #expect(lines(view).allSatisfy { !$0.isHidden })
    }
    @Test func shiftSquareAndSpaceTranslationPreserveSelection() throws {
        let (panel, view) = try fixture()
        func event(_ type: NSEvent.EventType, _ point: CGPoint, shift: Bool = false) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point,
                                            modifierFlags: shift ? [.shift] : [],
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: panel.windowNumber, context: nil,
                                            eventNumber: 1, clickCount: 1, pressure: 1))
        }
        var picked: CGRect?
        view.onFinish = { if case .area(let rect) = $0 { picked = rect } }
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 0, y: 100)))
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 75, y: 50), shift: true))
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 75, y: 50), shift: true))
        let square = try #require(picked)
        #expect(square.width == square.height)
        #expect(square.width > 0)

        picked = nil
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 0, y: 100)))
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 75, y: 50)))
        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                 characters: " ", charactersIgnoringModifiers: " ",
                                                 isARepeat: false, keyCode: 49))
        view.keyDown(with: space)
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 100, y: 25)))
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 100, y: 25)))
        let moved = try #require(picked)
        let imageScale = CGFloat(100) / NSScreen.screens[0].frame.width
        #expect(moved.width == (75 * imageScale).rounded())
        #expect(moved.height == (50 * imageScale).rounded())
        #expect(moved.minX > 0)
        #expect(moved.minY > 0)
    }

}
