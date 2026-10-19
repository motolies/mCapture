import Foundation

/// 파일 찾기 인덱스를 디스크에 저장하는 이진 형식 (앱을 다시 시작할 때 빠르게 복구)
///
/// 리틀엔디언. 자식·형제 연결은 저장하지 않고 로드할 때 parents로 다시 만든다
/// ```
/// "MCFI" · version(UInt32) · configHash(UInt64) · lastEventId(UInt64) · savedAt(Float64)
/// deviceUUID 개수(UInt16) + [길이(UInt8) + UTF-8]
/// entryCount(UInt32) · nameBytes(UInt32)
/// names[UInt8] · nameOffsets[UInt32](count+1) · parents[UInt32] · flags[UInt8]
/// checksum(UInt64, 앞의 모든 바이트의 FNV-1a)
/// ```
public struct FileIndexSnapshot: Sendable {
    public var index: FileIndex
    /// 루트·제외 규칙·숨김 설정의 해시. 다르면 전체를 다시 스캔한다
    public var configHash: UInt64
    /// 마지막으로 반영한 FSEvents 이벤트 ID. 다음 실행 때 여기서부터 기록을 재생한다
    public var lastEventId: UInt64
    /// 루트마다 FSEvents 장치 UUID. 바뀌면 이벤트 ID가 무효라 전체를 다시 스캔한다
    public var deviceUUIDs: [String]
    public var savedAt: Date

    static let magic: [UInt8] = Array("MCFI".utf8)
    static let version: UInt32 = 1

    public init(index: FileIndex, configHash: UInt64, lastEventId: UInt64, deviceUUIDs: [String], savedAt: Date = Date()) {
        self.index = index
        self.configHash = configHash
        self.lastEventId = lastEventId
        self.deviceUUIDs = deviceUUIDs
        self.savedAt = savedAt
    }

    /// 이진 데이터로 만든다
    public func encoded() -> Data {
        var data = Data()
        index.withStorage { names, offsets, parents, flags in
            data.reserveCapacity(64 + names.count + offsets.count * 4 + parents.count * 4 + flags.count)
            data.append(contentsOf: Self.magic)
            Self.append(Self.version, to: &data)
            Self.append(configHash, to: &data)
            Self.append(lastEventId, to: &data)
            Self.append(savedAt.timeIntervalSince1970.bitPattern, to: &data)
            Self.append(UInt16(deviceUUIDs.count), to: &data)
            for uuid in deviceUUIDs {
                let bytes = Array(uuid.utf8.prefix(255))
                data.append(UInt8(bytes.count))
                data.append(contentsOf: bytes)
            }
            Self.append(UInt32(parents.count), to: &data)
            Self.append(UInt32(names.count), to: &data)
            data.append(contentsOf: UnsafeRawBufferPointer(names))
            data.append(contentsOf: UnsafeRawBufferPointer(offsets))
            data.append(contentsOf: UnsafeRawBufferPointer(parents))
            data.append(contentsOf: UnsafeRawBufferPointer(flags))
        }
        let checksum = data.withUnsafeBytes { FNV1a.update(FNV1a.offset, $0) }
        Self.append(checksum, to: &data)
        return data
    }

    /// 이진 데이터를 읽는다. 형식·버전·설정 해시가 다르거나 손상됐으면 nil
    public static func decode(_ data: Data, expectedConfigHash: UInt64) -> FileIndexSnapshot? {
        guard data.count > 12 else { return nil }
        let body = data.prefix(data.count - 8)
        var tail = Reader(data.suffix(8))
        guard let stored = tail.integer(UInt64.self),
              body.withUnsafeBytes({ FNV1a.update(FNV1a.offset, $0) }) == stored
        else { return nil }

        var reader = Reader(body)
        guard reader.bytes(magic.count) == magic,
              reader.integer(UInt32.self) == version,
              let configHash = reader.integer(UInt64.self), configHash == expectedConfigHash,
              let lastEventId = reader.integer(UInt64.self),
              let savedBits = reader.integer(UInt64.self),
              let uuidCount = reader.integer(UInt16.self)
        else { return nil }
        var deviceUUIDs: [String] = []
        for _ in 0..<uuidCount {
            guard let length = reader.integer(UInt8.self), let bytes = reader.bytes(Int(length)) else { return nil }
            deviceUUIDs.append(String(decoding: bytes, as: UTF8.self))
        }
        guard let count = reader.integer(UInt32.self).map(Int.init),
              let nameBytes = reader.integer(UInt32.self).map(Int.init),
              let names: [UInt8] = reader.array(count: nameBytes),
              let offsets: [UInt32] = reader.array(count: count + 1),
              let parents: [UInt32] = reader.array(count: count),
              let flags: [UInt8] = reader.array(count: count),
              reader.isAtEnd,
              let index = FileIndex(names: names, nameOffsets: offsets, parents: parents, flags: flags)
        else { return nil }
        return FileIndexSnapshot(index: index, configHash: configHash, lastEventId: lastEventId,
                                 deviceUUIDs: deviceUUIDs, savedAt: Date(timeIntervalSince1970: Double(bitPattern: savedBits)))
    }

    // 정수를 리틀엔디언으로 붙인다
    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// 앞에서부터 차례로 읽는 도우미. 모자라면 nil
    struct Reader {
        let data: Data
        var offset: Int

        init(_ data: Data) {
            self.data = data
            self.offset = data.startIndex
        }

        var isAtEnd: Bool { offset == data.endIndex }

        // 바이트 n개
        mutating func bytes(_ count: Int) -> [UInt8]? {
            guard count >= 0, data.endIndex - offset >= count else { return nil }
            defer { offset += count }
            return Array(data[offset..<(offset + count)])
        }

        // 리틀엔디언 정수
        mutating func integer<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard data.endIndex - offset >= size else { return nil }
            defer { offset += size }
            var value: T = 0
            _ = withUnsafeMutableBytes(of: &value) { buffer in
                data.copyBytes(to: buffer, from: offset..<(offset + size))
            }
            return T(littleEndian: value)
        }

        // 원소 n개짜리 배열 (호스트가 리틀엔디언이라 그대로 복사한다: Apple Silicon·Intel 모두 해당)
        mutating func array<T: FixedWidthInteger>(count: Int) -> [T]? {
            let size = count * MemoryLayout<T>.stride
            guard count >= 0, data.endIndex - offset >= size else { return nil }
            defer { offset += size }
            return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer), from: offset..<(offset + size))
                initialized = count
            }
        }
    }
}
