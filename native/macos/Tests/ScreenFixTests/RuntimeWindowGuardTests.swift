import AppKit
import ApplicationServices
import ScreenFixApp
import ScreenFixCore

private enum RuntimeWindowGuardTestError: Error {
    case requested
}

private final class RuntimeWindowGuardStore: RuntimeConfigurationStore {
    var configuration: ScreenFixConfiguration?
    var loadError: Error?
    var saveError: Error?
    var onLoad: (() -> Void)?
    var onSave: (() -> Void)?
    let log: NSMutableArray

    init(configuration: ScreenFixConfiguration?, log: NSMutableArray) {
        self.configuration = configuration
        self.log = log
    }

    func load() throws -> ScreenFixConfiguration? {
        log.add("load")
        onLoad?()
        if let loadError { throw loadError }
        return configuration
    }

    func save(_ configuration: ScreenFixConfiguration) throws {
        log.add("save")
        onSave?()
        if let saveError { throw saveError }
        self.configuration = configuration
    }
}

private final class RuntimeWindowGuardCatalog: RuntimeDisplayCatalog {
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

private final class RuntimeWindowGuardMasks: RuntimeMaskOwner {
    var failReplace = false
    var onPrepare: (() -> Void)?
    private(set) var hasMasks = false
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func replace(
        frames: [RectD],
        screenFrame: NSRect,
        beforeRetire: () throws -> Void
    ) throws {
        log.add("masks-prepare")
        onPrepare?()
        if failReplace { throw RuntimeWindowGuardTestError.requested }
        try beforeRetire()
        log.add("masks-commit")
        hasMasks = true
    }

    func removeAll() {
        guard hasMasks else { return }
        log.add("masks-remove")
        hasMasks = false
    }
}

private final class RuntimeWindowGuardCalibration: RuntimeCalibrationOwner {
    var onSave: (([NormalizedRect]) throws -> Void)?
    var onCancel: (() throws -> Void)?
    private(set) var isEditing = false
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func start(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void,
        commitGuard: () throws -> Bool
    ) throws {
        log.add("editor-start")
        guard try commitGuard() else { throw RuntimeWindowGuardTestError.requested }
        self.onSave = onSave
        self.onCancel = onCancel
        isEditing = true
    }

    func stop() {
        log.add("editor-stop")
        isEditing = false
    }

    func save(_ bands: [NormalizedRect]) throws {
        try onSave?(bands)
        isEditing = false
    }

    func cancel() throws {
        try onCancel?()
        isEditing = false
    }
}

private final class RuntimeWindowGuardNotifications: RuntimeNotifications {
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
        log.add("subscribe")
        self.displayChanged = displayChanged
        self.willSleep = willSleep
        self.woke = woke
        return [NSObject(), NSObject(), NSObject()]
    }

    func unsubscribe(_ tokens: [AnyObject]) {
        log.add("unsubscribe")
    }
}

private final class RuntimeWindowGuardTrust: RuntimeAccessibilityTrustOwner {
    var trusted: Bool
    private(set) var needsPermission: [Bool] = []
    let log: NSMutableArray

    init(trusted: Bool, log: NSMutableArray) {
        self.trusted = trusted
        self.log = log
    }

    var isTrusted: Bool { trusted }

    func reconcile(needsPermission: Bool) -> Bool {
        log.add("trust-\(needsPermission)")
        self.needsPermission.append(needsPermission)
        return needsPermission && trusted
    }

    func stop() {
        log.add("trust-stop")
    }
}

private final class RuntimeWindowGuardOwnerFake: RuntimeWindowGuardOwner {
    private(set) var target: WindowGuardTarget?
    private(set) var starts: [WindowGuardTarget] = []
    private(set) var stopCount = 0
    private(set) var events: [AXWindowEvent] = []
    private(set) var staleLaneWrites = 0
    private var generation = 0
    private var stagedLane: (() -> Void)?
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func start(target: WindowGuardTarget) {
        generation += 1
        log.add("guard-start-\(target.selectedDisplayID)")
        starts.append(target)
        self.target = target
    }

    func stop() {
        generation += 1
        log.add("guard-stop")
        stopCount += 1
        target = nil
    }

