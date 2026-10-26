import AppKit

/// 검색 필드의 필드 에디터. 한글을 조합하는 중인 글자(marked text)도 바로 알린다
///
/// NSTextField의 stringValue와 controlTextDidChange는 조합이 끝나야 바뀌는 경우가 있어,
/// 조합 중에도 결과를 보여 주려고 필드 에디터에서 직접 문자열과 조합 여부를 넘긴다
final class SearchFieldEditor: NSTextView {
    /// (지금 문자열, 조합 중인지)
    var onChange: ((String, Bool) -> Void)?
    /// 글자를 바꾸기 직전 (바뀔 범위). 전체 선택을 덮어쓰는지 판단할 때 쓴다
    var onWillChange: ((NSRange) -> Void)?
    /// 선택 범위가 바뀐 뒤
    var onSelectionChange: (() -> Void)?
    /// false면 글자를 바꾸지 않는다 (휴지통 확인 카드가 떠 있는 동안)
    var canChangeText: (() -> Bool)?

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard canChangeText?() ?? true else { return false }
        onWillChange?(affectedCharRange)
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        onSelectionChange?()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        notify()
    }

    override func unmarkText() {
        super.unmarkText()
        notify()
    }

    override func didChangeText() {
        super.didChangeText()
        notify()
    }

    // 조합 중인 글자를 포함한 문자열을 알린다
    private func notify() {
        onChange?(string, hasMarkedText())
    }
}
