import ScreenFixCore

private func assignmentRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> RectD {
    RectD(x: x, y: y, width: width, height: height)
}

let displayAssignmentTests: [TestCase] = [
    TestCase(name: "DisplayAssignment selects the unique largest positive overlap") {
        let result = DisplayAssignment.stableID(
            for: assignmentRect(800, 100, 500, 400),
            displays: [
                DisplayFrame(stableID: "left", frame: assignmentRect(0, 0, 1000, 800)),
                DisplayFrame(stableID: "right", frame: assignmentRect(1000, 0, 1000, 800)),
            ]
        )
        try expectEqual(result, "right")
    },
    TestCase(name: "DisplayAssignment supports negative display origins") {
        let result = DisplayAssignment.stableID(
            for: assignmentRect(-1100, -700, 500, 400),
            displays: [
                DisplayFrame(stableID: "negative", frame: assignmentRect(-1200, -800, 1200, 800)),
                DisplayFrame(stableID: "primary", frame: assignmentRect(0, 0, 1200, 800)),
            ]
        )
        try expectEqual(result, "negative")
    },
    TestCase(name: "DisplayAssignment rejects equal-area ties") {
        let result = DisplayAssignment.stableID(
            for: assignmentRect(900, 100, 200, 400),
            displays: [
                DisplayFrame(stableID: "left", frame: assignmentRect(0, 0, 1000, 800)),
                DisplayFrame(stableID: "right", frame: assignmentRect(1000, 0, 1000, 800)),
            ]
        )
        try expectEqual(result, nil)
    },
    TestCase(name: "DisplayAssignment rejects ambiguous mirrored bounds") {
        let frame = assignmentRect(0, 0, 1200, 800)
        let result = DisplayAssignment.stableID(
            for: assignmentRect(100, 100, 500, 400),
            displays: [
                DisplayFrame(stableID: "mirror-a", frame: frame),
                DisplayFrame(stableID: "mirror-b", frame: frame),
            ]
        )
        try expectEqual(result, nil)
    },
    TestCase(name: "DisplayAssignment rejects zero overlap") {
        let result = DisplayAssignment.stableID(
            for: assignmentRect(1500, 100, 200, 200),
            displays: [DisplayFrame(stableID: "only", frame: assignmentRect(0, 0, 1000, 800))]
        )
        try expectEqual(result, nil)
    },
    TestCase(name: "DisplayAssignment rejects missing or duplicate stable identity") {
        try expectEqual(DisplayAssignment.stableID(
            for: assignmentRect(100, 100, 200, 200),
            displays: [DisplayFrame(stableID: nil, frame: assignmentRect(0, 0, 1000, 800))]
        ), nil)
        try expectEqual(DisplayAssignment.stableID(
            for: assignmentRect(900, 100, 300, 200),
            displays: [
                DisplayFrame(stableID: "same", frame: assignmentRect(0, 0, 1000, 800)),
                DisplayFrame(stableID: "same", frame: assignmentRect(1000, 0, 1000, 800)),
            ]
        ), nil)
    },
    TestCase(name: "DisplayAssignment fails closed for invalid frames") {
        try expectEqual(DisplayAssignment.stableID(
            for: assignmentRect(.nan, 100, 200, 200),
            displays: [DisplayFrame(stableID: "only", frame: assignmentRect(0, 0, 1000, 800))]
        ), nil)
        try expectEqual(DisplayAssignment.stableID(
            for: assignmentRect(100, 100, 200, 200),
            displays: [DisplayFrame(stableID: "only", frame: assignmentRect(0, 0, 0, 800))]
        ), nil)
    },
]
