import AppKit
import MCaptureCore

/// 캡처 → 선택 → 캡처 후 동작(복사·저장·에디터)까지의 흐름을 조정한다
@MainActor
final class CaptureCoordinator {
    private let preferences: Preferences
    private let exporter: Exporter
    private var isCapturing = false
    private var editors: [EditorWindowController] = []
    private var pins: [PinPanel] = []

    init(preferences: Preferences, exporter: Exporter) {
        self.preferences = preferences
        self.exporter = exporter
    }

    /// 모든 디스플레이를 멈춘 상태로 보여주고 영역을 고른다
    func captureArea() {
        run {
            guard let result = try await self.select(opensEditor: self.preferences.afterCaptureOpenEditor) else { return }
            try await self.deliver(result)
        }
    }

    /// 커서 아래 창을 강조하고 클릭한 창을 캡처한다. 드래그하면 영역 캡처와 같다
    func captureWindow() {
        run {
            guard let result = try await self.select(opensEditor: self.preferences.afterCaptureOpenEditor, windowMode: true) else { return }
            try await self.deliver(result)
        }
    }

    /// 커서가 있는 디스플레이 전체를 캡처한다
    func captureFullscreen() {
        run {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let screen = NSScreen.underMouse, let shot = try await ScreenCapturer.capture(screens: [screen]).first else {
                throw CaptureError.noDisplay
            }
            self.deliver(CaptureDocument(image: shot.image, scale: shot.scale, sourceAppName: appName), screen: screen)
        }
    }

    /// 고른 영역의 텍스트(QR 코드가 있으면 그 내용)를 인식해 클립보드에 복사한다
    func recognizeText() {
        run {
            guard let result = try await self.select(opensEditor: false) else { return }
            let image = result.rect.flatMap { result.shot.image.cropping(to: $0) } ?? result.shot.image
            let screen = result.shot.screen
            // 첫 인식은 시스템이 모델을 읽느라 오래 걸릴 수 있어, 늦어지면 진행 중임을 알린다
            let notice = Task {
                try await Task.sleep(for: .milliseconds(400))
                ToastPanel.show("텍스트 인식 중…", systemImage: "text.viewfinder", on: screen)
            }
            defer { notice.cancel() }
            let recognized = try await TextRecognizer.recognize(SendableImage(image))
            notice.cancel()

            guard let text = TextRecognizer.clipboardText(recognized, joinLines: self.preferences.ocrJoinLines) else {
                ToastPanel.show("인식된 텍스트가 없습니다", systemImage: "exclamationmark.triangle.fill", on: screen)
                return
            }
            self.exporter.copy(text: text)
            let kind = recognized.barcodes.isEmpty ? "텍스트" : "QR"
            ToastPanel.show("\(kind) 복사됨 · \(Self.preview(text))", on: screen)
        }
    }

