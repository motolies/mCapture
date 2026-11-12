import Foundation

/// 디스플레이가 자신의 이름과 지원 해상도를 알리는 정보(EDID). 128바이트 블록이 이어진 형태다
public struct EDID: Equatable, Sendable {
    /// 블록 하나의 크기
    public static let blockSize = 128
    /// 기본 블록 맨 앞의 고정 헤더
    static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    /// 기본 블록에서 확장 블록 수가 적힌 위치
    private static let extensionCountOffset = 126
    /// 기본 블록의 설명자 네 개 위치와 크기
    private static let descriptorOffsets = [54, 72, 90, 108]
    private static let descriptorSize = 18
    /// 이름 설명자 표시
    private static let nameTag: UInt8 = 0xFC

    /// 해상도와 주사율
    public struct Mode: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let refreshRate: Double

        public init(width: Int, height: Int, refreshRate: Double) {
            self.width = width
            self.height = height
            self.refreshRate = refreshRate
        }
    }

    public let bytes: [UInt8]

    /// 헤더, 블록 수, 블록마다의 체크섬이 모두 맞을 때만 만든다
    public init?(validating bytes: [UInt8]) {
        guard let extensions = EDID.extensionCount(ofBaseBlock: Array(bytes.prefix(EDID.blockSize))),
              bytes.count == (extensions + 1) * EDID.blockSize
        else { return nil }
        for start in stride(from: EDID.blockSize, to: bytes.count, by: EDID.blockSize) {
            guard EDID.checksumValid(bytes[start..<start + EDID.blockSize]) else { return nil }
        }
        self.bytes = bytes
    }

    /// 기본 블록이 유효하면(헤더·체크섬) 뒤따르는 확장 블록 수를 돌려준다. 유효하지 않으면 nil
    public static func extensionCount(ofBaseBlock block: [UInt8]) -> Int? {
        guard block.count == blockSize, Array(block[0..<header.count]) == header, checksumValid(block[...]) else { return nil }
        return Int(block[extensionCountOffset])
    }

    /// 블록의 모든 바이트 합이 256의 배수면 유효하다.
    /// 조각 순서가 바뀌어도 합은 같으므로 이 검사만으로는 순서가 맞는지 알 수 없다
    static func checksumValid(_ block: ArraySlice<UInt8>) -> Bool {
        block.count == blockSize && block.reduce(0) { ($0 + Int($1)) % 256 } == 0
    }

    /// 디스플레이 이름. 이름 설명자가 없으면 nil
    public var displayName: String? {
        for descriptor in descriptors where descriptor[0] == 0 && descriptor[1] == 0 && descriptor[3] == EDID.nameTag {
            // 이름은 5번째 바이트부터이고 줄바꿈(0x0A)으로 끝난 뒤 공백으로 채워진다
            let text = descriptor[5...].prefix { $0 != 0x0A }
            let name = String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// 디스플레이가 권장하는 해상도(첫 번째 상세 타이밍). 없으면 nil
    public var preferredMode: Mode? {
        for descriptor in descriptors where descriptor[0] != 0 || descriptor[1] != 0 {
            // 픽셀 클럭은 10kHz 단위. 가로·세로 값은 아래 8비트와 위 4비트가 따로 들어 있다
            let pixelClock = Double(Int(descriptor[0]) | Int(descriptor[1]) << 8) * 10_000
            let width = Int(descriptor[2]) | (Int(descriptor[4]) >> 4) << 8
            let horizontalBlank = Int(descriptor[3]) | (Int(descriptor[4]) & 0x0F) << 8
            let height = Int(descriptor[5]) | (Int(descriptor[7]) >> 4) << 8
            let verticalBlank = Int(descriptor[6]) | (Int(descriptor[7]) & 0x0F) << 8
            let total = (width + horizontalBlank) * (height + verticalBlank)
            guard width > 0, height > 0, total > 0 else { continue }
            return Mode(width: width, height: height, refreshRate: pixelClock / Double(total))
        }
        return nil
    }

    /// 기본 블록의 18바이트 설명자 네 개
    private var descriptors: [[UInt8]] {
        EDID.descriptorOffsets.map { Array(bytes[$0..<$0 + EDID.descriptorSize]) }
    }
}