    func handle(_ event: AXWindowEvent) {
        events.append(event)
    }

    func stageOldLaneWrite() {
        let stagedGeneration = generation
        stagedLane = { [weak self] in
            guard let self, self.generation == stagedGeneration else { return }
            self.staleLaneWrites += 1
        }
    }

    func flushOldLane() {
        let lane = stagedLane
        stagedLane = nil
        lane?()
    }
}

private final class RuntimeWindowGuardOrderedTimer: WindowGuardTimer {
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func cancel() {
        log.add("timer-cancel")
    }
}

private final class RuntimeWindowGuardOrderedSource: WindowGuardEventSource {
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func start() {}

    func stop() {
        log.add("source-stop")
    }

    func lane(for pid: pid_t) -> AXWorkLane? {
        nil
    }
}

private final class RuntimeWindowGuardUnusedAccess: WindowGuardWindowAccess {
    func facts(
        for identity: AXWindowIdentity,
        screenFixPID: pid_t,
        target: WindowGuardTarget
    ) throws -> WindowFacts {
        throw RuntimeWindowGuardTestError.requested
    }

    func isSizeSettable(for identity: AXWindowIdentity) throws -> Bool {
        false
    }

    func setSize(_ size: CGSize, for identity: AXWindowIdentity) throws {}
    func setPosition(_ position: CGPoint, for identity: AXWindowIdentity) throws {}

    func frame(for identity: AXWindowIdentity) throws -> RectD {
        throw RuntimeWindowGuardTestError.requested
    }
}

private struct RuntimeWindowGuardFixture {
    let log: NSMutableArray
    let store: RuntimeWindowGuardStore
    let catalog: RuntimeWindowGuardCatalog
    let masks: RuntimeWindowGuardMasks
    let calibration: RuntimeWindowGuardCalibration
    let notifications: RuntimeWindowGuardNotifications
    let trust: RuntimeWindowGuardTrust
    let guardOwner: RuntimeWindowGuardOwnerFake
    let runtime: RuntimeController
}

private func runtimeWindowGuardScreen(
    _ id: String,
    topLeftFrame: RectD,
    workArea: RectD? = nil
) -> ConnectedScreen {
    ConnectedScreen(
        display: ConnectedDisplay(
            stableId: id,
            name: "Display \(id)",
            width: topLeftFrame.width,
            height: topLeftFrame.height
        ),
        fullFrame: NSRect(
            x: topLeftFrame.x,
            y: topLeftFrame.y,
            width: topLeftFrame.width,
            height: topLeftFrame.height
        ),
        topLeftFullFrame: topLeftFrame,
        topLeftVisibleFrame: workArea ?? topLeftFrame,
        nativeScreen: NSObject()
    )
}

private func runtimeWindowGuardConfig(_ id: String, enabled: Bool = true) -> ScreenFixConfiguration {
    DefaultConfiguration.make(
        for: DisplayIdentity(
            stableId: id,
            name: "Display \(id)",
            width: 1000,
            height: 800
        ),
        enabled: enabled
    )
}

private func runtimeWindowGuardFixture(
    configuration: ScreenFixConfiguration?,
    screens: [ConnectedScreen],
    trusted: Bool = true,
    termination: @escaping () -> Void = {}
) -> RuntimeWindowGuardFixture {
    let log = NSMutableArray()
    let store = RuntimeWindowGuardStore(configuration: configuration, log: log)
    let catalog = RuntimeWindowGuardCatalog(screens: screens, log: log)
    let masks = RuntimeWindowGuardMasks(log: log)
    let calibration = RuntimeWindowGuardCalibration(log: log)
    let notifications = RuntimeWindowGuardNotifications(log: log)
    let trust = RuntimeWindowGuardTrust(trusted: trusted, log: log)
    let guardOwner = RuntimeWindowGuardOwnerFake(log: log)
    let runtime = RuntimeController(
        store: store,
        catalog: catalog,
        maskOwner: masks,
        calibrationOwner: calibration,
        accessibilityTrustOwner: trust,
        windowGuardOwner: guardOwner,
        notifications: notifications,
        termination: termination,
        stateDidChange: {}
    )
    return RuntimeWindowGuardFixture(
        log: log,
        store: store,
        catalog: catalog,
        masks: masks,
        calibration: calibration,
        notifications: notifications,
        trust: trust,
        guardOwner: guardOwner,
        runtime: runtime
    )
}

