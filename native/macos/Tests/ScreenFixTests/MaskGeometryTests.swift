import ScreenFixCore

let maskGeometryTests = [
    TestCase(name: "MaskGeometry projects permanent defaults across full display") {
        let display = DisplayIdentity(
            stableId: "display",
            name: "Ultrawide",
            width: 3440,
            height: 1440
        )
        let config = DefaultConfiguration.make(for: display, enabled: true)
        let frames = MaskGeometry.localFrames(
            bands: config.bands,
            displayWidth: 3440,
            displayHeight: 1440
        )

        try expectEqual(frames.count, 3)
        try expectEqual(frames[0], RectD(x: 1215, y: 0, width: 705, height: 489.6))
        try expectEqual(frames[1], RectD(x: 1215, y: 489.6, width: 705, height: 561.6))
        try expectEqual(frames[2], RectD(x: 1215, y: 1051.2, width: 705, height: 388.8))
        try expectEqual(frames[0].x, 1215, accuracy: 1e-12)
        try expectEqual(frames[0].right, 1920, accuracy: 1e-12)
        try expectEqual(frames[1].right, 1920, accuracy: 1e-12)
        try expectEqual(frames[2].right, 1920, accuracy: 1e-12)
        try expectEqual(frames[0].y, 0, accuracy: 1e-12)
        try expectEqual(frames[0].bottom, frames[1].y, accuracy: 1e-12)
        try expectEqual(frames[1].bottom, frames[2].y, accuracy: 1e-12)
        try expectEqual(frames[2].bottom, 1440, accuracy: 1e-12)
    },
    TestCase(name: "MaskGeometry preserves negative absolute display origins") {
        let bands = DefaultConfiguration.make(
            for: DisplayIdentity(stableId: "display", name: "Ultrawide", width: 3440, height: 1440),
            enabled: true
        ).bands
        let bounds = TopLeftDisplayBounds(x: -3440, y: -900, width: 3440, height: 1440)
        let frames = MaskGeometry.absoluteTopLeftFrames(bands: bands, in: bounds)

        try expectEqual(frames[0].x, -2225, accuracy: 1e-12)
        try expectEqual(frames[0].y, -900, accuracy: 1e-12)
    },
    TestCase(name: "MaskGeometry RectD uses half-open intersection") {
        let subject = RectD(x: 0, y: 0, width: 10, height: 10)
        try expect(!subject.intersects(RectD(x: 10, y: 0, width: 1, height: 1)))
        try expect(subject.intersects(RectD(x: 9, y: 0, width: 1, height: 1)))
    },
]
