import Foundation

/// 입력 장치 종류. rawValue는 트리거 문자열(`GestureSpec`)에 들어가므로 바꾸지 않는다
public enum InputDeviceKind: String, CaseIterable, Sendable {
    case magicMouse = "mouse"
    case magicTrackpad = "trackpad"
    case builtInTrackpad = "builtin"
    case unknown = "unknown"

    /// 화면 표시용 이름
    public var displayName: String {
        switch self {
        case .magicMouse: "매직마우스"
        case .magicTrackpad: "매직트랙패드"
        case .builtInTrackpad: "내장 트랙패드"
        case .unknown: "알 수 없는 장치"
        }
    }
}

/// MultitouchSupport의 Family ID를 장치 종류로 바꾼다 (Jitouch Gesture.m의 표)
public enum DeviceFamily {
    /// 112가 매직마우스(1·2세대 공통), 128~130이 매직트랙패드, 98~111·113이 내장 트랙패드
    public static func kind(forFamilyID id: Int32) -> InputDeviceKind {
        switch id {
        case 112: .magicMouse
        case 128...130: .magicTrackpad
        case 98...111, 113: .builtInTrackpad
        default: .unknown
        }
    }
}

/// 센서 표면 크기 (mm). 정규화 좌표는 가로:세로 비율이 달라 변위를 mm로 바꿔 분류한다
public struct SurfaceSize: Hashable, Sendable {
    public var widthMM: Double
    public var heightMM: Double

    public init(widthMM: Double, heightMM: Double) {
        self.widthMM = widthMM
        self.heightMM = heightMM
    }

    /// Magic Mouse 2 실측값. 재생처럼 장치 정보가 없을 때의 기본값
    public static let magicMouse2 = SurfaceSize(widthMM: 51.5, heightMM: 90.6)
}

/// 입력 장치 하나의 식별 정보. id는 IORegistry의 Multitouch ID라 블루투스가 끊겼다 붙어도 같다
public struct InputDeviceDescriptor: Hashable, Sendable {
    public var id: UInt64
    public var kind: InputDeviceKind
    public var name: String
    public var surface: SurfaceSize

    public init(id: UInt64, kind: InputDeviceKind, name: String, surface: SurfaceSize) {
        self.id = id
        self.kind = kind
        self.name = name
        self.surface = surface
    }
}

/// 물리 버튼 종류
public enum MouseButton: Hashable, Sendable {
    case left
    case right
    case other(Int)

    /// 화면 표시용 이름
    public var displayName: String {
        switch self {
        case .left: "왼쪽"
        case .right: "오른쪽"
        case .other(let n): "버튼\(n)"
        }
    }
}
