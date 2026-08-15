import ApplicationServices
import Foundation
import ScreenFixApp
import ScreenFixCore

private final class FakeGuardTimer: WindowGuardTimer {
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

private final class FakeGuardScheduler {
    struct Entry {
        let delay: TimeInterval
        let timer: FakeGuardTimer
        let callback: () -> Void
    }

    var failNext = false
    private(set) var entries: [Entry] = []

    func schedule(delay: TimeInterval, callback: @escaping () -> Void) -> WindowGuardTimer? {
        if failNext {
            failNext = false
            return nil
        }
        let timer = FakeGuardTimer()
        entries.append(Entry(delay: delay, timer: timer, callback: callback))
        return timer
    }
}

private final class FakeGuardLane: AXWorkLane {
    var held = false
    private(set) var queued: [() -> Void] = []

    func submit(_ work: @escaping () -> Void) {
        if held { queued.append(work) } else { work() }
    }

    func flush() {
        let retired = queued
        queued = []
        retired.forEach { $0() }
    }
}

private final class FakeGuardSource: WindowGuardEventSource {
    var lanes: [pid_t: FakeGuardLane] = [:]
    var onReseed: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var reseedCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func reseedCurrentWindows() {
        reseedCount += 1
        onReseed?()
    }

    func lane(for pid: pid_t) -> AXWorkLane? {
        lanes[pid]
    }
}

private final class FakeWindowAccess: WindowGuardWindowAccess {
    var frames: [AXWindowIdentity: RectD] = [:]
    var excluded = Set<AXWindowIdentity>()
    var sizeSettable: [AXWindowIdentity: Bool] = [:]
    var factsErrors: [AXWindowIdentity: Error] = [:]
    var frameErrors: [AXWindowIdentity: Error] = [:]
    var setErrors: [AXWindowIdentity: Error] = [:]
    var ignoreWrites = Set<AXWindowIdentity>()
    var ownerIsRegular = true
    var ownerIsHidden = false
    var ownerIsTerminated = false
    var positionSettable = true
    var assignedToSelectedDisplay = true
    var afterFacts: (() -> Void)?
    var afterSizeWrite: (() -> Void)?
    private(set) var log: [String] = []

    func clearLog() {
        log.removeAll()
    }

    func facts(
        for identity: AXWindowIdentity,
        screenFixPID: pid_t,
        target: WindowGuardTarget
    ) throws -> WindowFacts {
        log.append("\(identity.pid)-facts")
        if let error = factsErrors[identity] { throw error }
        let frame = frames[identity]
        let result = WindowFacts(
            ownerPID: identity.pid,
            screenFixPID: screenFixPID,
            ownerIsRegular: ownerIsRegular,
            ownerIsHidden: ownerIsHidden,
            ownerIsTerminated: ownerIsTerminated,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            minimized: excluded.contains(identity),
            frame: frame,
            positionSettable: positionSettable,
            assignedDisplayID: assignedToSelectedDisplay ? target.selectedDisplayID : "other",
            selectedDisplayID: target.selectedDisplayID,
            fullDisplayFrames: target.displays.map(\.frame)
        )
        afterFacts?()
        return result
    }

    func isSizeSettable(for identity: AXWindowIdentity) throws -> Bool {
        log.append("\(identity.pid)-size-settable")
        return sizeSettable[identity] ?? true
    }

    func setSize(_ size: CGSize, for identity: AXWindowIdentity) throws {
        log.append("\(identity.pid)-set-size")
        if let error = setErrors[identity] { throw error }
        guard !ignoreWrites.contains(identity), let frame = frames[identity] else { return }
        frames[identity] = RectD(x: frame.x, y: frame.y, width: size.width, height: size.height)
        afterSizeWrite?()
    }

    func setPosition(_ position: CGPoint, for identity: AXWindowIdentity) throws {
        log.append("\(identity.pid)-set-position")
        if let error = setErrors[identity] { throw error }
        guard !ignoreWrites.contains(identity), let frame = frames[identity] else { return }
        frames[identity] = RectD(x: position.x, y: position.y, width: frame.width, height: frame.height)
    }

