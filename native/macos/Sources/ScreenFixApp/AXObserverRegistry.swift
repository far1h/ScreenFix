import AppKit
import ApplicationServices
import Foundation

public protocol AXObserverClient: AnyObject {
    func prepare(_ element: AXUIElement) throws
    func elements(_ element: AXUIElement, attribute: CFString) throws -> [AXUIElement]
    func element(_ element: AXUIElement, attribute: CFString) throws -> AXUIElement
}

extension AXClient: AXObserverClient {}

public protocol AXObserverToken: AnyObject {
    func addNotification(_ notification: CFString, element: AXUIElement) -> AXError
    func removeNotification(_ notification: CFString, element: AXUIElement) -> AXError
    func attachToMainRunLoop() -> Bool
    func detachFromMainRunLoop()
}

public protocol AXWorkLane: AnyObject {
    func submit(_ work: @escaping () -> Void)
}

public final class DispatchAXWorkLane: AXWorkLane {
    private let queue: DispatchQueue

    public init(pid: pid_t) {
        queue = DispatchQueue(label: "screenfix.ax.\(pid)")
    }

    public func submit(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }
}

public protocol AXWorkspaceObservation: AnyObject {
    func cancel()
}

public struct AXObservedApplication: Equatable {
    public let pid: pid_t
    public let isRegular: Bool
    public let isHidden: Bool
    public let isTerminated: Bool

    public init(pid: pid_t, isRegular: Bool, isHidden: Bool, isTerminated: Bool) {
        self.pid = pid
        self.isRegular = isRegular
        self.isHidden = isHidden
        self.isTerminated = isTerminated
    }
}

public enum AXApplicationEventKind: Equatable {
    case launched
    case terminated
    case activated
    case unhidden
}

public struct AXApplicationEvent: Equatable {
    public let kind: AXApplicationEventKind
    public let application: AXObservedApplication

    public init(kind: AXApplicationEventKind, application: AXObservedApplication) {
        self.kind = kind
        self.application = application
    }
}

public enum AXWindowEventKind: Equatable {
    case seeded
    case shown
    case created
    case focused
    case moved
    case resized
    case minimized
    case deminiaturized
    case destroyed
}

public struct AXWindowEvent {
    public let identity: AXWindowIdentity
    public let element: AXUIElement
    public let kind: AXWindowEventKind

    public init(identity: AXWindowIdentity, element: AXUIElement, kind: AXWindowEventKind) {
        self.identity = identity
        self.element = element
        self.kind = kind
    }
}

public enum AXObserverCreation {
    case success(AXObserverToken)
    case failure(AXError)
}

private enum AXObserverRegistryError: Error {
    case registration(AXError)
}

private struct AXRegistration {
    let element: AXUIElement
    let notification: CFString
}

private final class AXApplicationSession {
    let pid: pid_t
    let revision: Int
    let applicationElement: AXUIElement
    let observer: AXObserverToken
    let lane: AXWorkLane
    var registrations: [AXRegistration]
    var windows: Set<AXWindowIdentity>

    init(
        pid: pid_t,
        revision: Int,
        applicationElement: AXUIElement,
        observer: AXObserverToken,
        lane: AXWorkLane,
        registrations: [AXRegistration],
        windows: Set<AXWindowIdentity>
    ) {
        self.pid = pid
        self.revision = revision
        self.applicationElement = applicationElement
        self.observer = observer
        self.lane = lane
        self.registrations = registrations
        self.windows = windows
    }
}

public final class AXObserverRegistry {
    public typealias WorkspaceSubscribe = (@escaping (AXApplicationEvent) -> Void) -> AXWorkspaceObservation?
    public typealias ObserverFactory = (
        pid_t,
        @escaping (AXUIElement, CFString) -> Void
    ) -> AXObserverCreation

    private let client: AXObserverClient
    private let screenFixPID: pid_t
    private let runningApplications: () -> [AXObservedApplication]
    private let subscribeToWorkspace: WorkspaceSubscribe
    private let applicationElement: (pid_t) -> AXUIElement
    private let makeObserver: ObserverFactory
    private let makeLane: (pid_t) -> AXWorkLane
    private let deliverOnMain: (@escaping () -> Void) -> Void
    private let eventSink: (AXWindowEvent) -> Void

