import CoreGraphics
import Foundation

/// 실행 취소 단위가 되는 편집 상태. 원본 이미지는 포함하지 않는다
public struct EditState: Equatable, Sendable {
    /// 이미지 픽셀 좌표의 크롭 영역. nil이면 이미지 전체
    public var crop: CGRect?
    /// 배열 순서가 곧 레이어 순서 (뒤가 위)
    public var annotations: [Annotation]

    public init(crop: CGRect? = nil, annotations: [Annotation] = []) {
        self.crop = crop
        self.annotations = annotations
    }

    /// 화면과 내보내기에 쓰는 영역 (크롭 또는 이미지 전체)
    public func visibleRect(imageBounds: CGRect) -> CGRect {
        crop ?? imageBounds
    }

    /// 새 카운터 번호. 지금 있는 카운터 중 가장 큰 번호 + 1 (지워도 번호를 다시 매기지 않는다)
    public var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.shape { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    public func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// id에 해당하는 주석을 교체한다. 없으면 아무것도 하지 않는다
    public mutating func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    public mutating func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// 여러 주석을 한꺼번에 지운다
    public mutating func remove(ids: Set<UUID>) {
        annotations.removeAll { ids.contains($0.id) }
    }

    /// 주석을 추가한다. 베이스 레이어(이미지 등)는 일반 주석 아래에서 맨 위, 일반 주석은 전체 맨 위에 둔다
    public mutating func add(_ annotation: Annotation) {
        if annotation.isBaseLayer {
            let index = annotations.lastIndex(where: \.isBaseLayer).map { $0 + 1 } ?? 0
            annotations.insert(annotation, at: index)
        } else {
            annotations.append(annotation)
        }
    }

    /// 주석을 같은 레이어 그룹의 맨 위로 옮긴다 (선택한 주석이 가려지지 않게)
    /// 베이스 레이어는 일반 주석 위로 올라가지 않는다
    public mutating func bringToFront(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        add(annotations.remove(at: index))
    }
}

/// 캡처 한 건. 원본 이미지는 불변이고 편집 상태만 바뀐다
public struct CaptureDocument {
    public let image: CGImage
    /// Retina 배율 (이미지 픽셀 / 논리 포인트)
    public let scale: CGFloat
    public var state: EditState
    /// 마지막으로 저장한 파일. 같은 캡처는 이 파일에 덮어쓴다
    public var savedURL: URL?
    /// 캡처한 앱 이름 (파일 이름 {app}). 파일에서 열었으면 nil
    public var sourceAppName: String?

    public init(image: CGImage, scale: CGFloat, state: EditState = EditState(), savedURL: URL? = nil, sourceAppName: String? = nil) {
        self.image = image
        self.scale = max(scale, 1)
        self.state = state
        self.savedURL = savedURL
        self.sourceAppName = sourceAppName
    }

    public var imageBounds: CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    public var visibleRect: CGRect {
        state.visibleRect(imageBounds: imageBounds)
    }
}

/// 스레드 사이로 CGImage를 넘기기 위한 래퍼. CGImage는 생성 후 불변이라 안전하다
public struct SendableImage: @unchecked Sendable, Equatable {
    public let cgImage: CGImage

    public init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }

    /// 같은 이미지 객체인지로 비교한다. 이미지는 불변이라 픽셀까지 비교할 필요가 없다 (실행 취소 비교용)
    public static func == (lhs: SendableImage, rhs: SendableImage) -> Bool {
        lhs.cgImage === rhs.cgImage
    }
}
