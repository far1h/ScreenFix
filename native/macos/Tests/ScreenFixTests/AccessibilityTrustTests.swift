import Foundation
import ScreenFixApp

private final class FakeTrustTimer: AccessibilityTrustTimer {
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

private final class FakeTrustScheduler {
    struct Entry {
        let delay: TimeInterval
        let timer: FakeTrustTimer
        let callback: () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(delay: TimeInterval, callback: @escaping () -> Void) -> AccessibilityTrustTimer? {
        let timer = FakeTrustTimer()
        entries.append(Entry(delay: delay, timer: timer, callback: callback))
        return timer
    }
}

private struct TrustFixture {
    let scheduler: FakeTrustScheduler
    let controller: AccessibilityTrustController
    let promptCount: () -> Int
    let silentCount: () -> Int
    let states: () -> [Bool]
}

private func trustFixture(prompt: Bool, silent: @escaping () -> Bool) -> TrustFixture {
    let scheduler = FakeTrustScheduler()
    var promptCount = 0
    var silentCount = 0
    var states: [Bool] = []
    let controller = AccessibilityTrustController(
        promptCheck: {
            promptCount += 1
            return prompt
        },
        silentCheck: {
            silentCount += 1
            return silent()
        },
        schedule: scheduler.schedule,
        stateDidChange: { states.append($0) }
    )
    return TrustFixture(
        scheduler: scheduler,
        controller: controller,
        promptCount: { promptCount },
        silentCount: { silentCount },
        states: { states }
    )
}

let accessibilityTrustTests: [TestCase] = [
    TestCase(name: "AccessibilityTrust inactive reconcile never checks or schedules") {
        let fixture = trustFixture(prompt: true, silent: { true })

        try expect(!fixture.controller.reconcile(needsPermission: false))
        try expect(!fixture.controller.reconcile(needsPermission: false))

        try expectEqual(fixture.promptCount(), 0)
        try expectEqual(fixture.silentCount(), 0)
        try expectEqual(fixture.scheduler.entries.count, 0)
    },
    TestCase(name: "AccessibilityTrust prompts once and polls every two seconds") {
        let fixture = trustFixture(prompt: false, silent: { false })

        try expect(!fixture.controller.reconcile(needsPermission: true))
        try expect(!fixture.controller.reconcile(needsPermission: true))

        try expectEqual(fixture.promptCount(), 1)
        try expectEqual(fixture.silentCount(), 0)
        try expectEqual(fixture.scheduler.entries.count, 1)
        try expectEqual(fixture.scheduler.entries[0].delay, 2)

        fixture.scheduler.entries[0].callback()
        try expectEqual(fixture.silentCount(), 1)
        try expectEqual(fixture.scheduler.entries.count, 2)
        try expectEqual(fixture.scheduler.entries[1].delay, 2)
    },
    TestCase(name: "AccessibilityTrust reports only real trust transitions") {
        var values = [false, true, true, false]
        let fixture = trustFixture(prompt: values.removeFirst(), silent: { values.removeFirst() })

        try expect(!fixture.controller.reconcile(needsPermission: true))
        fixture.scheduler.entries[0].callback()
        fixture.scheduler.entries[1].callback()
        fixture.scheduler.entries[2].callback()

        try expectEqual(fixture.states(), [true, false])
        try expectEqual(fixture.controller.isTrusted, false)
    },
    TestCase(name: "AccessibilityTrust prompt result is only the current state") {
        let fixture = trustFixture(prompt: true, silent: { false })

        try expect(fixture.controller.reconcile(needsPermission: true))
        fixture.scheduler.entries[0].callback()

        try expectEqual(fixture.states(), [false])
        try expectEqual(fixture.controller.isTrusted, false)
    },
    TestCase(name: "AccessibilityTrust inactive reconcile cancels and invalidates polling") {
        let fixture = trustFixture(prompt: false, silent: { true })
        _ = fixture.controller.reconcile(needsPermission: true)
        let first = fixture.scheduler.entries[0]

        _ = fixture.controller.reconcile(needsPermission: false)
        first.callback()

        try expectEqual(first.timer.cancelCount, 1)
        try expectEqual(fixture.silentCount(), 0)
        try expectEqual(fixture.states(), [])
        try expectEqual(fixture.scheduler.entries.count, 1)
    },
    TestCase(name: "AccessibilityTrust stop is idempotent and rejects stale callbacks") {
        let fixture = trustFixture(prompt: false, silent: { true })
        _ = fixture.controller.reconcile(needsPermission: true)
        let stale = fixture.scheduler.entries[0]

        fixture.controller.stop()
        fixture.controller.stop()
        stale.callback()

        try expectEqual(stale.timer.cancelCount, 1)
        try expectEqual(fixture.silentCount(), 0)
        try expectEqual(fixture.states(), [])
    },
    TestCase(name: "AccessibilityTrust restart uses a new generation without prompting again") {
        let fixture = trustFixture(prompt: false, silent: { true })
        _ = fixture.controller.reconcile(needsPermission: true)
        let stale = fixture.scheduler.entries[0]
        fixture.controller.stop()

        try expect(fixture.controller.reconcile(needsPermission: true))
        stale.callback()

        try expectEqual(fixture.promptCount(), 1)
        try expectEqual(fixture.silentCount(), 1)
        try expectEqual(fixture.scheduler.entries.count, 2)
        try expectEqual(fixture.states(), [])
    },
]