    private var workspaceObservation: AXWorkspaceObservation?
    private var sessions: [pid_t: AXApplicationSession] = [:]
    private var revisions: [pid_t: Int] = [:]
    private var pending = Set<pid_t>()
    private var generation = 0
    private var started = false

    public init(
        client: AXObserverClient,
        screenFixPID: pid_t,
        runningApplications: @escaping () -> [AXObservedApplication],
        subscribeToWorkspace: @escaping WorkspaceSubscribe,
        applicationElement: @escaping (pid_t) -> AXUIElement,
        makeObserver: @escaping ObserverFactory,
        makeLane: @escaping (pid_t) -> AXWorkLane,
        deliverOnMain: @escaping (@escaping () -> Void) -> Void,
        eventSink: @escaping (AXWindowEvent) -> Void
    ) {
        self.client = client
        self.screenFixPID = screenFixPID
        self.runningApplications = runningApplications
        self.subscribeToWorkspace = subscribeToWorkspace
        self.applicationElement = applicationElement
        self.makeObserver = makeObserver
        self.makeLane = makeLane
        self.deliverOnMain = deliverOnMain
        self.eventSink = eventSink
    }

    public convenience init(
        client: AXClient = AXClient(),
        screenFixPID: pid_t = getpid(),
        eventSink: @escaping (AXWindowEvent) -> Void
    ) {
        self.init(
            client: client,
            screenFixPID: screenFixPID,
            runningApplications: {
                NSWorkspace.shared.runningApplications.map(AXObservedApplication.init)
            },
            subscribeToWorkspace: { SystemAXWorkspaceObservation(callback: $0) },
            applicationElement: AXUIElementCreateApplication,
            makeObserver: SystemAXObserverToken.make,
            makeLane: DispatchAXWorkLane.init,
            deliverOnMain: { DispatchQueue.main.async(execute: $0) },
            eventSink: eventSink
        )
    }

    public func start() {
        guard !started else { return }
        started = true
        generation += 1
        let activeGeneration = generation
        workspaceObservation = subscribeToWorkspace { [weak self] event in
            self?.deliverOnMain { [weak self] in
                self?.handle(event, generation: activeGeneration)
            }
        }
        runningApplications().forEach { install($0, generation: activeGeneration) }
    }

    public func stop() {
        guard started || workspaceObservation != nil || !sessions.isEmpty || !pending.isEmpty else {
            return
        }
        generation += 1
        started = false
        let observation = workspaceObservation
        workspaceObservation = nil
        pending.removeAll()
        let retired = Array(sessions.values)
        sessions.removeAll()
        revisions.removeAll()
        observation?.cancel()
        retired.forEach(retire)
    }

    private func handle(_ event: AXApplicationEvent, generation activeGeneration: Int) {
        guard started, generation == activeGeneration else { return }
        switch event.kind {
        case .launched:
            install(event.application, generation: activeGeneration)
        case .terminated:
            invalidate(pid: event.application.pid)
        case .activated, .unhidden:
            guard isObservable(event.application) else { return }
            if sessions[event.application.pid] == nil {
                install(event.application, generation: activeGeneration)
            } else {
                refreshAll(pid: event.application.pid, kind: .shown, emitExisting: true)
            }
        }
    }

