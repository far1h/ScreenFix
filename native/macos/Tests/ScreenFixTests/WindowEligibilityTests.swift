import ScreenFixCore

private let eligibilityDisplay = RectD(x: 0, y: 0, width: 1200, height: 800)

private func eligibilityFacts(
    ownerPID: Int32? = 42,
    screenFixPID: Int32 = 7,
    ownerIsRegular: Bool? = true,
    ownerIsHidden: Bool? = false,
    ownerIsTerminated: Bool? = false,
    role: String? = "AXWindow",
    subrole: String? = "AXStandardWindow",
    minimized: Bool? = false,
    frame: RectD? = RectD(x: 350, y: 100, width: 500, height: 400),
    positionSettable: Bool? = true,
    assignedDisplayID: String? = "selected",
    selectedDisplayID: String? = "selected",
    fullDisplayFrames: [RectD] = [eligibilityDisplay]
) -> WindowFacts {
    WindowFacts(
        ownerPID: ownerPID,
        screenFixPID: screenFixPID,
        ownerIsRegular: ownerIsRegular,
        ownerIsHidden: ownerIsHidden,
        ownerIsTerminated: ownerIsTerminated,
        role: role,
        subrole: subrole,
        minimized: minimized,
        frame: frame,
        positionSettable: positionSettable,
        assignedDisplayID: assignedDisplayID,
        selectedDisplayID: selectedDisplayID,
        fullDisplayFrames: fullDisplayFrames
    )
}

let windowEligibilityTests: [TestCase] = [
    TestCase(name: "WindowEligibility accepts an ordinary movable standard window") {
        try expect(WindowEligibility.isEligible(eligibilityFacts()))
    },
    TestCase(name: "WindowEligibility keeps fixed-size position-settable windows eligible") {
        try expect(WindowEligibility.isEligible(eligibilityFacts(positionSettable: true)))
    },
    TestCase(name: "WindowEligibility rejects ScreenFix and system-owned windows") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerPID: 7)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerPID: 0)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerPID: nil)))
    },
    TestCase(name: "WindowEligibility rejects nonregular hidden and terminated owners") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsRegular: false)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsRegular: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsHidden: true)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsHidden: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsTerminated: true)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(ownerIsTerminated: nil)))
    },
    TestCase(name: "WindowEligibility rejects nonstandard roles and subroles") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(role: "AXMenu")))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(role: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(subrole: "AXDialog")))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(subrole: "AXFloatingWindow")))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(subrole: nil)))
    },
    TestCase(name: "WindowEligibility rejects minimized and nonmovable windows") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(minimized: true)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(minimized: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(positionSettable: false)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(positionSettable: nil)))
    },
    TestCase(name: "WindowEligibility requires one selected display assignment") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(assignedDisplayID: "other")))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(assignedDisplayID: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(selectedDisplayID: nil)))
    },
    TestCase(name: "WindowEligibility excludes full-display frames within one point") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(
            frame: RectD(x: 0.5, y: -0.5, width: 1199.5, height: 800.5)
        )))
        try expect(WindowEligibility.isEligible(eligibilityFacts(
            frame: RectD(x: 2, y: 0, width: 1200, height: 800)
        )))
    },
    TestCase(name: "WindowEligibility fails closed for malformed geometry") {
        try expect(!WindowEligibility.isEligible(eligibilityFacts(frame: nil)))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(
            frame: RectD(x: .nan, y: 0, width: 100, height: 100)
        )))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(
            frame: RectD(x: 0, y: 0, width: 0, height: 100)
        )))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(fullDisplayFrames: [])))
        try expect(!WindowEligibility.isEligible(eligibilityFacts(
            fullDisplayFrames: [RectD(x: 0, y: 0, width: .infinity, height: 800)]
        )))
    },
]
