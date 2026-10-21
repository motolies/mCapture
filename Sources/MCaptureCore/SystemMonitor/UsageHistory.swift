import Foundation

/// 최근 값을 정해진 개수만 남기는 기록 (오래된 것부터). CPU 기록 막대에 쓴다
public struct UsageHistory<Element: Sendable & Equatable>: Sendable, Equatable {
    public let capacity: Int
    public private(set) var elements: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        elements.reserveCapacity(self.capacity)
    }

    /// 끝에 붙이고 넘치면 가장 오래된 것을 버린다
    public mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > capacity {
            elements.removeFirst(elements.count - capacity)
        }
    }

    public var count: Int { elements.count }
    public var last: Element? { elements.last }
}
