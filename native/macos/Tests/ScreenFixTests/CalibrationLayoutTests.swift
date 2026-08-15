import ScreenFixCore

private func expectInside(_ child: RectD, _ parent: RectD) throws {
    try expect(child.x >= parent.x)
    try expect(child.y >= parent.y)
    try expect(child.right <= parent.right)
    try expect(child.bottom <= parent.bottom)
}

private func requireLayout(_ layout: CalibrationControlLayout?) throws -> CalibrationControlLayout {
    guard let layout else { throw TestFailure(description: "expected a calibration layout") }
    return layout
}

let calibrationLayoutTests = [
    TestCase(name: "CalibrationLayout rejects displays below its minimum size") {
        try expectEqual(CalibrationControlLayout.make(width: 259, height: 180), nil)
        try expectEqual(CalibrationControlLayout.make(width: 260, height: 179), nil)
        try expect(CalibrationControlLayout.make(width: 260, height: 180) != nil)
    },
    TestCase(name: "CalibrationLayout ordinary display uses exact approved frames") {
        let layout = try requireLayout(CalibrationControlLayout.make(width: 1_000, height: 800))
        try expectEqual(layout.save, RectD(x: 24, y: 734, width: 104, height: 42))
        try expectEqual(layout.cancel, RectD(x: 140, y: 734, width: 104, height: 42))
        try expectEqual(layout.instruction, RectD(x: 24, y: 24, width: 330, height: 42))
        try expectEqual(layout.instructionDot, RectD(x: 40, y: 41, width: 8, height: 8))
        try expectEqual(layout.instructionText, RectD(x: 58, y: 24, width: 280, height: 42))
        try expectEqual(layout.instructionTextSize, 15)
    },
    TestCase(name: "CalibrationLayout keeps controls inside menu bar and Dock safe edges") {
        let cases: [(RectD, RectD, RectD, RectD)] = [
            (
                RectD(x: 0, y: 38, width: 1_000, height: 762),
                RectD(x: 24, y: 734, width: 104, height: 42),
                RectD(x: 140, y: 734, width: 104, height: 42),
                RectD(x: 24, y: 62, width: 330, height: 42)
            ),
            (
                RectD(x: 0, y: 0, width: 1_000, height: 750),
                RectD(x: 24, y: 684, width: 104, height: 42),
                RectD(x: 140, y: 684, width: 104, height: 42),
                RectD(x: 24, y: 24, width: 330, height: 42)
            ),
            (
                RectD(x: 80, y: 0, width: 920, height: 800),
                RectD(x: 104, y: 734, width: 104, height: 42),
                RectD(x: 220, y: 734, width: 104, height: 42),
                RectD(x: 104, y: 24, width: 330, height: 42)
            ),
            (
                RectD(x: 0, y: 0, width: 900, height: 800),
                RectD(x: 24, y: 734, width: 104, height: 42),
                RectD(x: 140, y: 734, width: 104, height: 42),
                RectD(x: 24, y: 24, width: 330, height: 42)
            ),
        ]
        for (safeFrame, save, cancel, instruction) in cases {
            let layout = try requireLayout(
                CalibrationControlLayout.make(width: 1_000, height: 800, safeFrame: safeFrame)
            )
            try expectEqual(layout.save, save)
            try expectEqual(layout.cancel, cancel)
            try expectEqual(layout.instruction, instruction)
            try expectInside(layout.save, safeFrame)
            try expectInside(layout.cancel, safeFrame)
            try expectInside(layout.instruction, safeFrame)
        }
    },
    TestCase(name: "CalibrationLayout rejects invalid or insufficient safe frames") {
        let invalid = [
            RectD(x: -1, y: 0, width: 1_000, height: 800),
            RectD(x: 0, y: -1, width: 1_000, height: 800),
            RectD(x: 0, y: 0, width: 1_001, height: 800),
            RectD(x: 0, y: 0, width: 1_000, height: 801),
            RectD(x: 0, y: 0, width: 259, height: 800),
            RectD(x: 0, y: 0, width: 1_000, height: 179),
            RectD(x: .nan, y: 0, width: 1_000, height: 800),
            RectD(x: 0, y: 0, width: .infinity, height: 800),
        ]
        for safeFrame in invalid {
            try expectEqual(
                CalibrationControlLayout.make(width: 1_000, height: 800, safeFrame: safeFrame),
                nil
            )
        }
    },
    TestCase(name: "CalibrationLayout minimum width computes button widths and narrow instruction") {
        let layout = try requireLayout(CalibrationControlLayout.make(width: 260, height: 180))
        try expectEqual(layout.save, RectD(x: 24, y: 114, width: 100, height: 42))
        try expectEqual(layout.cancel, RectD(x: 136, y: 114, width: 100, height: 42))
        try expectEqual(layout.instruction, RectD(x: 24, y: 24, width: 212, height: 58))
        try expectEqual(layout.instructionDot, RectD(x: 40, y: 49, width: 8, height: 8))
        try expectEqual(layout.instructionText, RectD(x: 58, y: 24, width: 162, height: 58))
        try expectEqual(layout.instructionTextSize, 13)
    },
    TestCase(name: "CalibrationLayout 378 point cutoff keeps ordinary instruction") {
        let ordinary = try requireLayout(CalibrationControlLayout.make(width: 378, height: 200))
        let narrow = try requireLayout(CalibrationControlLayout.make(width: 377, height: 200))
        try expectEqual(ordinary.instruction, RectD(x: 24, y: 24, width: 330, height: 42))
        try expectEqual(ordinary.instructionTextSize, 15)
        try expectEqual(narrow.instruction, RectD(x: 24, y: 24, width: 329, height: 58))
        try expectEqual(narrow.instructionDot.y, 49)
        try expectEqual(narrow.instructionText.width, 279)
        try expectEqual(narrow.instructionTextSize, 13)
    },
    TestCase(name: "CalibrationLayout controls remain inside and do not overlap") {
        for (width, height) in [(260.0, 180.0), (377.0, 180.0), (1_000.0, 800.0)] {
            let layout = try requireLayout(CalibrationControlLayout.make(width: width, height: height))
            let canvas = RectD(x: 0, y: 0, width: width, height: height)
            try expectInside(layout.save, canvas)
            try expectInside(layout.cancel, canvas)
            try expectInside(layout.instruction, canvas)
            try expectInside(layout.instructionDot, layout.instruction)
            try expectInside(layout.instructionText, layout.instruction)
            try expect(layout.save.right < layout.cancel.x)
            try expect(layout.instruction.bottom < layout.save.y)
        }
    },
    TestCase(name: "CalibrationLayout rejects nonfinite and nonpositive dimensions") {
        try expectEqual(CalibrationControlLayout.make(width: .nan, height: 180), nil)
        try expectEqual(CalibrationControlLayout.make(width: 260, height: .infinity), nil)
        try expectEqual(CalibrationControlLayout.make(width: -1, height: 180), nil)
    },
]