    private func install(_ application: AXObservedApplication, generation activeGeneration: Int) {
        guard started,
              generation == activeGeneration,
              isObservable(application),
              sessions[application.pid] == nil,
              !pending.contains(application.pid) else {
            return
        }
        let pid = application.pid
        let revision = (revisions[pid] ?? 0) + 1
        revisions[pid] = revision
        pending.insert(pid)
        let lane = makeLane(pid)
        lane.submit { [weak self] in
            guard let self else { return }
            let applicationElement = self.applicationElement(pid)
            let creation = self.makeObserver(pid) { [weak self] element, notification in
                self?.deliverOnMain { [weak self] in
                    self?.handleNotification(
                        pid: pid,
                        revision: revision,
                        generation: activeGeneration,
                        element: element,
                        notification: notification
                    )
                }
            }
            guard case let .success(observer) = creation else {
                self.deliverOnMain { [weak self] in
                    self?.finishFailedInstall(pid: pid, revision: revision, generation: activeGeneration)
                }
                return
            }

            var registrations: [AXRegistration] = []
            do {
                try self.register(
                    Self.applicationNotifications,
                    element: applicationElement,
                    observer: observer,
                    registrations: &registrations
                )
                let windows = try self.client.elements(
                    applicationElement,
                    attribute: kAXWindowsAttribute as CFString
                )
                for window in windows {
                    try self.register(
                        Self.windowNotifications,
                        element: window,
                        observer: observer,
                        registrations: &registrations
                    )
                }
                let identities = Set(windows.map { AXWindowIdentity(pid: pid, element: $0) })
                self.deliverOnMain { [weak self] in
                    self?.finishInstall(
                        pid: pid,
                        revision: revision,
                        generation: activeGeneration,
                        applicationElement: applicationElement,
                        observer: observer,
                        lane: lane,
                        registrations: registrations,
                        windows: windows,
                        identities: identities
                    )
                }
            } catch {
                self.rollback(registrations, observer: observer)
                self.deliverOnMain { [weak self] in
                    self?.finishFailedInstall(pid: pid, revision: revision, generation: activeGeneration)
                }
            }
        }
    }

    private func finishInstall(
        pid: pid_t,
        revision: Int,
        generation activeGeneration: Int,
        applicationElement: AXUIElement,
        observer: AXObserverToken,
        lane: AXWorkLane,
        registrations: [AXRegistration],
        windows: [AXUIElement],
        identities: Set<AXWindowIdentity>
    ) {
        guard started,
              generation == activeGeneration,
              revisions[pid] == revision,
              sessions[pid] == nil,
              observer.attachToMainRunLoop() else {
            pending.remove(pid)
            lane.submit { [weak self] in self?.rollback(registrations, observer: observer) }
            return
        }
        pending.remove(pid)
        sessions[pid] = AXApplicationSession(
            pid: pid,
            revision: revision,
            applicationElement: applicationElement,
            observer: observer,
            lane: lane,
            registrations: registrations,
            windows: identities
        )
        windows.forEach { emit(pid: pid, element: $0, kind: .seeded) }
    }

    private func finishFailedInstall(pid: pid_t, revision: Int, generation activeGeneration: Int) {
        guard generation == activeGeneration, revisions[pid] == revision else { return }
        pending.remove(pid)
    }

    private func invalidate(pid: pid_t) {
        revisions[pid] = (revisions[pid] ?? 0) + 1
        pending.remove(pid)
        guard let session = sessions.removeValue(forKey: pid) else { return }
        retire(session)
    }

    private func retire(_ session: AXApplicationSession) {
        session.observer.detachFromMainRunLoop()
        let registrations = session.registrations
        session.registrations.removeAll()
        session.windows.removeAll()
        session.lane.submit { [weak self] in
            self?.rollback(registrations, observer: session.observer)
        }
    }

    private func register(
        _ notifications: [CFString],
        element: AXUIElement,
        observer: AXObserverToken,
        registrations: inout [AXRegistration]
    ) throws {
        for notification in notifications {
            try client.prepare(element)
            let result = observer.addNotification(notification, element: element)
            if result == .success {
                registrations.append(AXRegistration(element: element, notification: notification))
            } else if result != .notificationUnsupported {
                throw AXObserverRegistryError.registration(result)
            }
        }
    }

    private func rollback(_ registrations: [AXRegistration], observer: AXObserverToken) {
        for registration in registrations.reversed() {
            guard (try? client.prepare(registration.element)) != nil else { continue }
            _ = observer.removeNotification(registration.notification, element: registration.element)
        }
    }

