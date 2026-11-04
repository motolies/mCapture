import Foundation
import CoreGraphics
import Testing
@testable import MCaptureCore

@MainActor
private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@Suite @MainActor
struct AsyncLifecycleTests {
    @Test func exportsUseFIFOAndLatestSuccessfulPath() async {
        let session = DocumentExportSession()
        let gate = Gate()
        let first = URL(fileURLWithPath: "/first.png")
        let renamed = URL(fileURLWithPath: "/renamed.png")
        var order: [Int] = []
        session.enqueue { target in
            #expect(target == nil)
            order.append(1)
            await gate.wait()
            return first
        }
        session.enqueue { target in
            #expect(target == first)
            order.append(2)
            return target
        }
        session.enqueue(target: renamed) { target in
            #expect(target == renamed)
            order.append(3)
            return target
        }
        session.enqueue { target in
            #expect(target == renamed)
            order.append(4)
            return nil // encoding or saving failed
        }
        let done = session.enqueue { target in
            #expect(target == renamed)
            order.append(5)
            return target
        }
        while gate.continuation == nil { await Task.yield() }
        #expect(order == [1])
        gate.release()
        await done.value
        #expect(order == [1, 2, 3, 4, 5])
        #expect(session.savedURL == renamed)
    }

    @Test func documentCopiesSharePendingSaveAndFinalBytes() async throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let document = CaptureDocument(image: try #require(context.makeImage()), scale: 1)
        let editor = document
        let pin = editor
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = Gate()
        document.exportSession.enqueue { _ in
            await gate.wait()
            try? Data([1]).write(to: url)
            return url
        }
        editor.exportSession.enqueue { target in
            #expect(target == url)
            if let target { try? Data([2]).write(to: target) }
            return target
        }
        let done = pin.exportSession.enqueue { target in
            #expect(target == url)
            if let target { try? Data([3]).write(to: target) }
            return target
        }
        while gate.continuation == nil { await Task.yield() }
        gate.release()
        await done.value
        #expect(try Data(contentsOf: url) == Data([3]))
        #expect(document.savedURL == url)
        #expect(editor.savedURL == url)
        #expect(pin.savedURL == url)
    }

    @Test func firstFailureAndCopyDoNotAllocateAPath() async {
        let session = DocumentExportSession()
        session.enqueue { _ in nil }
        let done = session.enqueue { target in #expect(target == nil); return nil }
        await done.value
        #expect(session.savedURL == nil)
    }

    @Test func timeoutDoesNotWaitForUncooperativeSave() async throws {
        let gate = Gate()
        let race = TerminationRace()
        var replies = 0
        race.start(timeout: .milliseconds(10), save: { await gate.wait() }, reply: { replies += 1 })
        while replies == 0 { try await Task.sleep(for: .milliseconds(1)) }
        #expect(gate.continuation != nil)
        #expect(replies == 1)
        gate.release()
        try await Task.sleep(for: .milliseconds(20))
        #expect(replies == 1)
    }

    @Test(arguments: [0, 1, 20]) func terminationRepliesOnce(delay: Int) async throws {
        let race = TerminationRace()
        var replies = 0
        race.start(timeout: .milliseconds(1), save: {
            try? await Task.sleep(for: .milliseconds(delay))
        }, reply: { replies += 1 })
        race.start(timeout: .zero, save: {}, reply: { replies += 100 })
        try await Task.sleep(for: .milliseconds(40))
        #expect(replies == 1)
    }
}
