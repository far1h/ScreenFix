import Foundation

public struct DisplayFrame: Equatable {
    public let stableID: String?
    public let frame: RectD

    public init(stableID: String?, frame: RectD) {
        self.stableID = stableID
        self.frame = frame
    }
}

public enum DisplayAssignment {
    /// Returns the unique display with the largest positive window intersection.
    public static func stableID(for window: RectD, displays: [DisplayFrame]) -> String? {
        guard isValid(window), !displays.isEmpty else { return nil }

        var seen = Set<String>()
        var candidates: [(id: String, frame: RectD)] = []
        for display in displays {
            guard isValid(display.frame),
                  let id = display.stableID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id).inserted else {
                return nil
            }
            candidates.append((id, display.frame))
        }

        var bestID: String?
        var bestArea = 0.0
        var tied = false
        for candidate in candidates {
            let area = intersectionArea(window, candidate.frame)
            guard area > 0 else { continue }
            if area > bestArea {
                bestID = candidate.id
                bestArea = area
                tied = false
            } else if area == bestArea {
                tied = true
            }
        }
        return tied ? nil : bestID
    }

    private static func intersectionArea(_ lhs: RectD, _ rhs: RectD) -> Double {
        let width = max(0, min(lhs.right, rhs.right) - max(lhs.x, rhs.x))
        let height = max(0, min(lhs.bottom, rhs.bottom) - max(lhs.y, rhs.y))
        return width * height
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