    func frame(for identity: AXWindowIdentity) throws -> RectD {
        log.append("\(identity.pid)-frame")
        if let error = frameErrors[identity] { throw error }
        guard let frame = frames[identity] else { throw AXClientError.missingValue }
        return frame
    }
}

private struct GuardFixture {
    let source: FakeGuardSource
    let access: FakeWindowAccess
    let scheduler: FakeGuardScheduler
    let controller: WindowGuardController
    let permissionLosses: () -> Int
    let setNow: (TimeInterval) -> Void
}

private func guardFixture() -> GuardFixture {
    let source = FakeGuardSource()
    let access = FakeWindowAccess()
    let scheduler = FakeGuardScheduler()
    var permissionLosses = 0
    var now: TimeInterval = 0
    let controller = WindowGuardController(
        source: source,
        access: access,
        screenFixPID: 7,
        schedule: scheduler.schedule,
        now: { now },
        deliverOnMain: { $0() },
        permissionLost: { permissionLosses += 1 }
    )
    return GuardFixture(
        source: source,
        access: access,
        scheduler: scheduler,
        controller: controller,
        permissionLosses: { permissionLosses },
        setNow: { now = $0 }
    )
}

private func guardTarget(mask: RectD = RectD(x: 400, y: 0, width: 300, height: 800)) -> WindowGuardTarget {
    WindowGuardTarget(
        selectedDisplayID: "selected",
        workArea: RectD(x: 0, y: 0, width: 1200, height: 800),
        masks: [mask],
        displays: [DisplayFrame(stableID: "selected", frame: RectD(x: 0, y: 0, width: 1200, height: 800))]
    )
}

private func guardIdentity(_ pid: pid_t) -> AXWindowIdentity {
    AXWindowIdentity(pid: pid, element: AXUIElementCreateApplication(pid + 1000))
}

private func guardEvent(_ identity: AXWindowIdentity, _ kind: AXWindowEventKind = .moved) -> AXWindowEvent {
    AXWindowEvent(identity: identity, element: identity.element, kind: kind)
}

let windowGuardTests: [TestCase] = [
    TestCase(name: "WindowGuard debounces seed and replacement events for 150 milliseconds") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity, .seeded))
        let first = fixture.scheduler.entries[0]
        fixture.controller.handle(guardEvent(identity, .moved))
        let second = fixture.scheduler.entries[1]

        try expectEqual(first.delay, 0.15)
        try expectEqual(first.timer.cancelCount, 1)
        first.callback()
        try expectEqual(fixture.access.log, [])
        second.callback()
        try expectEqual(fixture.access.log.first, "42-facts")
    },
    TestCase(name: "WindowGuard target updates cancel stale work without restarting observers") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())
        fixture.controller.handle(guardEvent(identity))
        let stale = fixture.scheduler.entries[0]

        fixture.controller.start(target: guardTarget(mask: RectD(x: 500, y: 0, width: 200, height: 800)))
        stale.callback()

        try expectEqual(stale.timer.cancelCount, 1)
        try expectEqual(fixture.source.startCount, 1)
        try expectEqual(fixture.source.reseedCount, 1)
        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard target update reseeds a live window against new masks") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 100, y: 100, width: 100, height: 400)
        let firstTarget = guardTarget(mask: RectD(x: 400, y: 0, width: 300, height: 800))
        let secondTarget = guardTarget(mask: RectD(x: 50, y: 0, width: 200, height: 800))
        fixture.controller.start(target: firstTarget)
        fixture.controller.handle(guardEvent(identity, .seeded))
        fixture.scheduler.entries[0].callback()
        fixture.access.clearLog()
        fixture.source.onReseed = {
            fixture.controller.handle(guardEvent(identity, .seeded))
        }

        fixture.controller.start(target: secondTarget)

        try expectEqual(fixture.source.startCount, 1)
        try expectEqual(fixture.source.reseedCount, 1)
        try expectEqual(fixture.scheduler.entries.count, 2)
        fixture.scheduler.entries[1].callback()
        try expect(fixture.access.log.contains("42-set-position"))
        guard let corrected = fixture.access.frames[identity] else {
            throw TestFailure(description: "missing corrected window")
        }
        try expect(!corrected.intersects(secondTarget.masks[0]))
    },
    TestCase(name: "WindowGuard observes every correctable event kind with one retained identity") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.controller.start(target: guardTarget())
        fixture.controller.start(target: guardTarget())
        let kinds: [AXWindowEventKind] = [
            .seeded, .shown, .created, .focused, .moved, .resized, .deminiaturized,
        ]

        kinds.forEach { fixture.controller.handle(guardEvent(identity, $0)) }

        try expectEqual(fixture.source.startCount, 1)
        try expectEqual(fixture.source.reseedCount, 0)
        try expectEqual(fixture.scheduler.entries.count, kinds.count)
        try expectEqual(fixture.scheduler.entries.dropLast().allSatisfy { $0.timer.cancelCount == 1 }, true)
        try expectEqual(fixture.scheduler.entries.last?.timer.cancelCount, 0)
    },
    TestCase(name: "WindowGuard scheduling failure leaves no phantom pending work") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())
        fixture.scheduler.failNext = true

        fixture.controller.handle(guardEvent(identity))
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()

        try expectEqual(fixture.access.log.first, "42-facts")
    },
    TestCase(name: "WindowGuard destroyed and minimized events cancel pending work") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.controller.start(target: guardTarget())
        fixture.controller.handle(guardEvent(identity))
        let destroyed = fixture.scheduler.entries[0]
        fixture.controller.handle(guardEvent(identity, .destroyed))
        destroyed.callback()
        fixture.controller.handle(guardEvent(identity))
        let minimized = fixture.scheduler.entries[1]
        fixture.controller.handle(guardEvent(identity, .minimized))
        minimized.callback()

        try expectEqual(destroyed.timer.cancelCount, 1)
        try expectEqual(minimized.timer.cancelCount, 1)
        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard ignores ineligible disconnected and vanished windows") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 0, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.ownerIsHidden = true
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()
        fixture.access.ownerIsHidden = false
        fixture.access.assignedToSelectedDisplay = false
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[2].callback()
        fixture.access.assignedToSelectedDisplay = true
        fixture.access.factsErrors[identity] = AXClientError.api(.invalidUIElement)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[3].callback()

        try expectEqual(fixture.access.log.filter { $0.contains("set-") }, [])
        try expectEqual(fixture.access.frames[identity], RectD(x: 550, y: 100, width: 200, height: 400))
    },
    TestCase(name: "WindowGuard drops a pending window when its application lane disappears") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())
        fixture.controller.handle(guardEvent(identity))
        fixture.source.lanes.removeValue(forKey: 42)

        fixture.scheduler.entries[0].callback()

        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard corrects fixed-size windows with position only") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.sizeSettable[identity] = false
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()

        try expectEqual(fixture.access.frames[identity], RectD(x: 700, y: 100, width: 200, height: 400))
        try expectEqual(fixture.access.log, ["42-facts", "42-set-position", "42-frame"])
    },
    TestCase(name: "WindowGuard rejects resize-required fixed windows before partial writes") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 100, y: 100, width: 500, height: 400)
        fixture.access.sizeSettable[identity] = false
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        fixture.access.clearLog()
        fixture.setNow(0.5)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()

        try expectEqual(fixture.access.frames[identity], RectD(x: 100, y: 100, width: 500, height: 400))
        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard writes size before position and consumes only matching self events") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 100, y: 100, width: 500, height: 400)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        try expectEqual(
            fixture.access.log,
            ["42-facts", "42-size-settable", "42-set-size", "42-set-position", "42-frame"]
        )

        fixture.access.clearLog()
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()
        try expectEqual(fixture.access.log, ["42-facts"])

        fixture.access.clearLog()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[2].callback()
        try expect(fixture.access.log.contains("42-set-position"))
    },
    TestCase(name: "WindowGuard refusal cooldown expires after one second") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.ignoreWrites.insert(identity)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        fixture.access.clearLog()
        fixture.setNow(0.9)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()
        try expectEqual(fixture.access.log, [])

        fixture.setNow(1.01)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[2].callback()
        try expectEqual(fixture.access.log.first, "42-facts")
    },
    TestCase(name: "WindowGuard contains write errors and suppresses an immediate retry") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.setErrors[identity] = AXClientError.api(.cannotComplete)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        try expectEqual(fixture.access.log, ["42-facts", "42-set-position"])
        fixture.access.setErrors.removeValue(forKey: identity)
        fixture.access.clearLog()
        fixture.setNow(0.5)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()

        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard contains missing readback and clears recent state on destroy") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.frameErrors[identity] = AXClientError.missingValue
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()
        try expectEqual(
            fixture.access.log,
            ["42-facts", "42-set-position", "42-frame"]
        )
        fixture.access.frameErrors.removeValue(forKey: identity)
        fixture.setNow(1.1)
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[1].callback()
        fixture.controller.handle(guardEvent(identity, .destroyed))
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.clearLog()
        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[2].callback()

        try expect(fixture.access.log.contains("42-set-position"))
    },
    TestCase(name: "WindowGuard contains one app failure while another lane succeeds") {
        let fixture = guardFixture()
        let first = guardIdentity(42)
        let second = guardIdentity(43)
        let held = FakeGuardLane()
        held.held = true
        fixture.source.lanes[42] = held
        fixture.source.lanes[43] = FakeGuardLane()
        fixture.access.frames[first] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.frames[second] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.factsErrors[first] = AXClientError.api(.cannotComplete)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(first))
        fixture.controller.handle(guardEvent(second))
        fixture.scheduler.entries[0].callback()
        fixture.scheduler.entries[1].callback()

        try expectEqual(fixture.access.frames[second], RectD(x: 700, y: 100, width: 200, height: 400))
        try expectEqual(fixture.access.log, ["43-facts", "43-set-position", "43-frame"])
        held.flush()
        try expect(fixture.access.log.contains("42-facts"))
        fixture.access.clearLog()
        fixture.controller.handle(guardEvent(first))
        fixture.scheduler.entries[2].callback()
        try expectEqual(fixture.access.log, [])
    },
    TestCase(name: "WindowGuard reports Accessibility loss without mutating its target") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        fixture.source.lanes[42] = FakeGuardLane()
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.access.factsErrors[identity] = AXClientError.api(.apiDisabled)
        fixture.controller.start(target: guardTarget())

        fixture.controller.handle(guardEvent(identity))
        fixture.scheduler.entries[0].callback()

        try expectEqual(fixture.permissionLosses(), 1)
        try expectEqual(fixture.source.stopCount, 0)
    },
    TestCase(name: "WindowGuard generation stops work after fresh facts and after a size write") {
        let afterFacts = guardFixture()
        let factsIdentity = guardIdentity(42)
        afterFacts.source.lanes[42] = FakeGuardLane()
        afterFacts.access.frames[factsIdentity] = RectD(x: 550, y: 100, width: 200, height: 400)
        afterFacts.access.afterFacts = { afterFacts.controller.stop() }
        afterFacts.controller.start(target: guardTarget())
        afterFacts.controller.handle(guardEvent(factsIdentity))
        afterFacts.scheduler.entries[0].callback()
        try expectEqual(afterFacts.access.log, ["42-facts"])

        let afterSize = guardFixture()
        let sizeIdentity = guardIdentity(43)
        afterSize.source.lanes[43] = FakeGuardLane()
        afterSize.access.frames[sizeIdentity] = RectD(x: 100, y: 100, width: 500, height: 400)
        afterSize.access.afterSizeWrite = { afterSize.controller.stop() }
        afterSize.controller.start(target: guardTarget())
        afterSize.controller.handle(guardEvent(sizeIdentity))
        afterSize.scheduler.entries[0].callback()
        try expectEqual(
            afterSize.access.log,
            ["43-facts", "43-size-settable", "43-set-size"]
        )
    },
    TestCase(name: "WindowGuard stop invalidates pending and lane callbacks idempotently") {
        let fixture = guardFixture()
        let identity = guardIdentity(42)
        let held = FakeGuardLane()
        held.held = true
        fixture.source.lanes[42] = held
        fixture.access.frames[identity] = RectD(x: 550, y: 100, width: 200, height: 400)
        fixture.controller.start(target: guardTarget())
        fixture.controller.handle(guardEvent(identity))
        let timer = fixture.scheduler.entries[0]
        timer.callback()

        fixture.controller.stop()
        fixture.controller.stop()
        held.flush()

        try expectEqual(fixture.source.stopCount, 1)
        try expectEqual(fixture.access.log, [])
    },
]
