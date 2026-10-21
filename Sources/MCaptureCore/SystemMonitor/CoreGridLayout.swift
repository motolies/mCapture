import Foundation

/// 코어 링 격자 배치. 칩마다 코어 수가 달라(M1 8, M4 Pro 14, M3 Ultra 32) 열 수를 코어 수로 정한다
public enum CoreGridLayout {
    /// 열 수. 최대 열 안에서 줄 수가 가장 적은 열 수 중 가장 작은 것을 고른다 (마지막 줄이 가장 꽉 찬다)
    /// 8 → 한 줄, 9 → 5+4, 10 → 5+5, 12 → 6+6, 14 → 7+7, 16 → 8+8, 20 → 7+7+6, 24 → 8×3
    public static func columns(for count: Int, maxColumns: Int = 8) -> Int {
        guard count > 0 else { return 1 }
        let maxColumns = max(1, maxColumns)
        if count <= maxColumns { return count }
        let rows = (count + maxColumns - 1) / maxColumns
        return (count + rows - 1) / rows
    }

    /// 링 지름. 열이 많으면 폭에 맞춰 줄이고, 적어도 최대 크기를 넘지 않는다
    public static func ringDiameter(columns: Int, availableWidth: Double, spacing: Double, maxDiameter: Double = 30) -> Double {
        let columns = max(1, columns)
        let fit = ((availableWidth - Double(columns - 1) * spacing) / Double(columns)).rounded(.down)
        return max(12, min(maxDiameter, fit))
    }
}
