import ScreenFixCore

private let interactionDisplay = RectD(x: 0, y: 0, width: 1_000, height: 1_000)
private let interactionControls = CalibrationControlLayout(
    save: RectD(x: 24, y: 934, width: 104, height: 42),
    cancel: RectD(x: 140, y: 934, width: 104, height: 42),
    instruction: RectD(x: 24, y: 24, width: 330, height: 42),
    instructionDot: RectD(x: 40, y: 41, width: 8, height: 8),
    instructionText: RectD(x: 58, y: 24, width: 280, height: 42),
    instructionTextSize: 15
)

private func interactionBand(
    _ x: Double = 0.20,
    _ y: Double = 0.20,
    _ width: Double = 0.30,
    _ height: Double = 0.30
) -> NormalizedRect {
    NormalizedRect(x: x, y: y, w: width, h: height)
}

private func interactionPoint(for part: CalibrationPart) -> PointD {
    switch part {
    case .body: return PointD(x: 350, y: 350)
    case .left: return PointD(x: 200, y: 350)
    case .right: return PointD(x: 500, y: 350)
    case .top: return PointD(x: 350, y: 200)
    case .bottom: return PointD(x: 350, y: 500)
    }
}

private func interactionDelta(for part: CalibrationPart) -> PointD {
    switch part {
    case .body, .left, .right: return PointD(x: 10, y: 0)
    case .top, .bottom: return PointD(x: 0, y: 10)
    }
}

private func adding(_ point: PointD, _ delta: PointD) -> PointD {
    PointD(x: point.x + delta.x, y: point.y + delta.y)
}

