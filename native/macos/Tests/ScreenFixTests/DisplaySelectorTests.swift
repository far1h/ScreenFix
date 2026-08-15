import ScreenFixCore

private let savedDisplay = DisplayIdentity(
    stableId: "ABC-123",
    name: "Ultrawide",
    width: 3440,
    height: 1440
)

private func connected(
    stableId: String?,
    name: String = "Ultrawide",
    width: Double = 3440,
    height: Double = 1440
) -> ConnectedDisplay {
    ConnectedDisplay(
        stableId: stableId,
        name: name,
        width: width,
        height: height,
        vendorId: 1,
        modelId: 2,
        serialNumber: 3
    )
}

let displaySelectorTests = [
    TestCase(name: "DisplaySelector stable identity wins over diagnostics") {
        let diagnosticTwin = connected(stableId: "other")
        let stableMatch = connected(stableId: "ABC-123", name: "Changed", width: 1920, height: 1080)
        try expectEqual(DisplaySelector.select(saved: savedDisplay, from: [diagnosticTwin, stableMatch]), stableMatch)
    },
    TestCase(name: "DisplaySelector compares stable identity case-insensitively") {
        let match = connected(stableId: "abc-123", name: "Changed")
        try expectEqual(DisplaySelector.select(saved: savedDisplay, from: [match]), match)
    },
    TestCase(name: "DisplaySelector uses one exact name and dimensions fallback") {
        let match = connected(stableId: nil)
        try expectEqual(DisplaySelector.select(saved: savedDisplay, from: [match]), match)
    },
    TestCase(name: "DisplaySelector rejects absent diagnostic fallback") {
        try expectEqual(DisplaySelector.select(saved: savedDisplay, from: []), nil)
    },
    TestCase(name: "DisplaySelector rejects ambiguous diagnostic fallback") {
        try expectEqual(DisplaySelector.select(
            saved: savedDisplay,
            from: [connected(stableId: nil), connected(stableId: "other")]
        ), nil)
    },
    TestCase(name: "DisplaySelector rejects same name with different dimensions") {
        try expectEqual(DisplaySelector.select(
            saved: savedDisplay,
            from: [connected(stableId: nil, width: 1920), connected(stableId: nil, height: 1080)]
        ), nil)
    },
]
