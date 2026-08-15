import ApplicationServices
import Foundation
import ScreenFixApp

private final class FakeObserverClient: AXObserverClient {
    var windows: [pid_t: [AXUIElement]] = [:]
    var focused: [pid_t: AXUIElement] = [:]
    var error: Error?
    let log: NSMutableArray

    init(log: NSMutableArray) {
        self.log = log
    }

    func prepare(_ element: AXUIElement) throws {
        log.add("prepare-\(elementPID(element))")
        if let error { throw error }
    }

    func elements(_ element: AXUIElement, attribute: CFString) throws -> [AXUIElement] {
        log.add("windows-\(elementPID(element))")
        if let error { throw error }
        return windows[elementPID(element)] ?? []
    }

    func element(_ element: AXUIElement, attribute: CFString) throws -> AXUIElement {
        log.add("focused-\(elementPID(element))")
        if let error { throw error }
        guard let result = focused[elementPID(element)] else { throw AXClientError.missingValue }
        return result
    }
}

private final class FakeObserverToken: AXObserverToken {
    let pid: pid_t
    let callback: (AXUIElement, CFString) -> Void
    let log: NSMutableArray
    var unsupported = Set<String>()
    var failures = Set<String>()
    var attachResult = true
    private(set) var attached = 0
    private(set) var detached = 0

    init(pid: pid_t, callback: @escaping (AXUIElement, CFString) -> Void, log: NSMutableArray) {
        self.pid = pid
        self.callback = callback
        self.log = log
    }

    func addNotification(_ notification: CFString, element: AXUIElement) -> AXError {
        let name = notification as String
        log.add("add-\(elementPID(element))-\(name)")
        if unsupported.contains(name) { return .notificationUnsupported }
        if failures.contains(name) { return .cannotComplete }
        return .success
    }

    func removeNotification(_ notification: CFString, element: AXUIElement) -> AXError {
        log.add("remove-\(elementPID(element))-\(notification as String)")
        return .success
    }

    func attachToMainRunLoop() -> Bool {
        log.add("attach-\(pid)")
        if attachResult { attached += 1 }
        return attachResult
    }

    func detachFromMainRunLoop() {
        detached += 1
        log.add("detach-\(pid)")
    }
}

private final class FakeObserverLane: AXWorkLane {
    var held = false
    private(set) var queued: [() -> Void] = []

    func submit(_ work: @escaping () -> Void) {
        if held {
            queued.append(work)
        } else {
            work()
        }
    }

    func flush() {
        let work = queued
        queued = []
        work.forEach { $0() }
    }
}

private final class FakeWorkspaceObservation: AXWorkspaceObservation {
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

private final class ObserverEnvironment {
    let selfPID: pid_t = 7
    let log = NSMutableArray()
    let client: FakeObserverClient
    let workspace = FakeWorkspaceObservation()
    var apps: [AXObservedApplication] = []
    var workspaceCallback: ((AXApplicationEvent) -> Void)?
    var tokens: [pid_t: FakeObserverToken] = [:]
    var lanes: [pid_t: FakeObserverLane] = [:]
    var unsupported: [pid_t: Set<String>] = [:]
    var failures: [pid_t: Set<String>] = [:]
    var attachFailures = Set<pid_t>()
    var events: [AXWindowEvent] = []

    init() {
        client = FakeObserverClient(log: log)
    }

    func app(_ pid: pid_t, regular: Bool = true, hidden: Bool = false, terminated: Bool = false) -> AXObservedApplication {
        AXObservedApplication(pid: pid, isRegular: regular, isHidden: hidden, isTerminated: terminated)
    }

    func window(_ id: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(id)
    }