let calibrationInteractionTests = [
    TestCase(name: "CalibrationInteraction tap release latches body and every edge without moving") {
        let parts: [CalibrationPart] = [.body, .left, .right, .top, .bottom]
        for part in parts {
            let original = interactionBand()
            var interaction = CalibrationInteraction(workingBands: [original])
            let point = interactionPoint(for: part)
            try expectEqual(
                interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls),
                .none
            )
            try expectEqual(
                interaction.handle(
                    .primaryDragged(adding(point, PointD(x: 2, y: 3))),
                    displaySize: interactionDisplay,
                    controls: interactionControls
                ),
                .none
            )
            try expectEqual(
                interaction.handle(.primaryUp(point), displaySize: interactionDisplay, controls: interactionControls),
                .none
            )
            try expect(interaction.isLatched, "\(part) should latch")
            try expectEqual(interaction.workingBands, [original])
        }
    },
    TestCase(name: "CalibrationInteraction exact four point held drag moves body and every edge once") {
        let parts: [CalibrationPart] = [.body, .left, .right, .top, .bottom]
        for part in parts {
            let original = interactionBand()
            var interaction = CalibrationInteraction(workingBands: [original])
            let point = interactionPoint(for: part)
            let thresholdDelta: PointD
            switch part {
            case .body, .left, .right: thresholdDelta = PointD(x: 4, y: 0)
            case .top, .bottom: thresholdDelta = PointD(x: 0, y: 4)
            }
            _ = interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
            try expectEqual(
                interaction.handle(
                    .primaryDragged(adding(point, thresholdDelta)),
                    displaySize: interactionDisplay,
                    controls: interactionControls
                ),
                .redraw
            )
            try expect(interaction.workingBands[0] != original, "\(part) should change")
            _ = interaction.handle(
                .primaryDragged(adding(point, interactionDelta(for: part))),
                displaySize: interactionDisplay,
                controls: interactionControls
            )
            _ = interaction.handle(.primaryUp(point), displaySize: interactionDisplay, controls: interactionControls)
            try expect(!interaction.isLatched, "\(part) should release")
        }
    },
    TestCase(name: "CalibrationInteraction latched pointer movement edits every part without holding") {
        let parts: [CalibrationPart] = [.body, .left, .right, .top, .bottom]
        for part in parts {
            let original = interactionBand()
            var interaction = CalibrationInteraction(workingBands: [original])
            let point = interactionPoint(for: part)
            _ = interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
            _ = interaction.handle(.primaryUp(point), displaySize: interactionDisplay, controls: interactionControls)
            try expectEqual(
                interaction.handle(
                    .pointerMoved(adding(point, interactionDelta(for: part))),
                    displaySize: interactionDisplay,
                    controls: interactionControls
                ),
                .redraw
            )
            try expect(interaction.workingBands[0] != original, "\(part) should change")
            try expectEqual(
                interaction.handle(
                    .primaryDown(PointD(x: 800, y: 800)),
                    displaySize: interactionDisplay,
                    controls: interactionControls
                ),
                .none
            )
            try expect(!interaction.isLatched)
        }
    },
    TestCase(name: "CalibrationInteraction threshold uses Euclidean distance") {
        var below = CalibrationInteraction(workingBands: [interactionBand()])
        let point = interactionPoint(for: .body)
        _ = below.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
        try expectEqual(
            below.handle(
                .primaryDragged(adding(point, PointD(x: 2.8, y: 2.8))),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .none
        )

        var exact = CalibrationInteraction(workingBands: [interactionBand()])
        _ = exact.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
        try expectEqual(
            exact.handle(
                .primaryDragged(adding(point, PointD(x: 3, y: 3))),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .redraw
        )
    },
    TestCase(name: "CalibrationInteraction empty primary down leaves unrelated state unchanged") {
        let original = interactionBand()
        var interaction = CalibrationInteraction(workingBands: [original])
        try expectEqual(
            interaction.handle(
                .primaryDown(PointD(x: 800, y: 800)),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .none
        )
        try expectEqual(interaction.workingBands, [original])
        try expect(!interaction.isLatched)
    },
    TestCase(name: "CalibrationInteraction Save and Cancel activate immediately while latched") {
        for (point, effect) in [
            (PointD(x: 50, y: 950), CalibrationEffect.saveRequested),
            (PointD(x: 170, y: 950), CalibrationEffect.cancelRequested),
        ] {
            var interaction = CalibrationInteraction(workingBands: [interactionBand()])
            let body = interactionPoint(for: .body)
            _ = interaction.handle(.primaryDown(body), displaySize: interactionDisplay, controls: interactionControls)
            _ = interaction.handle(.primaryUp(body), displaySize: interactionDisplay, controls: interactionControls)
            try expect(interaction.isLatched)
            try expectEqual(
                interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls),
                effect
            )
        }
    },
    TestCase(name: "CalibrationInteraction visible snap releases from independent raw band") {
        var interaction = CalibrationInteraction(workingBands: [interactionBand(0.020, 0.20, 0.20, 0.20)])
        let point = PointD(x: 120, y: 300)
        _ = interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
        try expectEqual(
            interaction.handle(
                .primaryDragged(PointD(x: 112, y: 300)),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .redraw
        )
        try expectEqual(interaction.workingBands[0].x, 0)
        try expectEqual(
            interaction.handle(
                .primaryDragged(PointD(x: 113, y: 300)),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .redraw
        )
        try expectEqual(interaction.workingBands[0].x, 0.013, accuracy: 1e-12)
    },
    TestCase(name: "CalibrationInteraction rejected event is atomic and next event applies once") {
        let original = interactionBand()
        var interaction = CalibrationInteraction(workingBands: [original])
        let point = interactionPoint(for: .body)
        _ = interaction.handle(.primaryDown(point), displaySize: interactionDisplay, controls: interactionControls)
        try expectEqual(
            interaction.handle(
                .primaryDragged(PointD(x: .nan, y: point.y)),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .none
        )
        try expectEqual(interaction.workingBands, [original])
        try expectEqual(
            interaction.handle(
                .primaryDragged(PointD(x: point.x + 10, y: point.y)),
                displaySize: interactionDisplay,
                controls: interactionControls
            ),
            .redraw
        )
        try expectEqual(interaction.workingBands[0].x, original.x + 0.01, accuracy: 1e-12)
    },
]
