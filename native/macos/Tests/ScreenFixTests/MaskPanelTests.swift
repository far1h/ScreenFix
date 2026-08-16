import AppKit
import ScreenFixApp
import ScreenFixCore

private enum FakeMaskError: Error {
    case requested
}

private final class FakeMaskWindow: MaskWindow {
    let identifier: Int
    let frame: NSRect
    let ignoresMouseEvents: Bool
    private let log: NSMutableArray
    private let failOrder: Bool

    init(
        identifier: Int,
        frame: NSRect = .zero,
        log: NSMutableArray,
        failOrder: Bool = false,
        ignoresMouseEvents: Bool = true
    ) {
        self.identifier = identifier
        self.frame = frame
        self.log = log
        self.failOrder = failOrder
        self.ignoresMouseEvents = ignoresMouseEvents
    }

    func orderAndVerify() throws {
        log.add("order-\(identifier)")
        log.add("verify-\(identifier)")
        if failOrder { throw FakeMaskError.requested }
    }

    func close() {
        log.add("close-\(identifier)")
    }
}

private func eventStrings(_ log: NSMutableArray) -> [String] {
    log.compactMap { $0 as? String }
}

private func makeController(
    log: NSMutableArray,
    failCreateAt: Int? = nil,
    failOrderAt: Int? = nil,
    old: [FakeMaskWindow] = []
) -> MaskPanelController {
    var nextIdentifier = 0
    return MaskPanelController(
        factory: { frame in
            nextIdentifier += 1
            log.add("create-\(nextIdentifier)")
            if nextIdentifier == failCreateAt { throw FakeMaskError.requested }
            return FakeMaskWindow(
                identifier: nextIdentifier,
                frame: frame,
                log: log,
                failOrder: nextIdentifier == failOrderAt
            )
        },
        initialCommitted: old
    )
}

private let defaultLocalFrames = [
    RectD(x: 1215, y: 0, width: 705, height: 489.6),
    RectD(x: 1215, y: 489.6, width: 705, height: 561.6),
    RectD(x: 1215, y: 1051.2, width: 705, height: 388.8),
]

