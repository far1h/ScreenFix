import AppKit
import ScreenFixApp
import ScreenFixCore

private enum RuntimeCalibrationTestError: Error {
    case requested
}

private enum CalibrationTestMaskFailurePoint {
    case prepare
    case order
}

private final class CalibrationTestStore: RuntimeConfigurationStore {
    var configuration: ScreenFixConfiguration?
    var saveError: Error?
    var onSave: ((ScreenFixConfiguration) -> Void)?
    let log: NSMutableArray

    init(configuration: ScreenFixConfiguration?, log: NSMutableArray) {
        self.configuration = configuration
        self.log = log
    }

    func load() throws -> ScreenFixConfiguration? {
        log.add("load")
        return configuration
    }

    func save(_ configuration: ScreenFixConfiguration) throws {
        log.add("save")
        onSave?(configuration)
        if let saveError { throw saveError }
        self.configuration = configuration
    }
}

private final class CalibrationTestCatalog: RuntimeDisplayCatalog {
    var screens: [ConnectedScreen]
    let log: NSMutableArray

    init(screens: [ConnectedScreen], log: NSMutableArray) {
        self.screens = screens
        self.log = log
    }

    func connectedDisplays() -> [ConnectedScreen] {
        log.add("displays")
        return screens
    }
}

private final class CalibrationTestMasks: RuntimeMaskOwner {
    var committedCount = 0
    var failure: Error?
    var failureOnReplaceCall: Int?
    var failurePoint = CalibrationTestMaskFailurePoint.prepare
    var lastScreenFrame: NSRect?
    private(set) var replaceCount = 0
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func replace(
        frames: [RectD],
        screenFrame: NSRect,
        beforeRetire: () throws -> Void
    ) throws {
        replaceCount += 1
        log.add("mask-prepare")
        if let failure { throw failure }
        let scheduledFailure = failureOnReplaceCall == replaceCount
        if scheduledFailure, failurePoint == .prepare {
            throw RuntimeCalibrationTestError.requested
        }
        for index in 1...3 { log.add("mask-order-\(index)") }
        if scheduledFailure, failurePoint == .order {
            throw RuntimeCalibrationTestError.requested
        }
        try beforeRetire()
        if committedCount > 0 { log.add("mask-retire") }
        committedCount = frames.count
        lastScreenFrame = screenFrame
    }

    func removeAll() {
        guard committedCount > 0 else { return }
        log.add("mask-remove")
        committedCount = 0
        lastScreenFrame = nil
    }
}

private final class CalibrationTestNotifications: RuntimeNotifications {
    var displayChanged: (() -> Void)?
    var willSleep: (() -> Void)?
    var woke: (() -> Void)?
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func subscribe(
        displayChanged: @escaping () -> Void,
        willSleep: @escaping () -> Void,
        woke: @escaping () -> Void
    ) -> [AnyObject] {
        self.displayChanged = displayChanged
        self.willSleep = willSleep
        self.woke = woke
        return [NSObject(), NSObject(), NSObject()]
    }

    func unsubscribe(_ tokens: [AnyObject]) {
        log.add("unsubscribe")
    }
}

private final class CalibrationTestSession {
    let onSave: ([NormalizedRect]) throws -> Void
    let onCancel: () throws -> Void

    init(
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
    }
}

private final class CalibrationTestOwner: RuntimeCalibrationOwner {
    var failStart = false
    var isEditing = false
    private(set) var sessions: [CalibrationTestSession] = []
    private(set) var latestBands: [NormalizedRect] = []
    private(set) var latestFrame: NSRect?
    var onStop: (() -> Void)?
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func start(
        screenFrame: NSRect,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void,
        commitGuard: () throws -> Bool
    ) throws {
        log.add("editor-start")
        if failStart { throw RuntimeCalibrationTestError.requested }
        guard try commitGuard() else { throw RuntimeCalibrationTestError.requested }
        latestBands = bands
        latestFrame = screenFrame
        sessions.append(CalibrationTestSession(onSave: onSave, onCancel: onCancel))
        isEditing = true
    }

    func stop() {
        guard isEditing else { return }
        log.add("editor-stop")
        isEditing = false
        let callback = onStop
        onStop = nil
        callback?()
    }

    func save(_ bands: [NormalizedRect], session index: Int? = nil) throws {
        let resolved = index ?? sessions.count - 1
        try sessions[resolved].onSave(bands)
        if resolved == sessions.count - 1 { isEditing = false }
    }