    private func handleNotification(
        pid: pid_t,
        revision: Int,
        generation activeGeneration: Int,
        element: AXUIElement,
        notification: CFString
    ) {
        guard started,
              generation == activeGeneration,
              let session = sessions[pid],
              session.revision == revision else {
            return
        }
        switch notification as String {
        case kAXWindowCreatedNotification:
            refreshAll(pid: pid, kind: .created, emitExisting: false)
        case kAXFocusedWindowChangedNotification:
            refreshFocused(pid: pid)
        case kAXMovedNotification:
            emit(pid: pid, element: element, kind: .moved)
        case kAXResizedNotification:
            emit(pid: pid, element: element, kind: .resized)
        case kAXWindowMiniaturizedNotification:
            emit(pid: pid, element: element, kind: .minimized)
        case kAXWindowDeminiaturizedNotification:
            emit(pid: pid, element: element, kind: .deminiaturized)
        case kAXUIElementDestroyedNotification:
            session.windows.remove(AXWindowIdentity(pid: pid, element: element))
            emit(pid: pid, element: element, kind: .destroyed)
        default:
            break
        }
    }

    private func refreshAll(pid: pid_t, kind: AXWindowEventKind, emitExisting: Bool) {
        guard let session = sessions[pid] else { return }
        let activeGeneration = generation
        let revision = session.revision
        let known = session.windows
        session.lane.submit { [weak self] in
            guard let self else { return }
            var registrations: [AXRegistration] = []
            do {
                let windows = try self.client.elements(
                    session.applicationElement,
                    attribute: kAXWindowsAttribute as CFString
                )
                for window in windows where !known.contains(AXWindowIdentity(pid: pid, element: window)) {
                    try self.register(
                        Self.windowNotifications,
                        element: window,
                        observer: session.observer,
                        registrations: &registrations
                    )
                }
                self.deliverOnMain { [weak self] in
                    self?.finishRefresh(
                        pid: pid,
                        revision: revision,
                        generation: activeGeneration,
                        windows: windows,
                        registrations: registrations,
                        observer: session.observer,
                        lane: session.lane,
                        kind: kind,
                        emitExisting: emitExisting
                    )
                }
            } catch {
                self.rollback(registrations, observer: session.observer)
            }
        }
    }

    private func finishRefresh(
        pid: pid_t,
        revision: Int,
        generation activeGeneration: Int,
        windows: [AXUIElement],
        registrations: [AXRegistration],
        observer: AXObserverToken,
        lane: AXWorkLane,
        kind: AXWindowEventKind,
        emitExisting: Bool
    ) {
        guard started,
              generation == activeGeneration,
              let session = sessions[pid],
              session.revision == revision else {
            lane.submit { [weak self] in self?.rollback(registrations, observer: observer) }
            return
        }
        session.registrations.append(contentsOf: registrations)
        for window in windows {
            let identity = AXWindowIdentity(pid: pid, element: window)
            let wasKnown = session.windows.contains(identity)
            session.windows.insert(identity)
            if emitExisting || !wasKnown {
                emit(pid: pid, element: window, kind: kind)
            }
        }
    }

    private func refreshFocused(pid: pid_t) {
        guard let session = sessions[pid] else { return }
        let activeGeneration = generation
        let revision = session.revision
        let known = session.windows
        session.lane.submit { [weak self] in
            guard let self else { return }
            var registrations: [AXRegistration] = []
            do {
                let window = try self.client.element(
                    session.applicationElement,
                    attribute: kAXFocusedWindowAttribute as CFString
                )
                if !known.contains(AXWindowIdentity(pid: pid, element: window)) {
                    try self.register(
                        Self.windowNotifications,
                        element: window,
                        observer: session.observer,
                        registrations: &registrations
                    )
                }
                self.deliverOnMain { [weak self] in
                    self?.finishFocused(
                        pid: pid,
                        revision: revision,
                        generation: activeGeneration,
                        window: window,
                        registrations: registrations,
                        observer: session.observer,
                        lane: session.lane
                    )
                }
            } catch {
                self.rollback(registrations, observer: session.observer)
            }
        }
    }