let maskPanelTests = [
    TestCase(name: "MaskPanel has nonactivating opaque click-through properties") {
        _ = NSApplication.shared
        let frame = NSRect(x: 10, y: 20, width: 30, height: 40)
        let panel = MaskPanelFactory().make(frame: frame)
        defer { panel.close() }

        try expectEqual(panel.frame, frame)
        try expect(panel.styleMask.contains(.nonactivatingPanel))
        try expect(!panel.styleMask.contains(.titled))
        try expect(!panel.styleMask.contains(.closable))
        try expect(!panel.styleMask.contains(.miniaturizable))
        try expect(!panel.styleMask.contains(.resizable))
        try expect(panel.isOpaque)
        try expectEqual(panel.backgroundColor, .black)
        try expect(!panel.hasShadow)
        try expect(panel.ignoresMouseEvents)
        try expect(!panel.hidesOnDeactivate)
        try expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        try expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        try expect(panel.collectionBehavior.contains(.stationary))
        try expect(!panel.canBecomeKey)
        try expect(!panel.canBecomeMain)
        try expectEqual(
            panel.level.rawValue,
            NSWindow.Level.screenSaver.rawValue
        )
        try expect(panel.level.rawValue > NSWindow.Level.statusBar.rawValue)
        try expect(panel.level.rawValue > NSWindow.Level.popUpMenu.rawValue)
        try expect(
            panel.level.rawValue
                < Int(CGWindowLevelForKey(.assistiveTechHighWindow))
        )
    },
    TestCase(name: "MaskPanel does not constrain a full-frame mask to visibleFrame") {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else {
            throw TestFailure(description: "main screen unavailable")
        }
        let requested = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - 100,
            width: 100,
            height: 100
        )
        let panel = MaskPanelFactory().make(frame: requested)
        defer { panel.close() }

        try expectEqual(panel.constrainFrameRect(requested, to: screen), requested)
    },
    TestCase(name: "MaskPanel prepare creates exactly three converted candidates") {
        let log = NSMutableArray()
        let controller = makeController(log: log)
        let prepared = try controller.prepare(
            frames: defaultLocalFrames,
            screenFrame: NSRect(x: -3440, y: -900, width: 3440, height: 1440)
        )
        defer { controller.discard(prepared) }

        try expectEqual(prepared.windows.count, 3)
        let expectedFrames = [
            NSRect(x: -2225, y: 50.4, width: 705, height: 489.6),
            NSRect(x: -2225, y: -511.2, width: 705, height: 561.6),
            NSRect(x: -2225, y: -900, width: 705, height: 388.8),
        ]
        for (actual, expected) in zip(prepared.windows.map(\.frame), expectedFrames) {
            try expectEqual(actual.origin.x, expected.origin.x, accuracy: 1e-12)
            try expectEqual(actual.origin.y, expected.origin.y, accuracy: 1e-12)
            try expectEqual(actual.width, expected.width, accuracy: 1e-12)
            try expectEqual(actual.height, expected.height, accuracy: 1e-12)
        }
        try expectEqual(eventStrings(log), ["create-1", "create-2", "create-3"])
        try expect(prepared.windows.allSatisfy(\.ignoresMouseEvents))
    },
    TestCase(name: "MaskPanel prepare failure closes candidates and preserves old windows") {
        for failure in [2, 3] {
            let log = NSMutableArray()
            let old = FakeMaskWindow(identifier: 90, log: log)
            let controller = makeController(log: log, failCreateAt: failure, old: [old])
            try expectThrows {
                _ = try controller.prepare(frames: defaultLocalFrames, screenFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440))
            }
            let expected = failure == 2
                ? ["create-1", "create-2", "close-1"]
                : ["create-1", "create-2", "create-3", "close-1", "close-2"]
            try expectEqual(eventStrings(log), expected)
            try expectEqual(controller.committedCount, 1)
        }
    },
    TestCase(name: "MaskPanel discard is single-use and preserves committed windows") {
        let log = NSMutableArray()
        let old = FakeMaskWindow(identifier: 90, log: log)
        let controller = makeController(log: log, old: [old])
        let prepared = try controller.prepare(frames: defaultLocalFrames, screenFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440))
        controller.discard(prepared)
        controller.discard(prepared)

        try expectEqual(eventStrings(log), ["create-1", "create-2", "create-3", "close-1", "close-2", "close-3"])
        try expectEqual(controller.committedCount, 1)
    },
    TestCase(name: "MaskPanel commit orders and verifies before retiring old masks") {
        let log = NSMutableArray()
        let old = FakeMaskWindow(identifier: 90, log: log)
        let controller = makeController(log: log, old: [old])
        let prepared = try controller.prepare(frames: defaultLocalFrames, screenFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440))
        try controller.commit(prepared) { log.add("before-retire") }
        try controller.commit(prepared) { log.add("second-retire") }

        try expectEqual(eventStrings(log), [
            "create-1", "create-2", "create-3",
            "order-1", "verify-1", "order-2", "verify-2", "order-3", "verify-3",
            "before-retire", "close-90",
        ])
        try expectEqual(controller.committedCount, 3)
        try expect(controller.committedWindowsIgnoreMouseEvents)
    },
    TestCase(name: "MaskPanel order failure closes candidates and preserves old masks") {
        for failure in [1, 2, 3] {
            let log = NSMutableArray()
            let old = FakeMaskWindow(identifier: 90, log: log)
            let controller = makeController(log: log, failOrderAt: failure, old: [old])
            let prepared = try controller.prepare(frames: defaultLocalFrames, screenFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440))
            try expectThrows { try controller.commit(prepared) { log.add("before-retire") } }
            try expect(!eventStrings(log).contains("before-retire"))
            try expect(!eventStrings(log).contains("close-90"))
            try expectEqual(Array(eventStrings(log).suffix(3)), ["close-1", "close-2", "close-3"])
            try expectEqual(controller.committedCount, 1)
        }
    },
    TestCase(name: "MaskPanel before-retire failure closes candidates and preserves old masks") {
        let log = NSMutableArray()
        let old = FakeMaskWindow(identifier: 90, log: log)
        let controller = makeController(log: log, old: [old])
        let prepared = try controller.prepare(frames: defaultLocalFrames, screenFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440))

        try expectThrows {
            try controller.commit(prepared) {
                log.add("before-retire")
                throw FakeMaskError.requested
            }
        }
        try expectEqual(Array(eventStrings(log).suffix(4)), ["before-retire", "close-1", "close-2", "close-3"])
        try expect(!eventStrings(log).contains("close-90"))
        try expectEqual(controller.committedCount, 1)
    },
    TestCase(name: "MaskPanel removeAll is idempotent") {
        let log = NSMutableArray()
        let old = FakeMaskWindow(identifier: 90, log: log)
        let controller = makeController(log: log, old: [old])
        controller.removeAll()
        controller.removeAll()
        try expectEqual(eventStrings(log), ["close-90"])
        try expectEqual(controller.committedCount, 0)
    },
]
