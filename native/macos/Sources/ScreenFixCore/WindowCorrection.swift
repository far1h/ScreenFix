import Foundation

public enum WindowCorrection {
    /// Returns the deterministic nearest frame outside all vertically relevant masks.
    public static func target(window: RectD, workArea: RectD, masks: [RectD]) -> RectD? {
        guard isValid(window), isValid(workArea), !masks.isEmpty, masks.allSatisfy(isValid) else {
            return nil
        }
        guard masks.contains(where: window.intersects) else { return nil }

        let adjustedHeight = min(window.height, workArea.height)
        let adjusted = RectD(
            x: window.x,
            y: clamp(window.y, workArea.y, workArea.bottom - adjustedHeight),
            width: window.width,
            height: adjustedHeight
        )
        let overlapping = masks.filter { mask in
            adjusted.y < mask.bottom && mask.y < adjusted.bottom
        }
        guard !overlapping.isEmpty else { return adjusted }

        let leftBoundary = overlapping.map(\.x).min()!
        let rightBoundary = overlapping.map(\.right).max()!
        let left = candidate(
            window: adjusted,
            regionStart: workArea.x,
            regionEnd: clamp(leftBoundary, workArea.x, workArea.right)
        )
        let right = candidate(
            window: adjusted,
            regionStart: clamp(rightBoundary, workArea.x, workArea.right),
            regionEnd: workArea.right
        )

        switch (left, right) {
        case (nil, nil):
            return nil
        case let (candidate?, nil), let (nil, candidate?):
            return candidate
        case let (left?, right?):
            return cost(window: window, candidate: left, sideRank: 0)
                .lexicographicallyPrecedes(cost(window: window, candidate: right, sideRank: 1))
                ? left
                : right
        }
    }

    /// Compares all frame components with an inclusive finite tolerance.
    public static func framesNear(_ lhs: RectD, _ rhs: RectD, tolerance: Double) -> Bool {
        guard tolerance.isFinite, tolerance >= 0, isValid(lhs), isValid(rhs) else { return false }
        return abs(lhs.x - rhs.x) <= tolerance
            && abs(lhs.y - rhs.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func candidate(window: RectD, regionStart: Double, regionEnd: Double) -> RectD? {
        let regionWidth = regionEnd - regionStart
        guard regionWidth > 0 else { return nil }
        let width = min(window.width, regionWidth)
        return RectD(
            x: clamp(window.x, regionStart, regionEnd - width),
            y: window.y,
            width: width,
            height: window.height
        )
    }

    private static func cost(window: RectD, candidate: RectD, sideRank: Double) -> [Double] {
        [
            abs(window.x - candidate.x) + abs(window.y - candidate.y),
            (window.width - candidate.width) + (window.height - candidate.height),
            sideRank,
        ]
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        max(minimum, min(value, maximum))
    }

    private static func isValid(_ rect: RectD) -> Bool {
        rect.x.isFinite
            && rect.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.right.isFinite
            && rect.bottom.isFinite
            && rect.width > 0
            && rect.height > 0
    }
}
