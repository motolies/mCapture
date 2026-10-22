import CoreGraphics

/// 창을 화면 사용 영역 가운데에 두는 계산. AppKit 전역 좌표(왼쪽 아래 원점, 위쪽이 maxY)
/// 자기 창(NSWindow)과 다른 앱 창(손쉬운 사용 API)이 같은 계산을 써서 결과가 같다
public enum WindowCentering {
    /// 사용 영역보다 큰 창을 다루는 방법
    public enum OversizePolicy: Sendable {
        /// 넘치는 축을 사용 영역 크기로 줄인다
        case shrinkToFit
        /// 크기는 두고 왼쪽·위 변을 영역에 맞춘다 (제목 막대가 보이게)
        case keepSize
    }

    /// 크기는 유지하고(정책에 따라 줄이고) 원점은 정수로 반올림한다. 같은 입력에 두 번 적용해도 결과가 같다
    /// 축마다 따로 본다: 폭만 넘치면 폭만 줄이거나 왼쪽에 맞추고 세로는 가운데
    public static func frame(centering window: CGRect, in area: CGRect, oversize: OversizePolicy) -> CGRect {
        var size = window.size
        if oversize == .shrinkToFit {
            size.width = min(size.width, area.width.rounded(.down))
            size.height = min(size.height, area.height.rounded(.down))
        }
        let x = size.width <= area.width ? area.midX - size.width / 2 : area.minX
        let y = size.height <= area.height ? area.midY - size.height / 2 : area.maxY - size.height
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