    private func finishFocused(
        pid: pid_t,
        revision: Int,
        generation activeGeneration: Int,
        window: AXUIElement,
        registrations: [AXRegistration],
        observer: AXObserverToken,
        lane: AXWorkLane
    ) {
        guard started,
              generation == activeGeneration,
              let session = sessions[pid],
              session.revision == revision else {
            lane.submit { [weak self] in self?.rollback(registrations, observer: observer) }
            return
        }
        session.registrations.append(contentsOf: registrations)
        session.windows.insert(AXWindowIdentity(pid: pid, element: window))
        emit(pid: pid, element: window, kind: .focused)
    }

    private func emit(pid: pid_t, element: AXUIElement, kind: AXWindowEventKind) {
        eventSink(AXWindowEvent(
            identity: AXWindowIdentity(pid: pid, element: element),
            element: element,
            kind: kind
        ))
    }

    private func isObservable(_ application: AXObservedApplication) -> Bool {
        application.pid > 0
            && application.pid != screenFixPID
            && application.isRegular
            && !application.isTerminated
    }

    private static let applicationNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
    ]

    private static let windowNotifications: [CFString] = [
        kAXMovedNotification as CFString,
        kAXResizedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
    ]
}

private final class SystemAXObserverCallbackBox {
    let callback: (AXUIElement, CFString) -> Void

    init(callback: @escaping (AXUIElement, CFString) -> Void) {
        self.callback = callback
    }
}

private func systemAXObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    Unmanaged<SystemAXObserverCallbackBox>
        .fromOpaque(context)
        .takeUnretainedValue()
        .callback(element, notification)
}

private final class SystemAXObserverToken: AXObserverToken {
    private let observer: AXObserver
    private let callbackBox: SystemAXObserverCallbackBox
    private var attached = false

    private init(observer: AXObserver, callbackBox: SystemAXObserverCallbackBox) {
        self.observer = observer
        self.callbackBox = callbackBox
    }

    static func make(
        pid: pid_t,
        callback: @escaping (AXUIElement, CFString) -> Void
    ) -> AXObserverCreation {
        let callbackBox = SystemAXObserverCallbackBox(callback: callback)
        var observer: AXObserver?
        let result = AXObserverCreate(pid, systemAXObserverCallback, &observer)
        guard result == .success, let observer else { return .failure(result) }
        return .success(SystemAXObserverToken(observer: observer, callbackBox: callbackBox))
    }

    func addNotification(_ notification: CFString, element: AXUIElement) -> AXError {
        AXObserverAddNotification(
            observer,
            element,
            notification,
            Unmanaged.passUnretained(callbackBox).toOpaque()
        )
    }

    func removeNotification(_ notification: CFString, element: AXUIElement) -> AXError {
        AXObserverRemoveNotification(observer, element, notification)
    }

    func attachToMainRunLoop() -> Bool {
        guard !attached else { return true }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        attached = true
        return true
    }

    func detachFromMainRunLoop() {
        guard attached else { return }
        attached = false
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

private final class SystemAXWorkspaceObservation: AXWorkspaceObservation {
    private let center = NSWorkspace.shared.notificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(callback: @escaping (AXApplicationEvent) -> Void) {
        observe(NSWorkspace.didLaunchApplicationNotification, kind: .launched, callback: callback)
        observe(NSWorkspace.didTerminateApplicationNotification, kind: .terminated, callback: callback)
        observe(NSWorkspace.didActivateApplicationNotification, kind: .activated, callback: callback)
        observe(NSWorkspace.didUnhideApplicationNotification, kind: .unhidden, callback: callback)
    }

    func cancel() {
        let retired = tokens
        tokens.removeAll()
        retired.forEach(center.removeObserver)
    }

    private func observe(
        _ name: NSNotification.Name,
        kind: AXApplicationEventKind,
        callback: @escaping (AXApplicationEvent) -> Void
    ) {
        tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
                return
            }
            callback(AXApplicationEvent(
                kind: kind,
                application: AXObservedApplication(application)
            ))
        })
    }
}

private extension AXObservedApplication {
    init(_ application: NSRunningApplication) {
        self.init(
            pid: application.processIdentifier,
            isRegular: application.activationPolicy == .regular,
            isHidden: application.isHidden,
            isTerminated: application.isTerminated
        )
    }
}