private func runtimeWindowGuardEvents(_ value: RuntimeWindowGuardFixture) -> [String] {
    value.log.compactMap { $0 as? String }
}

private func runtimeWindowGuardIndex(_ event: String, in events: [String]) throws -> Int {
    guard let index = events.firstIndex(of: event) else {
        throw TestFailure(description: "missing event \(event) in \(events)")
    }
    return index
}

private func expectRuntimeWindowGuardOrder(
    _ first: String,
    _ second: String,
    in events: [String]
) throws {
    let firstIndex = try runtimeWindowGuardIndex(first, in: events)
    let secondIndex = try runtimeWindowGuardIndex(second, in: events)
    try expect(firstIndex < secondIndex)
}

let runtimeWindowGuardTests = [
    TestCase(name: "RuntimeWindowGuard startup commits masks before exact target") {
        let selected = runtimeWindowGuardScreen(
            "actual-a",
            topLeftFrame: RectD(x: 100, y: 200, width: 1000, height: 800),
            workArea: RectD(x: 100, y: 230, width: 1000, height: 770)
        )
        let other = runtimeWindowGuardScreen(
            "other",
            topLeftFrame: RectD(x: -900, y: 0, width: 1000, height: 700)
        )
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("actual-a"),
            screens: [selected, other]
        )

        value.runtime.start()

        let events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("masks-commit", "guard-start-actual-a", in: events)
        let expected = WindowGuardTarget(
            selectedDisplayID: "actual-a",
            workArea: selected.topLeftVisibleFrame,
            masks: MaskGeometry.absoluteTopLeftFrames(
                bands: runtimeWindowGuardConfig("actual-a").bands,
                in: TopLeftDisplayBounds(x: 100, y: 200, width: 1000, height: 800)
            ),
            displays: [
                DisplayFrame(stableID: "actual-a", frame: selected.topLeftFullFrame),
                DisplayFrame(stableID: "other", frame: other.topLeftFullFrame),
            ]
        )
        try expectEqual(value.guardOwner.target, expected)
        try expectEqual(value.guardOwner.starts.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard untrusted startup keeps masks and follows trust changes once") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )],
            trusted: false
        )
        value.runtime.start()

        try expect(value.masks.hasMasks)
        try expectEqual(value.guardOwner.starts.count, 0)
        try expectEqual(
            value.runtime.snapshot.menuState.status,
            "Window correction paused: Allow Accessibility in System Settings"
        )

        value.trust.trusted = true
        value.runtime.accessibilityTrustDidChange(true)
        value.runtime.accessibilityTrustDidChange(true)
        try expectEqual(value.guardOwner.starts.count, 1)

        value.trust.trusted = false
        value.runtime.accessibilityTrustDidChange(false)
        try expectEqual(value.guardOwner.stopCount, 1)
        try expect(value.masks.hasMasks)
        try expectEqual(
            value.runtime.snapshot.menuState.status,
            "Window correction paused: Allow Accessibility in System Settings"
        )
    },
    TestCase(name: "RuntimeWindowGuard prompts only when correction is needed") {
        let screen = runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
        )
        for configuration in [
            nil,
            runtimeWindowGuardConfig("a", enabled: false),
            runtimeWindowGuardConfig("missing"),
        ] {
            let value = runtimeWindowGuardFixture(
                configuration: configuration,
                screens: [screen],
                trusted: false
            )
            value.runtime.start()
            try expect(!value.trust.needsPermission.contains(true))
            try expectEqual(value.guardOwner.starts.count, 0)
        }
    },
    TestCase(name: "RuntimeWindowGuard calibration retires correction and Save restores after masks") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.log.removeAllObjects()

        value.runtime.toggleCalibration()
        var events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("guard-stop", "editor-start", in: events)
        try expectRuntimeWindowGuardOrder("trust-stop", "editor-start", in: events)

        value.log.removeAllObjects()
        try value.calibration.save(runtimeWindowGuardConfig("a").bands)
        events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("masks-commit", "guard-start-a", in: events)
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard calibration Cancel restores exactly one guard after masks") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.runtime.toggleCalibration()
        value.log.removeAllObjects()

        try value.calibration.cancel()

        let events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("masks-commit", "guard-start-a", in: events)
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard failed Disable rebuilds old guard after save") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.store.saveError = RuntimeWindowGuardTestError.requested
        value.log.removeAllObjects()

        value.runtime.setEnabled(false)

        let events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("guard-stop", "save", in: events)
        try expectRuntimeWindowGuardOrder("save", "guard-start-a", in: events)
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)
        try expectEqual(value.runtime.snapshot.configuration?.enabled, true)
        try expect(value.masks.hasMasks)
    },
    TestCase(name: "RuntimeWindowGuard Disable blocks reentrant trust restart until save returns") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        var guardWasActiveDuringSave = false
        value.store.onSave = {
            value.runtime.accessibilityTrustDidChange(true)
            guardWasActiveDuringSave = value.guardOwner.target != nil
        }
        value.store.saveError = RuntimeWindowGuardTestError.requested

        value.runtime.setEnabled(false)

        try expect(!guardWasActiveDuringSave)
        try expectEqual(value.guardOwner.target?.selectedDisplayID, "a")
        try expectEqual(value.guardOwner.starts.count, 2)
    },
    TestCase(name: "RuntimeWindowGuard successful Disable stops before save and masks") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.log.removeAllObjects()

        value.runtime.setEnabled(false)

        let events = runtimeWindowGuardEvents(value)
        let stop = try runtimeWindowGuardIndex("guard-stop", in: events)
        let save = try runtimeWindowGuardIndex("save", in: events)
        let masks = try runtimeWindowGuardIndex("masks-remove", in: events)
        try expect(stop < save)
        try expect(stop < masks)
        try expectEqual(value.guardOwner.target, nil)
        try expect(!value.masks.hasMasks)
    },
    TestCase(name: "RuntimeWindowGuard reload is transactional around masks and target") {
        let first = runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
        )
        let second = runtimeWindowGuardScreen(
            "b",
            topLeftFrame: RectD(x: -1400, y: 120, width: 1200, height: 900),
            workArea: RectD(x: -1400, y: 145, width: 1200, height: 875)
        )
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [first, second]
        )
        value.runtime.start()
        let oldTarget = value.guardOwner.target

        value.store.loadError = RuntimeWindowGuardTestError.requested
        value.log.removeAllObjects()
        value.runtime.reload()
        try expectEqual(value.guardOwner.target, oldTarget)
        try expect(value.masks.hasMasks)
        try expect(!runtimeWindowGuardEvents(value).contains("guard-stop"))

        value.store.loadError = nil
        value.store.configuration = runtimeWindowGuardConfig("b")
        value.log.removeAllObjects()
        value.runtime.reload()
        var events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("masks-commit", "guard-start-b", in: events)
        try expectEqual(value.guardOwner.target?.selectedDisplayID, "b")

        value.store.configuration = runtimeWindowGuardConfig("a")
        value.masks.failReplace = true
        value.log.removeAllObjects()
        value.runtime.reload()
        events = runtimeWindowGuardEvents(value)
        try expectEqual(value.guardOwner.target?.selectedDisplayID, "b")
        try expect(value.masks.hasMasks)
        try expect(!events.contains("guard-start-a"))
        try expectRuntimeWindowGuardOrder("guard-stop", "masks-prepare", in: events)
        try expectRuntimeWindowGuardOrder("masks-prepare", "guard-start-b", in: events)
        try expectEqual(events.filter { $0 == "guard-start-b" }.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard invalidates an old PID lane before replacement masks") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.guardOwner.stageOldLaneWrite()
        value.masks.onPrepare = { value.guardOwner.flushOldLane() }
        value.log.removeAllObjects()

        value.runtime.reload()

        let events = runtimeWindowGuardEvents(value)
        try expectEqual(value.guardOwner.staleLaneWrites, 0)
        try expectRuntimeWindowGuardOrder("guard-stop", "masks-prepare", in: events)
        try expectRuntimeWindowGuardOrder("masks-commit", "guard-start-a", in: events)
    },
    TestCase(name: "RuntimeWindowGuard reentrant stop cannot commit reset masks or guard") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.store.onSave = { value.runtime.stop() }

        value.runtime.resetToDefaults()

        try expect(!value.masks.hasMasks)
        try expectEqual(value.guardOwner.target, nil)
    },
    TestCase(name: "RuntimeWindowGuard reentrant stop makes reload result stale") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.store.onLoad = { value.runtime.stop() }

        value.runtime.reload()

        try expect(!value.masks.hasMasks)
        try expectEqual(value.guardOwner.target, nil)
    },
    TestCase(name: "RuntimeWindowGuard reentrant stop cannot mutate disabled reset state") {
        let base = runtimeWindowGuardConfig("a", enabled: false)
        let custom = ScreenFixConfiguration(
            schemaVersion: base.schemaVersion,
            enabled: false,
            display: base.display,
            bands: [
                NormalizedRect(x: 0.2, y: 0, w: 0.3, h: 0.3),
                NormalizedRect(x: 0.2, y: 0.3, w: 0.3, h: 0.4),
                NormalizedRect(x: 0.2, y: 0.7, w: 0.3, h: 0.3),
            ]
        )
        let value = runtimeWindowGuardFixture(
            configuration: custom,
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        value.store.onSave = { value.runtime.stop() }

        value.runtime.resetToDefaults()

        try expectEqual(value.runtime.snapshot.configuration, custom)
        try expectEqual(value.guardOwner.target, nil)
    },
    TestCase(name: "RuntimeWindowGuard disconnect revokes before masks and reconnects from fresh frames") {
        let initial = runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
        )
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [initial]
        )
        value.runtime.start()
        value.catalog.screens = []
        value.log.removeAllObjects()

        value.runtime.reconcile()

        var events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("guard-stop", "masks-remove", in: events)
        let reconnected = runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 300, y: 400, width: 1000, height: 800),
            workArea: RectD(x: 300, y: 430, width: 1000, height: 770)
        )
        value.catalog.screens = [reconnected]
        value.log.removeAllObjects()

        value.runtime.reconcile()

        events = runtimeWindowGuardEvents(value)
        try expectEqual(value.guardOwner.target?.workArea, reconnected.topLeftVisibleFrame)
        try expectEqual(value.guardOwner.target?.displays.map(\.frame), [reconnected.topLeftFullFrame])
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard sleep wake is idempotent and keeps notification lifetime") {
        let initial = runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
        )
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [initial]
        )
        value.runtime.start()
        value.log.removeAllObjects()

        value.notifications.willSleep?()

        var events = runtimeWindowGuardEvents(value)
        try expectRuntimeWindowGuardOrder("guard-stop", "trust-stop", in: events)
        try expect(value.masks.hasMasks)
        try expect(!events.contains("unsubscribe"))

        value.catalog.screens = [runtimeWindowGuardScreen(
            "a",
            topLeftFrame: RectD(x: 200, y: 300, width: 1000, height: 800)
        )]
        value.log.removeAllObjects()
        value.notifications.displayChanged?()
        try expectEqual(runtimeWindowGuardEvents(value), [])

        value.notifications.woke?()
        value.notifications.woke?()
        events = runtimeWindowGuardEvents(value)
        try expectEqual(events.filter { $0 == "masks-commit" }.count, 1)
        try expectEqual(events.filter { $0 == "trust-true" }.count, 1)
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)

        value.log.removeAllObjects()
        value.notifications.willSleep?()
        value.notifications.woke?()
        events = runtimeWindowGuardEvents(value)
        try expectEqual(events.filter { $0 == "guard-stop" }.count, 1)
        try expectEqual(events.filter { $0 == "guard-start-a" }.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard stale runtime callbacks are inert after stop") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        value.runtime.start()
        let displayChanged = value.notifications.displayChanged
        let willSleep = value.notifications.willSleep
        let woke = value.notifications.woke
        value.runtime.stop()
        value.log.removeAllObjects()

        displayChanged?()
        willSleep?()
        woke?()
        value.runtime.accessibilityTrustDidChange(true)
        value.runtime.accessibilityPermissionLost()

        try expectEqual(runtimeWindowGuardEvents(value), [])
        try expectEqual(value.guardOwner.target, nil)
    },
    TestCase(name: "RuntimeWindowGuard weak relay routes only into current runtime") {
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        let relay = RuntimeWindowGuardEventRelay()
        relay.runtime = value.runtime
        value.runtime.start()
        let element = AXUIElementCreateApplication(991)
        let event = AXWindowEvent(
            identity: AXWindowIdentity(pid: 991, element: element),
            element: element,
            kind: .moved
        )

        relay.handle(event)
        try expectEqual(value.guardOwner.events.count, 1)

        value.trust.trusted = false
        relay.accessibilityTrustDidChange(false)
        try expectEqual(value.guardOwner.stopCount, 1)

        value.runtime.stop()
        relay.handle(event)
        relay.accessibilityPermissionLost()
        try expectEqual(value.guardOwner.events.count, 1)
    },
    TestCase(name: "RuntimeWindowGuard quit teardown follows dependency order once") {
        var terminations = 0
        let value = runtimeWindowGuardFixture(
            configuration: runtimeWindowGuardConfig("a"),
            screens: [runtimeWindowGuardScreen(
                "a",
                topLeftFrame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )],
            termination: { terminations += 1 }
        )
        value.runtime.start()
        value.log.removeAllObjects()

        value.runtime.quit()
        value.runtime.quit()

        let events = runtimeWindowGuardEvents(value)
        let notifications = try runtimeWindowGuardIndex("unsubscribe", in: events)
        let trust = try runtimeWindowGuardIndex("trust-stop", in: events)
        let guardStop = try runtimeWindowGuardIndex("guard-stop", in: events)
        let editor = try runtimeWindowGuardIndex("editor-stop", in: events)
        let masks = try runtimeWindowGuardIndex("masks-remove", in: events)
        try expect(notifications < trust)
        try expect(trust < guardStop)
        try expect(guardStop < editor)
        try expect(editor < masks)
        try expectEqual(events.filter { $0 == "unsubscribe" }.count, 1)
        try expectEqual(events.filter { $0 == "guard-stop" }.count, 1)
        try expectEqual(terminations, 1)
    },
    TestCase(name: "RuntimeWindowGuard controller stops AX source before debounce timers") {
        let log = NSMutableArray()
        let source = RuntimeWindowGuardOrderedSource(log: log)
        let controller = WindowGuardController(
            source: source,
            access: RuntimeWindowGuardUnusedAccess(),
            schedule: { _, _ in RuntimeWindowGuardOrderedTimer(log: log) },
            deliverOnMain: { $0() },
            permissionLost: {}
        )
        let target = WindowGuardTarget(
            selectedDisplayID: "a",
            workArea: RectD(x: 0, y: 0, width: 1000, height: 800),
            masks: [RectD(x: 400, y: 0, width: 200, height: 800)],
            displays: [DisplayFrame(
                stableID: "a",
                frame: RectD(x: 0, y: 0, width: 1000, height: 800)
            )]
        )
        controller.start(target: target)
        let element = AXUIElementCreateApplication(777)
        controller.handle(AXWindowEvent(
            identity: AXWindowIdentity(pid: 777, element: element),
            element: element,
            kind: .moved
        ))

        controller.stop()

        let events = log.compactMap { $0 as? String }
        try expectRuntimeWindowGuardOrder("source-stop", "timer-cancel", in: events)
    },
    TestCase(name: "RuntimeWindowGuard system notifications use default and workspace centers") {
        let defaultCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let notifications = SystemRuntimeNotifications(
            defaultCenter: defaultCenter,
            workspaceCenter: workspaceCenter
        )
        var displayChanges = 0
        var sleeps = 0
        var wakes = 0
        let tokens = notifications.subscribe(
            displayChanged: { displayChanges += 1 },
            willSleep: { sleeps += 1 },
            woke: { wakes += 1 }
        )

        defaultCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        defaultCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        defaultCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try expectEqual(displayChanges, 1)
        try expectEqual(sleeps, 1)
        try expectEqual(wakes, 1)
        notifications.unsubscribe(tokens)
    },
]
