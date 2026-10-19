import Foundation

/// 파일 찾기의 한글 처리: NFC 정규화, 초성 판별, 조합 중 음절 비교
/// macOS 파일 이름은 한글이 자모로 풀린(NFD) 채 저장된 경우가 많아 이름과 검색어를 모두 NFC로 맞춘다
public enum HangulText {
    /// 완성형 음절 범위 (가 ~ 힣)
    static let syllableFirst: UInt32 = 0xAC00
    static let syllableLast: UInt32 = 0xD7A3
    /// 초성 하나가 차지하는 음절 수 (중성 21 × 종성 28)
    static let syllablesPerChoseong: UInt32 = 588
    /// 종성 개수 (받침 없음 포함)
    static let jongseongCount: UInt32 = 28

    /// 초성으로 쓰이는 호환 자모 19개의 코드 포인트 (ㄱ ㄲ ㄴ ㄷ ㄸ ㄹ ㅁ ㅂ ㅃ ㅅ ㅆ ㅇ ㅈ ㅉ ㅊ ㅋ ㅌ ㅍ ㅎ)
    static let choseongJamo: [UInt32] = [
        0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142, 0x3143, 0x3145,
        0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B, 0x314C, 0x314D, 0x314E,
    ]

    /// NFC로 정규화한다. ASCII만 있으면 변환 없이 그대로 돌려준다
    public static func nfc(_ text: String) -> String {
        text.utf8.allSatisfy { $0 < 0x80 } ? text : text.precomposedStringWithCanonicalMapping
    }

    /// 완성형 음절인지
    @inline(__always)
    public static func isSyllable(_ scalar: UInt32) -> Bool {
        scalar &- syllableFirst <= syllableLast - syllableFirst
    }

    /// 호환 자모 자음의 초성 번호(0~18). 받침에만 쓰는 자모(ㄳ 등)나 자모가 아니면 nil
    public static func choseongIndex(jamo scalar: UInt32) -> Int? {
        choseongJamo.firstIndex(of: scalar)
    }

    /// 완성형 음절의 초성 번호(0~18). 음절이 아니면 nil
    @inline(__always)
    public static func choseongIndex(syllable scalar: UInt32) -> Int? {
        isSyllable(scalar) ? Int((scalar - syllableFirst) / syllablesPerChoseong) : nil
    }

    /// 받침 없는 음절인지 (조합 중 마지막 글자를 초성+중성으로만 비교할 때 쓴다)
    public static func hasNoJongseong(_ scalar: UInt32) -> Bool {
        isSyllable(scalar) && (scalar - syllableFirst) % jongseongCount == 0
    }

    /// 음절의 초성+중성 번호 (받침을 무시한 비교용). 음절이 아니면 nil
    @inline(__always)
    public static func choseongJungseong(_ scalar: UInt32) -> UInt32? {
        isSyllable(scalar) ? (scalar - syllableFirst) / jongseongCount : nil
    }

    /// 문자열의 음절을 초성으로 바꾼다 (예: "한글.txt" → "ㅎㄱ.txt"). 음절이 아닌 글자는 그대로 둔다
    public static func choseong(of text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in nfc(text).unicodeScalars {
            if let index = choseongIndex(syllable: scalar.value), let jamo = Unicode.Scalar(choseongJamo[index]) {
                result.append(jamo)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}
