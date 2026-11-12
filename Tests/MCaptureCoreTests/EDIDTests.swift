import Foundation
import Testing
@testable import MCaptureCore

/// 회의실 TV에서 실측한 EDID (256바이트: 기본 블록 + CTA 확장 블록 1개)
private let sampleEDID: [UInt8] = Array(Data(base64Encoded: """
AP///////wAebQEAAQEBAQEeAQTFi054Ou6Ro1RMmSYPUFShCAAxQEVAYUBxQIGA0cABAQEBCOgAMPJwWoCwWIoAchBTAAAeAjqAGHE4LUBYLEUAchBTAAAeAAAA\
/QAYeB6HPAAKICAgICAgAAAA/ABMRyBUViBTU0NSCiAgAYkCAy/0WGFgEB9mZQQTAwISICEiAV1eX2JjZD9ATiMJVwfiAM/jBcAA4wYNAeIPAwI6gBhxOC1AWCxF\
AHIQUwAAHgR0ADDycFqAsFiKAHIQUwAAHmYhULBRABswQHA2AHIQUwAAHlZeAKCgoClQMCA1AHIQUwAAHgAAAAAAAAAAxQ==
""")!)

/// 블록의 마지막 바이트(체크섬)를 다시 계산해 합이 256의 배수가 되게 한다
private func fixingChecksum(_ block: [UInt8]) -> [UInt8] {
    var block = block
    let sum = block.dropLast().reduce(0) { ($0 + Int($1)) % 256 }
    block[block.count - 1] = UInt8((256 - sum) % 256)
    return block
}

/// 실측한 변환 어댑터를 흉내 낸 읽기 대상.
/// 16바이트를 요청하면 요청한 위치와 상관없이 아무 조각이나 돌려주고, 더 작게 요청하면 요청한 위치를 지킨다
private final class ScrambledAdapter {
    private let bytes: [UInt8]
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    /// true인 차례의 호출은 실패한다 (호출 순번 기준). 간헐적인 읽기 실패를 흉내 낸다
    var failingCalls: Set<Int> = []
    private(set) var callCount = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    // 시험마다 같은 순서가 나오도록 고정된 씨앗의 선형 합동 난수를 쓴다
    private func nextRow() -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(seed >> 33) % (bytes.count / 16)
    }

    func read(offset: Int, length: Int) -> [UInt8]? {
        callCount += 1
        if failingCalls.contains(callCount) { return nil }
        guard length >= 16 else { return Array(bytes[offset..<offset + length]) }
        let row = nextRow()
        return Array(bytes[row * 16..<row * 16 + 16])
    }
}

@Suite("EDID")
struct EDIDTests {
    @Test func 실측한_EDID는_검증을_통과하고_이름과_권장_해상도를_알려준다() throws {
        let edid = try #require(EDID(validating: sampleEDID))
        #expect(edid.displayName == "LG TV SSCR")
        let mode = try #require(edid.preferredMode)
        #expect(mode.width == 3840)
        #expect(mode.height == 2160)
        #expect(abs(mode.refreshRate - 60) < 0.01)
    }

    @Test func 헤더나_체크섬이_틀리면_거부한다() {
        var brokenHeader = sampleEDID
        brokenHeader[1] = 0x00
        #expect(EDID(validating: brokenHeader) == nil)

        var brokenBase = sampleEDID
        brokenBase[20] ^= 0x01
        #expect(EDID(validating: brokenBase) == nil)

        var brokenExtension = sampleEDID
        brokenExtension[200] ^= 0x01
        #expect(EDID(validating: brokenExtension) == nil)
    }

    @Test func 확장_블록_수와_길이가_다르면_거부한다() {
        // 기본 블록은 확장 블록 1개를 알리는데 기본 블록만 있는 경우
        #expect(EDID(validating: Array(sampleEDID.prefix(128))) == nil)
        #expect(EDID(validating: []) == nil)
    }

    @Test func 확장_블록이_없는_EDID도_받아들인다() throws {
        var base = Array(sampleEDID.prefix(128))
        base[126] = 0
        let edid = try #require(EDID(validating: fixingChecksum(base)))
        #expect(edid.bytes.count == 128)
        #expect(edid.displayName == "LG TV SSCR")
    }