    func cancel(session index: Int? = nil) throws {
        let resolved = index ?? sessions.count - 1
        try sessions[resolved].onCancel()
        if resolved == sessions.count - 1 { isEditing = false }
    }
}

private struct CalibrationRuntimeFixture {
    let log: NSMutableArray
    let store: CalibrationTestStore
    let catalog: CalibrationTestCatalog
    let masks: CalibrationTestMasks
    let editor: CalibrationTestOwner
    let notifications: CalibrationTestNotifications
    let runtime: RuntimeController
}

private func calibrationScreen(
    _ id: String,
    name: String = "Ultrawide",
    frame: NSRect = NSRect(x: 0, y: 0, width: 3440, height: 1440)
) -> ConnectedScreen {
    ConnectedScreen(
        display: ConnectedDisplay(
            stableId: id,
            name: name,
            width: frame.width,
            height: frame.height
        ),
        fullFrame: frame,
        nativeScreen: NSObject()
    )
}

private func calibrationConfig(_ id: String, enabled: Bool = true) -> ScreenFixConfiguration {
    DefaultConfiguration.make(
        for: DisplayIdentity(
            stableId: id,
            name: "Ultrawide",
            width: 3440,
            height: 1440
        ),
        enabled: enabled
    )
}

private func calibrationFixture(
    configuration: ScreenFixConfiguration?,
    screens: [ConnectedScreen]
) -> CalibrationRuntimeFixture {
    let log = NSMutableArray()
    let store = CalibrationTestStore(configuration: configuration, log: log)
    let catalog = CalibrationTestCatalog(screens: screens, log: log)
    let masks = CalibrationTestMasks(log: log)
    let editor = CalibrationTestOwner(log: log)
    let notifications = CalibrationTestNotifications(log: log)
    let runtime = RuntimeController(
        store: store,
        catalog: catalog,
        maskOwner: masks,
        calibrationOwner: editor,
        notifications: notifications,
        termination: {},
        stateDidChange: {}
    )
    return CalibrationRuntimeFixture(
        log: log,
        store: store,
        catalog: catalog,
        masks: masks,
        editor: editor,
        notifications: notifications,
        runtime: runtime
    )
}

private func editedCalibrationBands() -> [NormalizedRect] {
    [
        NormalizedRect(x: 0.30, y: 0, w: 0.20, h: 0.30),
        NormalizedRect(x: 0.30, y: 0.30, w: 0.20, h: 0.40),
        NormalizedRect(x: 0.30, y: 0.70, w: 0.20, h: 0.30),
    ]
}

private func calibrationEvents(_ value: CalibrationRuntimeFixture) -> [String] {
    value.log.compactMap { $0 as? String }
}

