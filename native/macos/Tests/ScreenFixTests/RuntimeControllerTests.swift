import AppKit
import ScreenFixApp
import ScreenFixCore

private enum FakeRuntimeError: Error {
    case requested
}

private final class FakeRuntimeStore: RuntimeConfigurationStore {
    var configuration: ScreenFixConfiguration?
    var loadError: Error?
    var saveError: Error?
    var onSave: ((ScreenFixConfiguration) throws -> Void)?
    let log: NSMutableArray

    init(configuration: ScreenFixConfiguration?, log: NSMutableArray) {
        self.configuration = configuration
        self.log = log
    }

    func load() throws -> ScreenFixConfiguration? {
        log.add("load")
        if let loadError { throw loadError }
        return configuration
    }

    func save(_ configuration: ScreenFixConfiguration) throws {
        log.add("save")
        try onSave?(configuration)
        if let saveError { throw saveError }
        self.configuration = configuration
    }
}

private final class FakeRuntimeCatalog: RuntimeDisplayCatalog {
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

private final class FakeRuntimeMasks: RuntimeMaskOwner {
    enum Failure {
        case none
        case prepare
        case order(Int)
    }

    var failure = Failure.none
    var committedCount = 0
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func replace(
        frames: [RectD],
        screenFrame: NSRect,
        beforeRetire: () throws -> Void
    ) throws {
        log.add("prepare")
        if case .prepare = failure { throw FakeRuntimeError.requested }
        for index in 1...3 {
            log.add("order-\(index)")
            log.add("verify-\(index)")
            if case .order(index) = failure {
                for candidate in 1...3 { log.add("close-candidate-\(candidate)") }
                throw FakeRuntimeError.requested
            }
        }
        do {
            try beforeRetire()
        } catch {
            for candidate in 1...3 { log.add("close-candidate-\(candidate)") }
            throw error
        }
        if committedCount > 0 {
            for old in 1...committedCount { log.add("close-old-\(old)") }
        }
        committedCount = 3
    }

    func removeAll() {
        guard committedCount > 0 else { return }
        log.add("remove-masks")
        committedCount = 0
    }
}

private final class FakeRuntimeCalibration: RuntimeCalibrationOwner {
    let log: NSMutableArray
    var isEditing = false

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
        log.add("calibration-start")
        guard try commitGuard() else { throw FakeRuntimeError.requested }
        isEditing = true
    }

    func stop() {
        guard isEditing else { return }
        log.add("calibration-stop")
        isEditing = false
    }
}

private final class FakeRuntimeNotifications: RuntimeNotifications {
    let log: NSMutableArray
    var displayChanged: (() -> Void)?
    var willSleep: (() -> Void)?
    var woke: (() -> Void)?

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

private struct RuntimeFixture {
    let log: NSMutableArray
    let store: FakeRuntimeStore
    let catalog: FakeRuntimeCatalog
    let masks: FakeRuntimeMasks
    let calibration: FakeRuntimeCalibration
    let notifications: FakeRuntimeNotifications
    let runtime: RuntimeController
}

private func runtimeDisplay(_ id: String, name: String = "Ultrawide") -> ConnectedScreen {
    let display = ConnectedDisplay(stableId: id, name: name, width: 3440, height: 1440)
    return ConnectedScreen(
        display: display,
        fullFrame: NSRect(x: 0, y: 0, width: 3440, height: 1440),
        nativeScreen: NSObject()
    )
}

private func runtimeConfig(_ id: String, enabled: Bool = true) -> ScreenFixConfiguration {
    DefaultConfiguration.make(
        for: DisplayIdentity(stableId: id, name: "Ultrawide", width: 3440, height: 1440),
        enabled: enabled
    )
}

private func customRuntimeConfig(_ id: String) -> ScreenFixConfiguration {
    let base = runtimeConfig(id)
    return ScreenFixConfiguration(
        schemaVersion: base.schemaVersion,
        enabled: base.enabled,
        display: base.display,
        bands: [
            NormalizedRect(x: 0.1, y: 0, w: 0.2, h: 0.34),
            NormalizedRect(x: 0.1, y: 0.34, w: 0.2, h: 0.39),
            NormalizedRect(x: 0.1, y: 0.73, w: 0.2, h: 0.27),
        ]
    )
}

private func fixture(
    configuration: ScreenFixConfiguration?,
    screens: [ConnectedScreen],
    termination: @escaping () -> Void = {}
) -> RuntimeFixture {
    let log = NSMutableArray()
    let store = FakeRuntimeStore(configuration: configuration, log: log)
    let catalog = FakeRuntimeCatalog(screens: screens, log: log)
    let masks = FakeRuntimeMasks(log: log)
    let calibration = FakeRuntimeCalibration(log: log)
    let notifications = FakeRuntimeNotifications(log: log)
    let runtime = RuntimeController(
        store: store,
        catalog: catalog,
        maskOwner: masks,
        calibrationOwner: calibration,
        notifications: notifications,
        termination: termination,
        stateDidChange: {}
    )
    return RuntimeFixture(
        log: log,
        store: store,
        catalog: catalog,
        masks: masks,
        calibration: calibration,
        notifications: notifications,
        runtime: runtime
    )
}

private func runtimeEvents(_ fixture: RuntimeFixture) -> [String] {
    fixture.log.compactMap { $0 as? String }
}

let runtimeControllerTests = [
    TestCase(name: "RuntimeController startup without config is idempotent") {
        let value = fixture(configuration: nil, screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.runtime.start()

        try expectEqual(runtimeEvents(value).filter { $0 == "subscribe" }.count, 1)
        try expectEqual(value.masks.committedCount, 0)
        try expectEqual(value.runtime.snapshot.menuState.status, "Paused: select a monitor")
    },
    TestCase(name: "RuntimeController invalid startup preserves file and reports config error") {
        let value = fixture(configuration: nil, screens: [])
        value.store.loadError = FakeRuntimeError.requested
        value.runtime.start()

        try expectEqual(value.masks.committedCount, 0)
        try expect(value.runtime.snapshot.menuState.status?.hasPrefix("Paused: config error:") == true)
    },
    TestCase(name: "RuntimeController selection opens provisional calibration before saving") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b", name: "Second")])
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.selectDisplay(stableId: "b")

        try expect(runtimeEvents(value).contains("prepare"))
        try expect(runtimeEvents(value).contains("calibration-start"))
        try expect(!runtimeEvents(value).contains("save"))
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
        try expect(value.runtime.snapshot.calibrating)
    },
    TestCase(name: "RuntimeController provisional selection does not touch a failing store") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b")])
        value.runtime.start()
        value.store.saveError = FakeRuntimeError.requested
        value.log.removeAllObjects()
        value.runtime.selectDisplay(stableId: "b")

        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(value.masks.committedCount, 3)
        try expect(!runtimeEvents(value).contains("save"))
        try expect(value.runtime.snapshot.calibrating)
    },
    TestCase(name: "RuntimeController stale monitor choice preserves the live transaction") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        let before = value.runtime.snapshot
        value.log.removeAllObjects()

