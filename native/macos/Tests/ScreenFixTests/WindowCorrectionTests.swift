import ScreenFixCore

private func correctionRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> RectD {
    RectD(x: x, y: y, width: width, height: height)
}

let windowCorrectionTests = [
    TestCase(name: "WindowCorrection returns nil when no mask intersects") {
        let result = WindowCorrection.target(
            window: correctionRect(0, 100, 300, 400),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(400, 0, 300, 800)]
        )
        try expectEqual(result, nil)
    },
    TestCase(name: "WindowCorrection preserves size on the nearest safe side") {
        let result = WindowCorrection.target(
            window: correctionRect(550, 100, 200, 400),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(400, 0, 300, 800)]
        )
        try expectEqual(result, correctionRect(700, 100, 200, 400))
    },
    TestCase(name: "WindowCorrection keeps a wide left-dragged window on the nearest side") {
        let result = WindowCorrection.target(
            window: correctionRect(-700, 100, 1400, 700),
            workArea: correctionRect(-951, 25, 3440, 1415),
            masks: [correctionRect(214, 0, 755, 1440)]
        )
        try expectEqual(result, correctionRect(-951, 100, 1165, 700))
    },
    TestCase(name: "WindowCorrection keeps a wide right-dragged window on the nearest side") {
        let result = WindowCorrection.target(
            window: correctionRect(700, 100, 1400, 700),
            workArea: correctionRect(-951, 25, 3440, 1415),
            masks: [correctionRect(214, 0, 755, 1440)]
        )
        try expectEqual(result, correctionRect(969, 100, 1400, 700))
    },
    TestCase(name: "WindowCorrection prefers shorter movement even when shrinking") {
        let result = WindowCorrection.target(
            window: correctionRect(100, 100, 500, 400),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(400, 0, 300, 800)]
        )
        try expectEqual(result, correctionRect(0, 100, 400, 400))
    },
    TestCase(name: "WindowCorrection clamps an oversized window before choosing a side") {
        let result = WindowCorrection.target(
            window: correctionRect(300, -100, 1000, 1000),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(400, 0, 300, 800)]
        )
        try expectEqual(result, correctionRect(0, 0, 400, 800))
    },
    TestCase(name: "WindowCorrection chooses left on equal movement and reduction") {
        let result = WindowCorrection.target(
            window: correctionRect(350, 100, 300, 400),
            workArea: correctionRect(0, 0, 1000, 800),
            masks: [correctionRect(400, 0, 200, 800)]
        )
        try expectEqual(result, correctionRect(100, 100, 300, 400))
    },
    TestCase(name: "WindowCorrection combines masks overlapping the adjusted vertical span") {
        let result = WindowCorrection.target(
            window: correctionRect(350, 100, 500, 600),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(400, 0, 100, 300), correctionRect(600, 500, 100, 300)]
        )
        try expectEqual(result, correctionRect(700, 100, 500, 600))
    },
    TestCase(name: "WindowCorrection keeps a vertical clamp that clears every mask") {
        let result = WindowCorrection.target(
            window: correctionRect(350, 20, 500, 100),
            workArea: correctionRect(0, 100, 1200, 700),
            masks: [correctionRect(400, 0, 300, 80)]
        )
        try expectEqual(result, correctionRect(350, 100, 500, 100))
    },
    TestCase(name: "WindowCorrection uses the only positive-width safe side") {
        let result = WindowCorrection.target(
            window: correctionRect(0, 100, 500, 400),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(0, 0, 300, 800)]
        )
        try expectEqual(result, correctionRect(300, 100, 500, 400))
    },
    TestCase(name: "WindowCorrection returns nil without a positive-width safe side") {
        let result = WindowCorrection.target(
            window: correctionRect(100, 100, 500, 400),
            workArea: correctionRect(0, 0, 1200, 800),
            masks: [correctionRect(0, 0, 1200, 800)]
        )
        try expectEqual(result, nil)
    },
    TestCase(name: "WindowCorrection preserves deterministic negative coordinates") {
        let result = WindowCorrection.target(
            window: correctionRect(-850, 100, 500, 400),
            workArea: correctionRect(-1200, 0, 1200, 800),
            masks: [correctionRect(-800, 0, 300, 800)]
        )
        try expectEqual(result, correctionRect(-500, 100, 500, 400))
    },
    TestCase(name: "WindowCorrection framesNear includes the exact tolerance") {
        let frame = correctionRect(100, 200, 500, 400)
        try expect(WindowCorrection.framesNear(
            frame,
            correctionRect(101, 199, 501, 399),
            tolerance: 1
        ))
        try expect(!WindowCorrection.framesNear(
            frame,
            correctionRect(101.01, 200, 500, 400),
            tolerance: 1
        ))
    },
    TestCase(name: "WindowCorrection fails closed for invalid rectangles") {
        let validWindow = correctionRect(350, 100, 500, 400)
        let validWorkArea = correctionRect(0, 0, 1200, 800)
        let validMask = correctionRect(400, 0, 300, 800)

        try expectEqual(WindowCorrection.target(
            window: correctionRect(.nan, 100, 500, 400),
            workArea: validWorkArea,
            masks: [validMask]
        ), nil)
        try expectEqual(WindowCorrection.target(
            window: correctionRect(350, 100, 0, 400),
            workArea: validWorkArea,
            masks: [validMask]
        ), nil)
        try expectEqual(WindowCorrection.target(
            window: validWindow,
            workArea: correctionRect(0, 0, 0, 800),
            masks: [validMask]
        ), nil)
        try expectEqual(WindowCorrection.target(
            window: validWindow,
            workArea: validWorkArea,
            masks: [correctionRect(400, 0, .infinity, 800)]
        ), nil)
        try expect(!WindowCorrection.framesNear(
            correctionRect(.nan, 0, 1, 1),
            correctionRect(0, 0, 1, 1),
            tolerance: 1
        ))
        try expect(!WindowCorrection.framesNear(
            validWindow,
            validWindow,
            tolerance: -1
        ))
    },
]