let runtimeCalibrationTests = [
    TestCase(name: "RuntimeCalibration starts from fresh live screen and keeps enabled masks") {
        let value = calibrationFixture(
            configuration: calibrationConfig("a"),
            screens: [calibrationScreen("a")]
        )
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.toggleCalibration()

        try expectEqual(calibrationEvents(value), ["displays", "editor-start", "displays"])
        try expectEqual(value.masks.committedCount, 3)
        try expectEqual(value.editor.latestBands, calibrationConfig("a").bands)
        try expect(value.runtime.snapshot.calibrating)
        try expect(value.runtime.snapshot.menuState.calibrating)
    },
    TestCase(name: "RuntimeCalibration checked toggle cancels without changing config") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        value.runtime.toggleCalibration()

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 3)
        try expect(calibrationEvents(value).contains("editor-stop"))
        try expect(!calibrationEvents(value).contains("save"))
    },
    TestCase(name: "RuntimeCalibration disabled Save preserves disabled state and removes temporary masks") {
        let value = calibrationFixture(
            configuration: calibrationConfig("a", enabled: false),
            screens: [calibrationScreen("a")]
        )
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.toggleCalibration()
        try expectEqual(value.masks.committedCount, 3)
        try value.editor.save(editedCalibrationBands())

        try expectEqual(value.runtime.snapshot.configuration?.bands, editedCalibrationBands())
        try expectEqual(value.runtime.snapshot.configuration?.enabled, false)
        try expectEqual(value.masks.committedCount, 0)
        try expect(!value.runtime.snapshot.calibrating)
    },
    TestCase(name: "RuntimeCalibration Save orders masks saves before retirement then closes editor") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        try value.editor.save(editedCalibrationBands())

        let events = calibrationEvents(value)
        let save = try eventIndex("save", in: events)
        let retire = try eventIndex("mask-retire", in: events)
        try expect(save < retire)
        try expectEqual(value.runtime.snapshot.configuration?.bands, editedCalibrationBands())
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 3)
    },
    TestCase(name: "RuntimeCalibration Save failure keeps editor config masks and working session") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.store.saveError = RuntimeCalibrationTestError.requested
        try expectThrows { try value.editor.save(editedCalibrationBands()) }

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.masks.committedCount, 3)
        try expect(value.runtime.snapshot.menuState.status?.contains("config error") == true)
    },
    TestCase(name: "RuntimeCalibration candidate mask failure keeps editor and prior transaction") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.masks.failure = RuntimeCalibrationTestError.requested
        try expectThrows { try value.editor.save(editedCalibrationBands()) }

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.masks.committedCount, 3)
        try expect(value.runtime.snapshot.menuState.status?.contains("mask error") == true)
    },
    TestCase(name: "RuntimeCalibration Cancel discards working changes without saving") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        try value.editor.cancel()

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expect(!calibrationEvents(value).contains("save"))
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 3)
    },
    TestCase(name: "RuntimeCalibration stale callbacks are inert after cancel reload and replacement") {
        let value = calibrationFixture(
            configuration: calibrationConfig("a"),
            screens: [calibrationScreen("a"), calibrationScreen("b", name: "Second")]
        )
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.runtime.toggleCalibration()
        let afterCancel = value.runtime.snapshot
        try value.editor.sessions[0].onSave(editedCalibrationBands())
        try value.editor.sessions[0].onCancel()
        try expectEqual(value.runtime.snapshot.configuration, afterCancel.configuration)

        value.runtime.toggleCalibration()
        value.runtime.reload()
        let afterReload = value.runtime.snapshot
        try value.editor.sessions[1].onSave(editedCalibrationBands())
        try expectEqual(value.runtime.snapshot.configuration, afterReload.configuration)

        value.runtime.selectDisplay(stableId: "b")
        let afterReplacement = value.runtime.snapshot
        try value.editor.sessions[1].onCancel()
        try expectEqual(value.runtime.snapshot.configuration, afterReplacement.configuration)
    },
    TestCase(name: "RuntimeCalibration vanished monitor row preserves the active editor transaction") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        let before = value.runtime.snapshot

        value.runtime.selectDisplay(stableId: "vanished-row")

        try expectEqual(value.runtime.snapshot.configuration, before.configuration)
        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.masks.committedCount, 3)
    },
    TestCase(name: "RuntimeCalibration editor startup failure preserves ordinary runtime") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.editor.failStart = true
        value.runtime.toggleCalibration()

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expectEqual(value.masks.committedCount, 3)
        try expect(!value.runtime.snapshot.calibrating)
        try expect(value.runtime.snapshot.menuState.status?.contains("calibration error") == true)
    },
    TestCase(name: "RuntimeCalibration first monitor selection is provisional until Save") {
        let value = calibrationFixture(configuration: nil, screens: [calibrationScreen("b")])
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.selectDisplay(stableId: "b")

        try expectEqual(value.runtime.snapshot.configuration, nil)
        try expect(value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 3)
        try expect(!calibrationEvents(value).contains("save"))
        try value.editor.cancel()
        try expectEqual(value.runtime.snapshot.configuration, nil)
        try expectEqual(value.masks.committedCount, 0)
    },
    TestCase(name: "RuntimeCalibration replacement monitor Cancel restores prior config and masks") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(
            configuration: original,
            screens: [calibrationScreen("a"), calibrationScreen("b", name: "Second")]
        )
        value.runtime.start()
        value.runtime.selectDisplay(stableId: "b")
        try expectEqual(value.runtime.snapshot.configuration, original)
        try value.editor.cancel()

        try expectEqual(value.runtime.snapshot.configuration, original)
        try expectEqual(value.masks.committedCount, 3)
        try expectEqual(value.masks.lastScreenFrame, calibrationScreen("a").fullFrame)
    },
    TestCase(name: "RuntimeCalibration provisional Save persists only chosen display and edits") {
        let original = calibrationConfig("a")
        let secondFrame = NSRect(x: -2560, y: -400, width: 2560, height: 1440)
        let value = calibrationFixture(
            configuration: original,
            screens: [calibrationScreen("a"), calibrationScreen("b", name: "Second", frame: secondFrame)]
        )
        value.runtime.start()
        value.runtime.selectDisplay(stableId: "b")
        try value.editor.save(editedCalibrationBands())

        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "b")
        try expectEqual(value.runtime.snapshot.configuration?.bands, editedCalibrationBands())
        try expectEqual(value.masks.lastScreenFrame, secondFrame)
    },
    TestCase(name: "RuntimeCalibration provisional editor failure restores prior or empty masks") {
        for original in [calibrationConfig("a") as ScreenFixConfiguration?, nil] {
            let screens = original == nil
                ? [calibrationScreen("b")]
                : [calibrationScreen("a"), calibrationScreen("b", name: "Second")]
            let value = calibrationFixture(configuration: original, screens: screens)
            value.runtime.start()
            value.editor.failStart = true
            value.runtime.selectDisplay(stableId: "b")

            try expectEqual(value.runtime.snapshot.configuration, original)
            try expectEqual(value.masks.committedCount, original == nil ? 0 : 3)
        }
    },
    TestCase(name: "RuntimeCalibration provisional editor failure removes masks when rollback fails") {
        for failurePoint in [CalibrationTestMaskFailurePoint.prepare, .order] {
            let original = calibrationConfig("a")
            let second = calibrationScreen("b", name: "Second")
            let value = calibrationFixture(
                configuration: original,
                screens: [calibrationScreen("a"), second]
            )
            value.runtime.start()
            value.editor.failStart = true
            value.masks.failureOnReplaceCall = 3
            value.masks.failurePoint = failurePoint

            value.runtime.selectDisplay(stableId: "b")

            try expectEqual(value.runtime.snapshot.configuration, original)
            try expectEqual(value.masks.committedCount, 0)
            try expectEqual(value.masks.lastScreenFrame, nil)
        }
    },
    TestCase(name: "RuntimeCalibration provisional Cancel removes masks when rollback fails") {
        for failurePoint in [CalibrationTestMaskFailurePoint.prepare, .order] {
            let original = calibrationConfig("a")
            let second = calibrationScreen("b", name: "Second")
            let value = calibrationFixture(
                configuration: original,
                screens: [calibrationScreen("a"), second]
            )
            value.runtime.start()
            value.runtime.selectDisplay(stableId: "b")
            value.masks.failureOnReplaceCall = 3
            value.masks.failurePoint = failurePoint

            try value.editor.cancel()

            try expectEqual(value.runtime.snapshot.configuration, original)
            try expectEqual(value.masks.committedCount, 0)
            try expectEqual(value.masks.lastScreenFrame, nil)
        }
    },
    TestCase(name: "RuntimeCalibration identical replacement screen keeps the active editor") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        value.catalog.screens = [calibrationScreen("a")]

        value.runtime.reconcile()

        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.editor.sessions.count, 1)
        try expect(!calibrationEvents(value).contains("editor-stop"))
        try expect(!calibrationEvents(value).contains("mask-prepare"))
    },
    TestCase(name: "RuntimeCalibration frame topology changes cancel and rebuild saved masks") {
        let changes = [
            NSRect(x: -200, y: 0, width: 3440, height: 1440),
            NSRect(x: 0, y: 0, width: 3000, height: 1440),
            NSRect(x: 0, y: 0, width: 3440, height: 1200),
        ]
        for changedFrame in changes {
            let original = calibrationConfig("a")
            let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
            value.runtime.start()
            value.runtime.toggleCalibration()
            value.catalog.screens = [calibrationScreen("a", frame: changedFrame)]
            value.runtime.reconcile()

            try expect(!value.runtime.snapshot.calibrating)
            try expect(!value.editor.isEditing)
            try expectEqual(value.runtime.snapshot.configuration, original)
            try expectEqual(value.masks.lastScreenFrame, changedFrame)
        }
    },
    TestCase(name: "RuntimeCalibration disconnect cancels before masks and reconnect never resurrects editor") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        value.catalog.screens = []
        value.runtime.reconcile()
        let disconnectedEvents = calibrationEvents(value)

        let editorStop = try eventIndex("editor-stop", in: disconnectedEvents)
        let maskRemove = try eventIndex("mask-remove", in: disconnectedEvents)
        try expect(editorStop < maskRemove)
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 0)

        value.catalog.screens = [calibrationScreen("a")]
        value.runtime.reconcile()
        try expectEqual(value.masks.committedCount, 3)
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.editor.sessions.count, 1)
    },
    TestCase(name: "RuntimeCalibration sleep cancels editor and wake uses fresh topology") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        let staleSession = value.editor.sessions[0]
        value.catalog.screens = [calibrationScreen("a")]
        value.notifications.willSleep?()
        try expect(!value.runtime.snapshot.calibrating)
        value.notifications.woke?()
        try expect(!value.runtime.snapshot.calibrating)

        let moved = NSRect(x: -3440, y: -100, width: 3440, height: 1440)
        value.catalog.screens = [calibrationScreen("a", frame: moved)]
        value.notifications.willSleep?()
        value.notifications.woke?()
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.lastScreenFrame, moved)
        try staleSession.onSave(editedCalibrationBands())
        try staleSession.onCancel()
        try expectEqual(value.runtime.snapshot.configuration, calibrationConfig("a"))
    },
    TestCase(name: "RuntimeCalibration invalid or too-small frames fail before editor allocation") {
        let frames = [
            NSRect(x: CGFloat.nan, y: 0, width: 3440, height: 1440),
            NSRect(x: 0, y: CGFloat.infinity, width: 3440, height: 1440),
            NSRect(x: 0, y: 0, width: 259, height: 180),
            NSRect(x: 0, y: 0, width: 260, height: 179),
        ]
        for frame in frames {
            let value = calibrationFixture(configuration: nil, screens: [calibrationScreen("a", frame: frame)])
            value.runtime.start()
            value.log.removeAllObjects()
            value.runtime.selectDisplay(stableId: "a")

            try expect(!value.runtime.snapshot.calibrating)
            try expect(!calibrationEvents(value).contains("editor-start"))
            try expectEqual(value.masks.committedCount, 0)
        }
    },
    TestCase(name: "RuntimeCalibration topology cancellation revokes old callbacks") {
        let original = calibrationConfig("a")
        let value = calibrationFixture(configuration: original, screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.catalog.screens = []
        value.runtime.reconcile()

        try value.editor.sessions[0].onSave(editedCalibrationBands())
        try value.editor.sessions[0].onCancel()
        try expectEqual(value.runtime.snapshot.configuration, original)
        try expect(!value.runtime.snapshot.calibrating)
        try expectEqual(value.masks.committedCount, 0)
    },
    TestCase(name: "RuntimeCalibration teardown reentrancy cannot retire a newer editor") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.editor.onStop = { value.runtime.toggleCalibration() }

        value.runtime.toggleCalibration()

        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.editor.sessions.count, 2)
    },
    TestCase(name: "RuntimeCalibration reentrant Save serializes before the newer monitor editor") {
        let value = calibrationFixture(
            configuration: calibrationConfig("a"),
            screens: [calibrationScreen("a"), calibrationScreen("b", name: "Second")]
        )
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.store.onSave = { _ in
            value.store.onSave = nil
            value.runtime.selectDisplay(stableId: "b")
        }

        try value.editor.save(editedCalibrationBands(), session: 0)

        try expect(value.runtime.snapshot.calibrating)
        try expect(value.editor.isEditing)
        try expectEqual(value.editor.sessions.count, 2)
        try expectEqual(value.editor.latestFrame, calibrationScreen("b", name: "Second").fullFrame)
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(value.runtime.snapshot.configuration?.bands, editedCalibrationBands())
        try expectEqual(value.store.configuration, value.runtime.snapshot.configuration)
        try expectEqual(value.masks.lastScreenFrame, calibrationScreen("b", name: "Second").fullFrame)
    },
    TestCase(name: "RuntimeCalibration stop orders callbacks editor and masks and remains inert") {
        let value = calibrationFixture(configuration: calibrationConfig("a"), screens: [calibrationScreen("a")])
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()
        let staleWake = value.notifications.woke

        value.runtime.stop()
        value.runtime.stop()
        staleWake?()
        let events = calibrationEvents(value)

        let unsubscribe = try eventIndex("unsubscribe", in: events)
        let editorStop = try eventIndex("editor-stop", in: events)
        let maskRemove = try eventIndex("mask-remove", in: events)
        try expect(unsubscribe < editorStop)
        try expect(editorStop < maskRemove)
        try expectEqual(events.filter { $0 == "unsubscribe" }.count, 1)
        try expectEqual(events.filter { $0 == "editor-stop" }.count, 1)
        try expectEqual(events.filter { $0 == "mask-remove" }.count, 1)
        try expect(!value.editor.isEditing)
        try expectEqual(value.masks.committedCount, 0)
    },
]

private func eventIndex(_ value: String, in events: [String]) throws -> Int {
    guard let index = events.firstIndex(of: value) else {
        throw TestFailure(description: "missing event \(value)")
    }
    return index
}
