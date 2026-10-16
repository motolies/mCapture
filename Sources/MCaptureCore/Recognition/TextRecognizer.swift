import CoreGraphics
import Foundation
import Vision

/// 이미지에서 읽은 텍스트 줄과 바코드(QR 등) 내용
public struct RecognitionResult: Equatable, Sendable {
    public var lines: [String]
    public var barcodes: [String]

    public init(lines: [String] = [], barcodes: [String] = []) {
        self.lines = lines
        self.barcodes = barcodes
    }
}

/// Vision으로 텍스트(한국어·영어)와 바코드를 인식한다
public enum TextRecognizer {
    /// 텍스트 인식과 바코드 검출을 동시에 실행한다
    public static func recognize(_ image: SendableImage) async throws -> RecognitionResult {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = [Locale.Language(identifier: "ko-KR"), Locale.Language(identifier: "en-US")]
        textRequest.usesLanguageCorrection = true
        let barcodeRequest = DetectBarcodesRequest()

        async let text = textRequest.perform(on: image.cgImage)
        async let barcodes = barcodeRequest.perform(on: image.cgImage)
        return try await RecognitionResult(
            lines: text.compactMap { $0.topCandidates(1).first?.string },
            barcodes: barcodes.compactMap(\.payloadString)
        )
    }

    /// 클립보드에 넣을 문자열. QR 등 바코드가 있으면 그 내용만 쓴다 (바코드 주변 글자 인식 결과는 쓸모가 없다)
    /// joinLines면 줄바꿈을 공백으로 바꾸고, 어느 쪽이든 이중 공백을 하나로 줄인다. 아무것도 없으면 nil
    public static func clipboardText(_ result: RecognitionResult, joinLines: Bool) -> String? {
        let lines = (result.barcodes.isEmpty ? result.lines : result.barcodes)
            .map { collapseSpaces($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        // 바코드 내용(URL 등)은 이어 붙이면 깨지므로 줄 단위를 유지한다
        return joinLines && result.barcodes.isEmpty ? lines.joined(separator: " ") : lines.joined(separator: "\n")
    }

    // 연속된 공백을 하나로 줄인다
    private static func collapseSpaces(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