    @Test func 조각_순서가_뒤섞여도_체크섬은_통과하므로_헤더로_걸러진다() {
        // 기본 블록의 0번·1번 조각을 맞바꾼다. 합은 그대로지만 헤더가 맨 앞에 없다
        var swapped = sampleEDID
        swapped.replaceSubrange(0..<16, with: sampleEDID[16..<32])
        swapped.replaceSubrange(16..<32, with: sampleEDID[0..<16])
        #expect(EDID.checksumValid(swapped[0..<128]))
        #expect(EDID(validating: swapped) == nil)
    }
}

@Suite("EDIDReader")
struct EDIDReaderTests {
    @Test func 뒤섞여_읽히는_어댑터에서도_작은_단위로_읽어_원본을_얻는다() {
        let adapter = ScrambledAdapter(sampleEDID)
        let result = EDIDReader.readTrusted(from: adapter.read)
        #expect(result == .success(EDID(validating: sampleEDID)!))
    }

    @Test func 열여섯_바이트_단위로만_읽으면_실패한다() {
        let adapter = ScrambledAdapter(sampleEDID)
        let result = EDIDReader.readTrusted(from: adapter.read, chunkPlan: [16, 16, 16, 16, 16, 16])
        #expect(result == .failure(.unreadable))
    }

    @Test func 검증을_한_번만_통과하면_믿지_않는다() {
        let adapter = ScrambledAdapter(sampleEDID)
        #expect(EDIDReader.readTrusted(from: adapter.read, chunkPlan: [8]) == .failure(.unreadable))
        #expect(EDIDReader.readTrusted(from: adapter.read, chunkPlan: [8, 16, 16]) == .failure(.unreadable))
    }

    @Test func 간헐적으로_실패해도_같은_결과가_두_번_나오면_성공한다() {
        let adapter = ScrambledAdapter(sampleEDID)
        // 8바이트 단위로 256바이트를 읽으면 시도당 32번 호출한다. 둘째·셋째 시도의 첫 호출을 실패시킨다
        adapter.failingCalls = [33, 34]
        var pauses = 0
        let result = EDIDReader.readTrusted(from: adapter.read, chunkPlan: [8, 8, 8, 8], pause: { pauses += 1 })
        #expect(result == .success(EDID(validating: sampleEDID)!))
        // 첫 시도 성공, 둘째·셋째 실패, 넷째에서 일치. 시도 사이마다 한 번씩 쉰다
        #expect(pauses == 3)
    }

    @Test func 서로_다른_결과가_한_번씩_나오면_두_번_나온_쪽을_고른다() {
        // 첫 시도만 다른(그러나 검증은 통과하는) 내용을 돌려주는 대상
        var other = sampleEDID
        other[100] = other[100] &+ 1
        let otherBase = fixingChecksum(Array(other.prefix(128)))
        let altered = otherBase + Array(sampleEDID.suffix(128))
        var attempt = 0
        var lastOffset = Int.max
        let source: EDIDReader.Source = { offset, length in
            // 위치가 0으로 돌아오면 새 시도가 시작된 것이다
            if offset < lastOffset, offset == 0 { attempt += 1 }
            lastOffset = offset
            let bytes = attempt == 1 ? altered : sampleEDID
            return Array(bytes[offset..<offset + length])
        }
        let result = EDIDReader.readTrusted(from: source, chunkPlan: [8, 8, 8])
        #expect(result == .success(EDID(validating: sampleEDID)!))
    }

    @Test func 확장_블록이_많으면_지원하지_않는다고_알린다() {
        var base = Array(sampleEDID.prefix(128))
        base[126] = 3
        let bytes = fixingChecksum(base) + Array(sampleEDID.suffix(128))
        let source: EDIDReader.Source = { offset, length in Array(bytes[offset..<offset + length]) }
        #expect(EDIDReader.readTrusted(from: source) == .failure(.unsupportedExtensionCount(3)))
    }

    @Test func 읽기가_계속_실패하면_읽을_수_없다고_알린다() {
        let source: EDIDReader.Source = { _, _ in nil }
        #expect(EDIDReader.readTrusted(from: source) == .failure(.unreadable))
    }
}
