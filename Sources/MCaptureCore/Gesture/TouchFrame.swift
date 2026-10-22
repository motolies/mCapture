import Foundation

/// 접촉 상태. MultitouchSupport가 주는 state 값과 같다
public enum TouchPhase: Int32, CaseIterable, Sendable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7

    /// 로그에 쓰는 이름 (문헌과 같은 표기)
    public var name: String {
        switch self {
        case .notTracking: "NotTracking"
        case .startInRange: "StartInRange"
        case .hoverInRange: "HoverInRange"
        case .makeTouch: "MakeTouch"
        case .touching: "Touching"
        case .breakTouch: "BreakTouch"
        case .lingerInRange: "LingerInRange"
        case .outOfRange: "OutOfRange"
        }
    }

    /// 로그의 이름에서 상태를 찾는다
    public init?(name: String) {
        guard let phase = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = phase
    }
}

/// 접촉 하나. 프레임워크의 96바이트 레코드에서 필요한 필드만 값으로 복사한 것
public struct TouchContact: Sendable, Equatable {
    public var timestamp: Double
    public var pathIndex: Int32
    /// 원시 state 값. 모르는 값이 와도 보존한다
    public var state: Int32
    public var fingerID: Int32
    public var x: Float
    public var y: Float
    public var velX: Float
    public var velY: Float
    /// 접촉 크기 (Jitouch의 size). 손바닥·약한 접촉 판정에 쓴다
    public var zTotal: Float
    public var zDensity: Float

    public init(
        timestamp: Double, pathIndex: Int32, state: Int32, fingerID: Int32 = 0,
        x: Float, y: Float, velX: Float = 0, velY: Float = 0, zTotal: Float, zDensity: Float = 0
    ) {
        self.timestamp = timestamp
        self.pathIndex = pathIndex
        self.state = state
        self.fingerID = fingerID
        self.x = x
        self.y = y
        self.velX = velX
        self.velY = velY
        self.zTotal = zTotal
        self.zDensity = zDensity
    }

    /// state를 열거형으로. 모르는 값이면 nil
    public var phase: TouchPhase? { TouchPhase(rawValue: state) }

    /// 로그용 상태 이름. 모르는 값은 "stateN"
    public var stateName: String { phase?.name ?? "state\(state)" }
}

/// 콜백 한 번 = 프레임 하나. 그 순간 센서가 보는 접촉 전부가 들어 있다
public struct TouchFrame: Sendable, Equatable {
    public var timestamp: Double
    public var contacts: [TouchContact]

    public init(timestamp: Double, contacts: [TouchContact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}