        value.runtime.selectDisplay(stableId: "disconnected-menu-choice")
        let after = value.runtime.snapshot

        try expectEqual(after.configuration, before.configuration)
        try expectEqual(after.displayConnected, before.displayConnected)
        try expectEqual(after.menuState, before.menuState)
        try expectEqual(value.masks.committedCount, 3)
        try expectEqual(runtimeEvents(value), ["displays"])
    },
    TestCase(name: "RuntimeController enabled reset transacts and disabled reset only saves") {
        let enabled = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        enabled.runtime.start()
        enabled.log.removeAllObjects()
        enabled.runtime.resetToDefaults()
        try expect(runtimeEvents(enabled).contains("prepare"))
        try expect(runtimeEvents(enabled).contains("save"))
        try expectEqual(enabled.runtime.snapshot.configuration?.enabled, true)

        let disabled = fixture(configuration: runtimeConfig("a", enabled: false), screens: [runtimeDisplay("a")])
        disabled.runtime.start()
        disabled.log.removeAllObjects()
        disabled.runtime.resetToDefaults()
        try expectEqual(runtimeEvents(disabled), ["displays", "save"])
        try expectEqual(disabled.masks.committedCount, 0)
        try expectEqual(disabled.runtime.snapshot.configuration?.enabled, false)
    },
    TestCase(name: "RuntimeController reload failure preserves old state and valid reload replaces") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b")])
        value.runtime.start()
        value.store.loadError = FakeRuntimeError.requested
        value.runtime.reload()
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(value.masks.committedCount, 3)

        value.store.loadError = nil
        value.store.configuration = runtimeConfig("b")
        value.log.removeAllObjects()
        value.runtime.reload()
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "b")
        try expectEqual(value.masks.committedCount, 3)
        try expect(runtimeEvents(value).contains("prepare"))
        try expect(!runtimeEvents(value).contains("save"))
    },
    TestCase(name: "RuntimeController reload of a missing file clears old state") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.store.configuration = nil
        value.runtime.reload()

        try expectEqual(value.runtime.snapshot.configuration, nil)
        try expectEqual(value.masks.committedCount, 0)
        try expectEqual(value.runtime.snapshot.menuState.status, "Paused: select a monitor")
    },
    TestCase(name: "RuntimeController mask failure never saves and preserves old state") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b")])
        value.runtime.start()
        value.masks.failure = .order(2)
        value.log.removeAllObjects()
        value.runtime.selectDisplay(stableId: "b")

        try expect(!runtimeEvents(value).contains("save"))
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(value.masks.committedCount, 3)
        try expect(value.runtime.snapshot.menuState.status?.hasPrefix("Paused: mask error:") == true)
    },
    TestCase(name: "RuntimeController mask failure preserves state for reset reload and reconcile") {
        let reset = fixture(configuration: customRuntimeConfig("a"), screens: [runtimeDisplay("a")])
        reset.runtime.start()
        let resetBands = reset.runtime.snapshot.configuration?.bands
        reset.masks.failure = .order(1)
        reset.log.removeAllObjects()
        reset.runtime.resetToDefaults()
        try expectEqual(reset.runtime.snapshot.configuration?.bands, resetBands)
        try expect(!runtimeEvents(reset).contains("save"))
        try expectEqual(reset.masks.committedCount, 3)

        let reload = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b")])
        reload.runtime.start()
        reload.store.configuration = runtimeConfig("b")
        reload.masks.failure = .order(2)
        reload.log.removeAllObjects()
        reload.runtime.reload()
        try expectEqual(reload.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(reload.masks.committedCount, 3)

        let reconcile = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        reconcile.runtime.start()
        reconcile.masks.failure = .order(3)
        reconcile.log.removeAllObjects()
        reconcile.runtime.reconcile()
        try expectEqual(reconcile.runtime.snapshot.configuration?.display.stableId, "a")
        try expectEqual(reconcile.masks.committedCount, 3)
    },
    TestCase(name: "RuntimeController prepare failure never saves selection") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a"), runtimeDisplay("b")])
        value.runtime.start()
        value.masks.failure = .prepare
        value.log.removeAllObjects()
        value.runtime.selectDisplay(stableId: "b")
        try expect(!runtimeEvents(value).contains("save"))
        try expectEqual(value.runtime.snapshot.configuration?.display.stableId, "a")
    },
    TestCase(name: "RuntimeController disconnect and ambiguity remove masks") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.catalog.screens = []
        value.runtime.reconcile()
        try expectEqual(value.masks.committedCount, 0)
        try expectEqual(value.runtime.snapshot.menuState.status, "Paused: saved display is disconnected")

        value.catalog.screens = [runtimeDisplay("x"), runtimeDisplay("y")]
        value.runtime.reconcile()
        try expectEqual(value.masks.committedCount, 0)
    },
    TestCase(name: "RuntimeController repeated reload keeps exactly three masks") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.runtime.reload()
        value.runtime.reload()
        try expectEqual(value.masks.committedCount, 3)
    },
    TestCase(name: "RuntimeController Enable Disable operations are idempotent") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.setEnabled(false)
        value.runtime.setEnabled(false)
        try expectEqual(runtimeEvents(value).filter { $0 == "remove-masks" }.count, 1)
        try expectEqual(runtimeEvents(value).filter { $0 == "save" }.count, 1)

        value.runtime.setEnabled(true)
        value.runtime.setEnabled(true)
        try expectEqual(value.masks.committedCount, 3)
        try expectEqual(runtimeEvents(value).filter { $0 == "prepare" }.count, 1)
    },
    TestCase(name: "RuntimeController Disable save failure preserves enabled masks") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        let before = value.runtime.snapshot
        value.store.saveError = FakeRuntimeError.requested
        value.log.removeAllObjects()

        value.runtime.setEnabled(false)
        let after = value.runtime.snapshot

        try expectEqual(after.configuration, before.configuration)
        try expectEqual(after.displayConnected, before.displayConnected)
        try expectEqual(after.menuState.enabledActionTitle, "Disable")
        try expect(after.menuState.enabledActionChecked)
        try expect(after.menuState.status?.hasPrefix("Paused: config error:") == true)
        try expectEqual(value.masks.committedCount, 3)
        try expectEqual(runtimeEvents(value), ["save"])
    },
    TestCase(name: "RuntimeController Disable save boundary cannot mutate after reentrant stop") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        value.log.removeAllObjects()
        value.store.onSave = { _ in
            value.runtime.stop()
            throw FakeRuntimeError.requested
        }

        value.runtime.setEnabled(false)

        try expectEqual(value.runtime.snapshot.configuration?.enabled, true)
        try expectEqual(value.runtime.snapshot.menuState.status, nil)
        try expectEqual(runtimeEvents(value), ["save", "unsubscribe", "remove-masks"])
    },
    TestCase(name: "RuntimeController callbacks reconcile and stale callback is inert after stop") {
        let value = fixture(configuration: runtimeConfig("a"), screens: [runtimeDisplay("a")])
        value.runtime.start()
        let stale = value.notifications.displayChanged
        value.log.removeAllObjects()
        value.notifications.displayChanged?()
        value.notifications.willSleep?()
        value.notifications.woke?()
        try expectEqual(runtimeEvents(value).filter { $0 == "prepare" }.count, 2)

        value.log.removeAllObjects()
        value.runtime.stop()
        stale?()
        value.runtime.stop()
        try expectEqual(runtimeEvents(value).first, "unsubscribe")
        try expectEqual(runtimeEvents(value).filter { $0 == "unsubscribe" }.count, 1)
        try expect(!runtimeEvents(value).contains("prepare"))
    },
    TestCase(name: "RuntimeController quit stops and terminates once") {
        var terminations = 0
        let value = fixture(
            configuration: runtimeConfig("a"),
            screens: [runtimeDisplay("a")],
            termination: { terminations += 1 }
        )
        value.runtime.start()
        value.log.removeAllObjects()
        value.runtime.quit()
        value.runtime.quit()
        try expectEqual(terminations, 1)
        try expectEqual(runtimeEvents(value).first, "unsubscribe")
        try expectEqual(runtimeEvents(value).filter { $0 == "remove-masks" }.count, 1)
    },
]