    func registry() -> AXObserverRegistry {
        AXObserverRegistry(
            client: client,
            screenFixPID: selfPID,
            runningApplications: { self.apps },
            subscribeToWorkspace: { callback in
                self.workspaceCallback = callback
                return self.workspace
            },
            applicationElement: AXUIElementCreateApplication,
            makeObserver: { pid, callback in
                let token = FakeObserverToken(pid: pid, callback: callback, log: self.log)
                token.unsupported = self.unsupported[pid] ?? []
                token.failures = self.failures[pid] ?? []
                token.attachResult = !self.attachFailures.contains(pid)
                self.tokens[pid] = token
                return .success(token)
            },
            makeLane: { pid in
                if let lane = self.lanes[pid] { return lane }
                let lane = FakeObserverLane()
                self.lanes[pid] = lane
                return lane
            },
            deliverOnMain: { $0() },
            eventSink: { self.events.append($0) }
        )
    }
}

private func elementPID(_ element: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
}

let axObserverRegistryTests: [TestCase] = [
    TestCase(name: "AXObserverRegistry seeds current regular applications once") {
        let environment = ObserverEnvironment()
        environment.apps = [
            environment.app(42),
            environment.app(43, regular: false),
            environment.app(44, terminated: true),
            environment.app(environment.selfPID),
        ]
        environment.client.windows[42] = [environment.window(142)]
        let registry = environment.registry()

        registry.start()
        registry.start()

        try expectEqual(environment.tokens.keys.sorted(), [42])
        try expectEqual(environment.tokens[42]?.attached, 1)
        try expectEqual(environment.events.map(\.kind), [.seeded])
        try expectEqual(environment.events.map { $0.identity.pid }, [42])
    },
    TestCase(name: "AXObserverRegistry configures timeout before every notification") {
        let environment = ObserverEnvironment()
        environment.apps = [environment.app(42)]
        environment.client.windows[42] = [environment.window(142)]
        let registry = environment.registry()

        registry.start()

        let calls = environment.log.compactMap { $0 as? String }
        for index in calls.indices where calls[index].hasPrefix("add-") {
            try expect(index > 0 && calls[index - 1].hasPrefix("prepare-"))
        }
        let added = calls.filter { $0.hasPrefix("add-") }
        try expect(added.contains { $0.contains(kAXWindowCreatedNotification as String) })
        try expect(added.contains { $0.contains(kAXFocusedWindowChangedNotification as String) })
        try expect(added.contains { $0.contains(kAXMovedNotification as String) })
        try expect(added.contains { $0.contains(kAXResizedNotification as String) })
        try expect(added.contains { $0.contains(kAXUIElementDestroyedNotification as String) })
    },
    TestCase(name: "AXObserverRegistry contains unsupported and failed application registration") {
        let environment = ObserverEnvironment()
        environment.apps = [environment.app(42), environment.app(43), environment.app(44)]
        environment.client.windows[42] = [environment.window(142)]
        environment.client.windows[43] = [environment.window(143)]
        environment.client.windows[44] = [environment.window(144)]
        environment.unsupported[42] = [kAXMovedNotification as String]
        environment.failures[43] = [kAXResizedNotification as String]
        environment.attachFailures.insert(44)
        let registry = environment.registry()

        registry.start()

        try expectEqual(environment.tokens[42]?.attached, 1)
        try expectEqual(environment.tokens[43]?.attached, 0)
        try expectEqual(environment.tokens[44]?.attached, 0)
        try expectEqual(environment.events.map { $0.identity.pid }, [42])
    },
    TestCase(name: "AXObserverRegistry responds to launch terminate activate and unhide") {
        let environment = ObserverEnvironment()
        let registry = environment.registry()
        registry.start()
        let first = environment.window(142)
        environment.client.windows[42] = [first]

        environment.workspaceCallback?(AXApplicationEvent(kind: .launched, application: environment.app(42)))
        let second = environment.window(242)
        environment.client.windows[42] = [first, second]
        environment.workspaceCallback?(AXApplicationEvent(kind: .activated, application: environment.app(42)))
        environment.workspaceCallback?(AXApplicationEvent(kind: .unhidden, application: environment.app(42)))
        environment.workspaceCallback?(AXApplicationEvent(kind: .terminated, application: environment.app(42, terminated: true)))

        try expectEqual(environment.events.map(\.kind), [.seeded, .shown, .shown, .shown, .shown])
        try expectEqual(environment.tokens[42]?.detached, 1)
    },
    TestCase(name: "AXObserverRegistry emits window events and registers created windows") {
        let environment = ObserverEnvironment()
        let app = AXUIElementCreateApplication(42)
        let first = environment.window(142)
        let second = environment.window(242)
        environment.apps = [environment.app(42)]
        environment.client.windows[42] = [first]
        let registry = environment.registry()
        registry.start()
        guard let token = environment.tokens[42] else { throw TestFailure(description: "missing token") }

        token.callback(first, kAXMovedNotification as CFString)
        environment.client.windows[42] = [first, second]
        token.callback(app, kAXWindowCreatedNotification as CFString)
        environment.client.focused[42] = second
        token.callback(app, kAXFocusedWindowChangedNotification as CFString)
        token.callback(second, kAXUIElementDestroyedNotification as CFString)

        try expectEqual(environment.events.map(\.kind), [.seeded, .moved, .created, .focused, .destroyed])
    },
    TestCase(name: "AXObserverRegistry stale callbacks are inert after idempotent stop") {
        let environment = ObserverEnvironment()
        environment.apps = [environment.app(42)]
        let window = environment.window(142)
        environment.client.windows[42] = [window]
        let registry = environment.registry()
        registry.start()
        guard let token = environment.tokens[42] else { throw TestFailure(description: "missing token") }

        registry.stop()
        registry.stop()
        token.callback(window, kAXMovedNotification as CFString)
        environment.workspaceCallback?(AXApplicationEvent(kind: .launched, application: environment.app(43)))

        try expectEqual(environment.workspace.cancelCount, 1)
        try expectEqual(token.detached, 1)
        try expectEqual(environment.events.map(\.kind), [.seeded])
        try expect(environment.tokens[43] == nil)
    },
    TestCase(name: "AXObserverRegistry isolates work lanes by application") {
        let environment = ObserverEnvironment()
        environment.apps = [environment.app(42), environment.app(43)]
        environment.client.windows[42] = [environment.window(142)]
        environment.client.windows[43] = [environment.window(143)]
        let held = FakeObserverLane()
        held.held = true
        environment.lanes[42] = held
        let registry = environment.registry()

        registry.start()

        try expectEqual(environment.events.map { $0.identity.pid }, [43])
        try expectEqual(environment.tokens[43]?.attached, 1)
        held.flush()
        try expectEqual(environment.events.map { $0.identity.pid }, [43, 42])
        try expectEqual(environment.tokens[42]?.attached, 1)
    },
]