    // 토스트에 보일 첫 줄 앞부분
    private static func preview(_ text: String, limit: Int = 30) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        return firstLine.count > limit ? firstLine.prefix(limit) + "…" : firstLine
    }

    /// 이미지 파일을 에디터로 연다. DPI 정보로 Retina 배율을 추정한다
    func open(fileURL: URL) {
        guard let loaded = ImageLoader.load(url: fileURL) else {
            ToastPanel.show("이미지를 열 수 없습니다: \(fileURL.lastPathComponent)", systemImage: "xmark.octagon.fill")
            return
        }
        openEditor(CaptureDocument(image: loaded.image, scale: loaded.scale), screen: nil)
    }

    /// 파일 선택 창으로 이미지를 골라 각각 에디터로 연다
    func openWithPanel() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = preferences.saveFolder
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open(fileURL:))
    }

    /// 모든 디스플레이를 멈춘 화면 위에서 고르게 한다. 확대경 색상(Tab)은 여기서 복사하고 nil을 돌려준다
    /// 결과로 에디터를 열지 않으면 캡처 전에 쓰던 앱으로 포커스를 돌려준다
    /// windowMode면 멈춘 화면과 같은 순간의 창 목록으로 창을 고르게 한다
    private func select(opensEditor: Bool, windowMode: Bool = false) async throws -> SelectionResult? {
        let started = ContinuousClock.now
        let previousApp = NSWorkspace.shared.frontmostApplication
        let windows = windowMode ? WindowList.onScreen() : []
        let shots = try await ScreenCapturer.capture()
        let overlay = SelectionOverlayController(shots: shots, windows: windows)
        Log.capture.info("오버레이 표시까지 \((ContinuousClock.now - started).milliseconds, format: .fixed(precision: 1))ms")
        var result = await overlay.run()
        if case .window(let id) = result?.pick {
            result?.appName = windows.first { $0.id == id }?.ownerName
        } else {
            result?.appName = previousApp?.localizedName
        }

        var color: String?
        if case .color(let hex) = result?.pick { color = hex }
        if result == nil || color != nil || !opensEditor,
           previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        // 토스트는 오버레이보다 낮은 레벨이라 오버레이가 닫힌 뒤에 띄운다
        if let color {
            exporter.copy(text: color)
            ToastPanel.show("\(color) 복사됨", on: result?.shot.screen)
            return nil
        }
        return result
    }

    // 권한 확인, 중복 실행 방지, 오류 알림을 공통 처리한다
    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isCapturing else { return }
        guard ScreenRecordingPermission.ensureGranted() else { return }
        isCapturing = true
        Task {
            do {
                try await body()
            } catch {
                Log.capture.error("캡처 실패: \(error.localizedDescription, privacy: .public)")
                ToastPanel.show("캡처 실패: \(error.localizedDescription)", systemImage: "xmark.octagon.fill")
            }
            isCapturing = false
        }
    }

    // 고른 창은 그 창만 다시 캡처하고, 영역·디스플레이는 멈춘 화면을 크롭한다
    private func deliver(_ result: SelectionResult) async throws {
        if case .window(let id) = result.pick {
            let shot = try await ScreenCapturer.captureWindow(id: id, includeShadow: preferences.windowShadow)
            deliver(CaptureDocument(image: shot.image, scale: shot.scale, sourceAppName: result.appName), screen: result.shot.screen)
        } else {
            let document = CaptureDocument(
                image: result.shot.image, scale: result.shot.scale, state: EditState(crop: result.rect), sourceAppName: result.appName
            )
            deliver(document, screen: result.shot.screen)
        }
    }

    #if DEBUG
    /// 개발용: 창 하나를 캡처해 PNG로 쓴다 (그림자 켜기·끄기 결과 비교)
    func debugCaptureWindow(id: CGWindowID, shadow: Bool, to url: URL) {
        Task {
            do {
                let shot = try await ScreenCapturer.captureWindow(id: id, includeShadow: shadow)
                try ImageEncoder.pngData(shot.image, scale: shot.scale)?.write(to: url)
            } catch {
                Log.capture.error("창 캡처 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif

    /// 설정에 따라 에디터를 열고, 복사·저장은 백그라운드 인코딩 후 처리한다
    private func deliver(_ document: CaptureDocument, screen: NSScreen) {
        let editor = preferences.afterCaptureOpenEditor ? openEditor(document, screen: screen) : nil
        let copy = preferences.afterCaptureCopy
        let save = preferences.afterCaptureSave
        guard copy || save, let image = DocumentRenderer.render(image: document.image, state: document.state, scale: document.scale) else { return }

        Task { [exporter] in
            if let url = await exporter.export(
                image, scale: document.scale, copy: copy, save: save, overwriting: nil, appName: document.sourceAppName, screen: screen
            ) {
                editor?.documentSaved(at: url)
            }
        }
    }

    /// 문서를 화면에 고정한다. 핀은 Dock 아이콘(활성화 정책)에 영향을 주지 않는다
    func pin(_ document: CaptureDocument, screen: NSScreen?) {
        guard let image = DocumentRenderer.render(image: document.image, state: document.state, scale: document.scale) else {
            ToastPanel.show("이미지 변환 실패", systemImage: "xmark.octagon.fill")
            return
        }
        let pin = PinPanel(document: document, image: image, exporter: exporter, screen: screen)
        pin.onClose = { [weak self] closed in self?.pins.removeAll { $0 === closed } }
        pin.onEdit = { [weak self] document, screen in self?.openEditor(document, screen: screen) }
        pins.append(pin)
        pin.orderFrontRegardless()
    }

    @discardableResult
    private func openEditor(_ document: CaptureDocument, screen: NSScreen?) -> EditorWindowController {
        let editor = EditorWindowController(
            document: document, preferences: preferences, exporter: exporter, screen: screen, avoiding: editors.compactMap(\.window)
        )
        editor.onClose = { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
            self?.updateActivationPolicy()
        }
        editor.onOpenFiles = { [weak self] urls in urls.forEach { self?.open(fileURL: $0) } }
        editor.onPin = { [weak self] document, screen in self?.pin(document, screen: screen) }
        editors.append(editor)
        updateActivationPolicy()
        NSApp.activate()
        editor.present()
        return editor
    }

    /// 에디터가 열려 있을 때만 Dock 아이콘과 메뉴 막대를 보인다
    private func updateActivationPolicy() {
        NSApp.setActivationPolicy(editors.isEmpty ? .accessory : .regular)
    }
}
