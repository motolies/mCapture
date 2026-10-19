import AppKit

/// 검색 필드의 필드 에디터. 한글을 조합하는 중인 글자(marked text)도 바로 알린다
///
/// NSTextField의 stringValue와 controlTextDidChange는 조합이 끝나야 바뀌는 경우가 있어,
/// 조합 중에도 결과를 보여 주려고 필드 에디터에서 직접 문자열과 조합 여부를 넘긴다
final class SearchFieldEditor: NSTextView {
    /// (지금 문자열, 조합 중인지)
    var onChange: ((String, Bool) -> Void)?

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
