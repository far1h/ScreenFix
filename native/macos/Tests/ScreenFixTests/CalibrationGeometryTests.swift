import ScreenFixCore

private let calibrationDisplay = RectD(x: 0, y: 0, width: 1_000, height: 1_000)

private func band(
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
) -> NormalizedRect {
    NormalizedRect(x: x, y: y, w: width, h: height)
}

private func expectBand(
    _ actual: NormalizedRect,
    _ expected: NormalizedRect,
    accuracy: Double = 1e-12
) throws {
    try expectEqual(actual.x, expected.x, accuracy: accuracy)
    try expectEqual(actual.y, expected.y, accuracy: accuracy)
    try expectEqual(actual.w, expected.w, accuracy: accuracy)
    try expectEqual(actual.h, expected.h, accuracy: accuracy)
}

let calibrationGeometryTests = [
    TestCase(name: "CalibrationGeometry hitTest finds all handles and body") {
        let frames = [RectD(x: 100, y: 200, width: 300, height: 400)]
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 100, y: 400), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .left)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 400, y: 400), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .right)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 250, y: 200), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .top)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 250, y: 600), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .bottom)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 250, y: 400), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .body)
        )
    },
    TestCase(name: "CalibrationGeometry hitTest gives handles and later painting priority") {
        let frames = [
            RectD(x: 0, y: 0, width: 100, height: 100),
            RectD(x: 50, y: 0, width: 100, height: 100),
        ]
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 50, y: 50), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 1, part: .left)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 75, y: 50), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 1, part: .body)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 100, y: 100), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 1, part: .bottom)
        )
    },
    TestCase(name: "CalibrationGeometry hitTest same-band corner follows bottom top right left order") {
        let frames = [RectD(x: 10, y: 20, width: 100, height: 100)]
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 110, y: 120), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .bottom)
        )
        try expectEqual(
            CalibrationGeometry.hitTest(point: PointD(x: 10, y: 20), frames: frames, handleSize: 8),
            CalibrationHit(bandIndex: 0, part: .top)
        )
    },
    TestCase(name: "CalibrationGeometry drag clamps body on every screen edge") {
        let original = band(0.20, 0.30, 0.40, 0.50)
        try expectBand(
            CalibrationGeometry.drag(
                band: original,
                part: .body,
                delta: PointD(x: -1_000, y: -1_000),
                displaySize: calibrationDisplay,
                minimumSize: 20
            ),
            band(0, 0, 0.40, 0.50)
        )
        try expectBand(
            CalibrationGeometry.drag(
                band: original,
                part: .body,
                delta: PointD(x: 1_000, y: 1_000),
                displaySize: calibrationDisplay,
                minimumSize: 20
            ),
            band(0.60, 0.50, 0.40, 0.50)
        )
        try expectBand(original, band(0.20, 0.30, 0.40, 0.50))
    },
    TestCase(name: "CalibrationGeometry drag resizes every edge and fixes its opposite edge") {
        let original = band(0.20, 0.30, 0.40, 0.40)
        let cases: [(CalibrationPart, PointD, NormalizedRect)] = [
            (.left, PointD(x: 50, y: 0), band(0.25, 0.30, 0.35, 0.40)),
            (.right, PointD(x: -50, y: 0), band(0.20, 0.30, 0.35, 0.40)),
            (.top, PointD(x: 0, y: 50), band(0.20, 0.35, 0.40, 0.35)),
            (.bottom, PointD(x: 0, y: -50), band(0.20, 0.30, 0.40, 0.35)),
        ]
        for (part, delta, expected) in cases {
            let result = CalibrationGeometry.drag(
                band: original,
                part: part,
                delta: delta,
                displaySize: calibrationDisplay,
                minimumSize: 20
            )
            try expectBand(result, expected)
        }
    },
    TestCase(name: "CalibrationGeometry drag never crosses its 20 point minimum") {
        let original = band(0.20, 0.30, 0.40, 0.40)
        let cases: [(CalibrationPart, PointD, NormalizedRect)] = [
            (.left, PointD(x: 1_000, y: 0), band(0.58, 0.30, 0.02, 0.40)),
            (.right, PointD(x: -1_000, y: 0), band(0.20, 0.30, 0.02, 0.40)),
            (.top, PointD(x: 0, y: 1_000), band(0.20, 0.68, 0.40, 0.02)),
            (.bottom, PointD(x: 0, y: -1_000), band(0.20, 0.30, 0.40, 0.02)),
        ]
        for (part, delta, expected) in cases {
            try expectBand(
                CalibrationGeometry.drag(
                    band: original,
                    part: part,
                    delta: delta,
                    displaySize: calibrationDisplay,
                    minimumSize: 20
                ),
                expected
            )
        }
    },
    TestCase(name: "CalibrationGeometry malformed undersized edge moves only toward validity") {
        let narrow = band(0.50, 0.20, 0.01, 0.20)
        try expectBand(
            CalibrationGeometry.drag(
                band: narrow,
                part: .right,
                delta: PointD(x: -10, y: 0),
                displaySize: calibrationDisplay,
                minimumSize: 20
            ),
            narrow
        )
        try expectBand(
            CalibrationGeometry.drag(
                band: narrow,
                part: .right,
                delta: PointD(x: 10, y: 0),
                displaySize: calibrationDisplay,
                minimumSize: 20
            ),
            band(0.50, 0.20, 0.02, 0.20)
        )
    },
    TestCase(name: "CalibrationGeometry body snaps leading and trailing edges to screen") {
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: band(0.012, 0.012, 0.30, 0.40),
                activeIndex: 0,
                part: .body,
                bands: [band(0.012, 0.012, 0.30, 0.40)],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            band(0, 0, 0.30, 0.40)
        )
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: band(0.50, 0.50, 0.488, 0.488),
                activeIndex: 0,
                part: .body,
                bands: [band(0.50, 0.50, 0.488, 0.488)],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            band(0.512, 0.512, 0.488, 0.488)
        )
    },
    TestCase(name: "CalibrationGeometry resize edges snap only to legal screen boundaries") {
        let cases: [(CalibrationPart, NormalizedRect, NormalizedRect)] = [
            (.left, band(0.012, 0.20, 0.30, 0.40), band(0, 0.20, 0.312, 0.40)),
            (.right, band(0.50, 0.20, 0.488, 0.40), band(0.50, 0.20, 0.50, 0.40)),
            (.top, band(0.20, 0.012, 0.30, 0.40), band(0.20, 0, 0.30, 0.412)),
            (.bottom, band(0.20, 0.50, 0.30, 0.488), band(0.20, 0.50, 0.30, 0.50)),
        ]
        for (part, raw, expected) in cases {
            try expectBand(
                CalibrationGeometry.snap(
                    rawBand: raw,
                    activeIndex: 0,
                    part: part,
                    bands: [raw],
                    displaySize: calibrationDisplay,
                    threshold: 12
                ),
                expected
            )
        }
        let illegal = band(0.988, 0.20, 0.012, 0.40)
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: illegal,
                activeIndex: 0,
                part: .left,
                bands: [illegal],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            illegal
        )
    },
    TestCase(name: "CalibrationGeometry body edges snap to both peer edges") {
        let peers = [
            band(0.40, 0.70, 0.10, 0.10),
            band(0.70, 0.40, 0.10, 0.10),
        ]
        let cases: [(NormalizedRect, NormalizedRect)] = [
            (band(0.388, 0.20, 0.20, 0.20), band(0.40, 0.20, 0.20, 0.20)),
            (band(0.288, 0.20, 0.20, 0.20), band(0.30, 0.20, 0.20, 0.20)),
            (band(0.20, 0.388, 0.20, 0.20), band(0.20, 0.40, 0.20, 0.20)),
            (band(0.20, 0.288, 0.20, 0.20), band(0.20, 0.30, 0.20, 0.20)),
        ]
        for (raw, expected) in cases {
            try expectBand(
                CalibrationGeometry.snap(
                    rawBand: raw,
                    activeIndex: 2,
                    part: .body,
                    bands: peers + [raw],
                    displaySize: calibrationDisplay,
                    threshold: 12
                ),
                expected
            )
        }
    },
    TestCase(name: "CalibrationGeometry every resized edge snaps to both peer edges") {
        let peer = band(0.40, 0.40, 0.10, 0.10)
        let cases: [(CalibrationPart, NormalizedRect, NormalizedRect)] = [
            (.left, band(0.388, 0.20, 0.20, 0.20), band(0.40, 0.20, 0.188, 0.20)),
            (.left, band(0.488, 0.20, 0.20, 0.20), band(0.50, 0.20, 0.188, 0.20)),
            (.right, band(0.20, 0.20, 0.188, 0.20), band(0.20, 0.20, 0.20, 0.20)),
            (.right, band(0.20, 0.20, 0.288, 0.20), band(0.20, 0.20, 0.30, 0.20)),
            (.top, band(0.20, 0.388, 0.20, 0.20), band(0.20, 0.40, 0.20, 0.188)),
            (.top, band(0.20, 0.488, 0.20, 0.20), band(0.20, 0.50, 0.20, 0.188)),
            (.bottom, band(0.20, 0.20, 0.20, 0.188), band(0.20, 0.20, 0.20, 0.20)),
            (.bottom, band(0.20, 0.20, 0.20, 0.288), band(0.20, 0.20, 0.20, 0.30)),
        ]
        for (part, raw, expected) in cases {
            try expectBand(
                CalibrationGeometry.snap(
                    rawBand: raw,
                    activeIndex: 1,
                    part: part,
                    bands: [peer, raw],
                    displaySize: calibrationDisplay,
                    threshold: 12
                ),
                expected
            )
        }
    },
    TestCase(name: "CalibrationGeometry snap threshold is inclusive at 12 points") {
        let exact = band(0.012, 0.30, 0.20, 0.20)
        let outside = band(0.01201, 0.30, 0.20, 0.20)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: exact,
                activeIndex: 0,
                part: .body,
                bands: [exact],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0
        )
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: outside,
                activeIndex: 0,
                part: .body,
                bands: [outside],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            outside
        )
    },
    TestCase(name: "CalibrationGeometry snap tie order is deterministic") {
        let screenTie = band(0.01, 0.30, 0.98, 0.20)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: screenTie,
                activeIndex: 1,
                part: .body,
                bands: [band(0.02, 0.70, 0.10, 0.10), screenTie],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0
        )

        let peerTie = band(0.39, 0.20, 0.20, 0.20)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: peerTie,
                activeIndex: 2,
                part: .body,
                bands: [band(0.38, 0.70, 0.10, 0.10), band(0.40, 0.70, 0.10, 0.10), peerTie],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0.38
        )

        let edgeTie = band(0.39, 0.20, 0.02, 0.20)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: edgeTie,
                activeIndex: 1,
                part: .body,
                bands: [band(0.38, 0.70, 0.02, 0.10), edgeTie],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0.38
        )

        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: edgeTie,
                activeIndex: 1,
                part: .body,
                bands: [band(0.40, 0.70, 0.10, 0.10), edgeTie],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0.40
        )
    },
    TestCase(name: "CalibrationGeometry snap rejects out of bounds and affected subminimum sizes") {
        let raw = band(0.50, 0.20, 0.025, 0.20)
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: raw,
                activeIndex: 1,
                part: .right,
                bands: [band(0.519999999999, 0.70, 0.10, 0.10), raw],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            raw
        )
        let outOfBounds = band(0.10, 0.20, 0.20, 0.20)
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: outOfBounds,
                activeIndex: 1,
                part: .right,
                bands: [band(0, 0.70, 0.09, 0.10), outOfBounds],
                displaySize: calibrationDisplay,
                threshold: 800
            ),
            band(0.10, 0.20, 0.90, 0.20)
        )
    },
    TestCase(name: "CalibrationGeometry snap minimum checks are axis specific") {
        let shortHorizontal = band(0.25, 0.20, 0.03, 0.019)
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: shortHorizontal,
                activeIndex: 1,
                part: .right,
                bands: [band(0.27, 0.70, 0.10, 0.10), shortHorizontal],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            band(0.25, 0.20, 0.27 - 0.25, 0.019)
        )
        let narrowVertical = band(0.20, 0.25, 0.019, 0.03)
        try expectBand(
            CalibrationGeometry.snap(
                rawBand: narrowVertical,
                activeIndex: 1,
                part: .bottom,
                bands: [band(0.70, 0.27, 0.10, 0.10), narrowVertical],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            band(0.20, 0.25, 0.019, 0.27 - 0.25)
        )
        let narrowBody = band(0.012, 0.20, 0.019, 0.20)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: narrowBody,
                activeIndex: 0,
                part: .body,
                bands: [narrowBody],
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0
        )
        let shortBody = band(0.20, 0.012, 0.20, 0.019)
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: shortBody,
                activeIndex: 0,
                part: .body,
                bands: [shortBody],
                displaySize: calibrationDisplay,
                threshold: 12
            ).y,
            0
        )
    },
    TestCase(name: "CalibrationGeometry snap permits exact 20 points within machine tolerance") {
        let raw = band(0.002, 0.20, 0.025, 0.019)
        let snapped = CalibrationGeometry.snap(
            rawBand: raw,
            activeIndex: 1,
            part: .right,
            bands: [band(0.022, 0.70, 0.30, 0.10), raw],
            displaySize: calibrationDisplay,
            threshold: 12
        )
        try expectEqual(snapped.x + snapped.w, 0.022)
        try expectEqual(snapped.w, 0.022 - raw.x)
    },
    TestCase(name: "CalibrationGeometry invalid values fail closed") {
        let raw = band(0.20, 0.20, 0.20, 0.20)
        let malformedPeers = [band(.nan, 0, 0.10, 0.10), band(0.40, 0.70, 0.10, 0.10), raw]
        try expectEqual(
            CalibrationGeometry.snap(
                rawBand: raw,
                activeIndex: 2,
                part: .body,
                bands: malformedPeers,
                displaySize: calibrationDisplay,
                threshold: 12
            ).x,
            0.20
        )
        let invalidCases = [
            CalibrationGeometry.snap(
                rawBand: band(.nan, 0.20, 0.20, 0.20),
                activeIndex: 0,
                part: .body,
                bands: [raw],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            CalibrationGeometry.snap(
                rawBand: raw,
                activeIndex: -1,
                part: .body,
                bands: [raw],
                displaySize: calibrationDisplay,
                threshold: 12
            ),
            CalibrationGeometry.snap(
                rawBand: raw,
                activeIndex: 0,
                part: .body,
                bands: [raw],
                displaySize: RectD(x: 0, y: 0, width: .infinity, height: 1_000),
                threshold: 12
            ),
            CalibrationGeometry.snap(
                rawBand: raw,
                activeIndex: 0,
                part: .body,
                bands: [raw],
                displaySize: calibrationDisplay,
                threshold: .nan
            ),
        ]
        for result in invalidCases {
            if result.x.isNaN {
                try expect(result.y == 0.20 && result.w == 0.20 && result.h == 0.20)
            } else {
                try expectBand(result, raw)
            }
        }
        try expectEqual(
            CalibrationGeometry.hitTest(
                point: PointD(x: .infinity, y: 0),
                frames: [RectD(x: 0, y: 0, width: 10, height: 10)],
                handleSize: 8
            ),
            nil
        )
    },
]
