import Foundation

public struct WindowFacts: Equatable {
    public let ownerPID: Int32?
    public let screenFixPID: Int32
    public let ownerIsRegular: Bool?
    public let ownerIsHidden: Bool?
    public let ownerIsTerminated: Bool?
    public let role: String?
    public let subrole: String?
    public let minimized: Bool?
    public let frame: RectD?
    public let positionSettable: Bool?
    public let assignedDisplayID: String?
    public let selectedDisplayID: String?
    public let fullDisplayFrames: [RectD]

    public init(
        ownerPID: Int32?,
        screenFixPID: Int32,
        ownerIsRegular: Bool?,
        ownerIsHidden: Bool?,
        ownerIsTerminated: Bool?,
        role: String?,
        subrole: String?,
        minimized: Bool?,
        frame: RectD?,
        positionSettable: Bool?,
        assignedDisplayID: String?,
        selectedDisplayID: String?,
        fullDisplayFrames: [RectD]
    ) {
        self.ownerPID = ownerPID
        self.screenFixPID = screenFixPID
        self.ownerIsRegular = ownerIsRegular
        self.ownerIsHidden = ownerIsHidden
        self.ownerIsTerminated = ownerIsTerminated
        self.role = role
        self.subrole = subrole
        self.minimized = minimized
        self.frame = frame
        self.positionSettable = positionSettable
        self.assignedDisplayID = assignedDisplayID
        self.selectedDisplayID = selectedDisplayID
        self.fullDisplayFrames = fullDisplayFrames
    }
}

public enum WindowEligibility {
    public static let standardRole = "AXWindow"
    public static let standardSubrole = "AXStandardWindow"

    /// Conservatively classifies an ordinary movable window using fresh facts.
    public static func isEligible(_ facts: WindowFacts) -> Bool {
        guard let ownerPID = facts.ownerPID,
              ownerPID > 0,
              facts.screenFixPID > 0,
              ownerPID != facts.screenFixPID,
              facts.ownerIsRegular == true,
              facts.ownerIsHidden == false,
              facts.ownerIsTerminated == false,
              facts.role == standardRole,
              facts.subrole == standardSubrole,
              facts.minimized == false,
              facts.positionSettable == true,
              let frame = facts.frame,
              isValid(frame),
              let assignedID = nonempty(facts.assignedDisplayID),
              let selectedID = nonempty(facts.selectedDisplayID),
              assignedID == selectedID,
              !facts.fullDisplayFrames.isEmpty,
              facts.fullDisplayFrames.allSatisfy(isValid) else {
            return false
        }

        return !facts.fullDisplayFrames.contains { fullFrame in
            WindowCorrection.framesNear(frame, fullFrame, tolerance: 1)
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
