import AppKit
@preconcurrency import ScreenCaptureKit
import MCaptureCore

/// 디스플레이 하나를 캡처한 결과
struct ScreenShot {
    let screen: NSScreen
    let image: CGImage

    /// 이미지 픽셀 / 논리 포인트
    var scale: CGFloat {
        CGFloat(image.width) / max(screen.frame.width, 1)
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .noDisplay: "캡처할 디스플레이를 찾지 못했습니다."
        case .windowNotFound: "창을 찾지 못했습니다. 이미 닫혔을 수 있습니다."
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 마우스 커서가 있는 화면
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

/// ScreenCaptureKit으로 디스플레이 전체를 네이티브 해상도로 캡처한다
@MainActor
enum ScreenCapturer {
    // 화면 이미지는 보관하지 않는다. 두 필터를 함께 준비해 옵션 변경도 재조회 없이 반영한다.
    private struct DisplayFilters {
        let includingApp: SCContentFilter
        let excludingApp: SCContentFilter
    }
    private static var displayFilters: [CGDirectDisplayID: DisplayFilters] = [:]
    private static var excludesOwnApplication = false
    private static var preparation: Task<Void, Error>?
    private static var generation = UUID()

    /// 권한이 이미 있으면 앱 시작 시 목록 조회를 미리 끝낸다. 화면 캡처나 권한 요청은 하지 않는다.
    static func prepare() {
        guard ScreenRecordingPermission.isGranted else { return }
        Task { try? await prepareFilters() }
    }

    /// 화면 구성 변경·잠자기 복귀 시 이전 디스플레이 객체를 폐기한다.
    static func invalidate() {
        generation = UUID()
        preparation?.cancel()
        preparation = nil
        displayFilters.removeAll()
        excludesOwnApplication = false
    }

    private static func prepareFilters() async throws {
        while displayFilters.isEmpty {
            let currentGeneration = generation
            let task: Task<Void, Error>
            if let preparation {
                task = preparation
            } else {
                task = Task {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    try Task.checkCancellation()
                    guard generation == currentGeneration else { return }
                    let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                    excludesOwnApplication = !ownApps.isEmpty
                    guard !content.displays.isEmpty else { throw CaptureError.noDisplay }
                    displayFilters = Dictionary(uniqueKeysWithValues: content.displays.map {
                        ($0.displayID, DisplayFilters(
                            includingApp: SCContentFilter(display: $0, excludingApplications: [], exceptingWindows: []),
                            excludingApp: SCContentFilter(display: $0, excludingApplications: ownApps, exceptingWindows: [])
                        ))
                    })
                }
                preparation = task
            }
            do {
                try await task.value
            } catch {
                // 준비 도중 화면 구성이 바뀌었으면 새 조회에 합류한다.
                if generation != currentGeneration { continue }
                preparation = nil
                throw error
            }
            if generation == currentGeneration { preparation = nil }
        }
    }

    /// 지정한 화면들(기본: 모든 화면)을 동시에 캡처한다. 커서는 제외하고 자기 앱 창은 옵션에 따른다.
    /// 오래된 필터로 실패하면 목록을 새로 읽고 한 번만 재시도한다.
    static func capture(screens: [NSScreen] = NSScreen.screens, includeAppWindows: Bool = false) async throws -> [ScreenShot] {
        do {
            return try await captureDisplays(screens: screens, includeAppWindows: includeAppWindows)
        } catch {
            invalidate()
            try Task.checkCancellation()
            return try await captureDisplays(screens: screens, includeAppWindows: includeAppWindows)
        }
    }

    private static func captureDisplays(screens: [NSScreen], includeAppWindows: Bool) async throws -> [ScreenShot] {
        let started = ContinuousClock.now
        // 창이 없을 때 자기 앱이 목록에서 빠질 수 있다. 그런 필터는 이후 열린 에디터를
        // 제외하지 못하므로 다음 캡처에서 목록을 다시 확인한다.
        if !includeAppWindows && !excludesOwnApplication { displayFilters.removeAll() }
        try await prepareFilters()
        let contentTime = ContinuousClock.now - started

        let jobs: [(CGDirectDisplayID, SCContentFilter, SCStreamConfiguration)] = screens.compactMap { screen in
            guard let id = screen.displayID, let filters = displayFilters[id] else { return nil }
            let filter = includeAppWindows ? filters.includingApp : filters.excludingApp
            let config = SCStreamConfiguration()
            let pixelScale = CGFloat(filter.pointPixelScale)
            config.width = Int((filter.contentRect.width * pixelScale).rounded())
            config.height = Int((filter.contentRect.height * pixelScale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            return (id, filter, config)
        }
        guard !jobs.isEmpty, jobs.count == screens.count else { throw CaptureError.noDisplay }

        let images = try await withThrowingTaskGroup(of: (CGDirectDisplayID, SendableImage).self) { group in
            for (id, filter, config) in jobs {
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (id, SendableImage(image))
                }
            }
            var result: [CGDirectDisplayID: CGImage] = [:]
            for try await (id, image) in group {
                result[id] = image.cgImage
            }
            return result
        }

        let shots = screens.compactMap { screen in
            screen.displayID.flatMap { images[$0] }.map { ScreenShot(screen: screen, image: $0) }
        }
        let total = ContinuousClock.now - started
        Log.capture.info("캡처 \(shots.count)개 디스플레이: content \(contentTime.milliseconds, format: .fixed(precision: 1))ms, 전체 \(total.milliseconds, format: .fixed(precision: 1))ms")
        return shots
    }

    /// 창 그림자가 창 밖으로 퍼지는 최대 거리보다 넉넉한 여유 (포인트)
    private static let shadowPadding: CGFloat = 150

    /// 창 하나를 다른 창에 가려지지 않은 상태로 네이티브 해상도로 캡처한다
    /// 배경은 투명하고, includeShadow면 창 그림자를 포함한다. 배율은 창이 있는 디스플레이 기준
    static func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> (image: CGImage, scale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = !includeShadow
        config.shouldBeOpaque = false
        if includeShadow {
            // 출력 크기가 창 크기면 그림자까지 넣으려고 창을 줄인다. 그림자 여유를 두고 확대 없이 받은 뒤 투명 가장자리를 잘라낸다
            config.width = Int(((filter.contentRect.width + shadowPadding * 2) * scale).rounded())
            config.height = Int(((filter.contentRect.height + shadowPadding * 2) * scale).rounded())
            config.scalesToFit = false
        }
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let raw = CGSize(width: image.width, height: image.height)
        if includeShadow, let visible = ImageSampler.visibleBounds(of: image), let trimmed = image.cropping(to: visible) {
            image = trimmed
        }
        Log.capture.info("창 캡처 \(id): \(Int(raw.width))×\(Int(raw.height)) → \(image.width)×\(image.height), contentRect \(filter.contentRect.debugDescription, privacy: .public), 그림자 \(includeShadow)")
        return (image, scale)
    }
}
