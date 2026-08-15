import AppKit
import ApplicationServices
import Foundation
import ScreenFixCore

public protocol WindowGuardTimer: AnyObject {
    func cancel()
}

public protocol WindowGuardEventSource: AnyObject {
    func start()
    func stop()
    func lane(for pid: pid_t) -> AXWorkLane?
}

public protocol WindowGuardWindowAccess: AnyObject {
    func facts(
        for identity: AXWindowIdentity,
        screenFixPID: pid_t,
        target: WindowGuardTarget
    ) throws -> WindowFacts
    func isSizeSettable(for identity: AXWindowIdentity) throws -> Bool
    func setSize(_ size: CGSize, for identity: AXWindowIdentity) throws
    func setPosition(_ position: CGPoint, for identity: AXWindowIdentity) throws
    func frame(for identity: AXWindowIdentity) throws -> RectD
}

public struct WindowGuardTarget: Equatable {
    public let selectedDisplayID: String
    public let workArea: RectD
    public let masks: [RectD]
    public let displays: [DisplayFrame]

    public init(
        selectedDisplayID: String,
        workArea: RectD,
        masks: [RectD],
        displays: [DisplayFrame]
    ) {
        self.selectedDisplayID = selectedDisplayID
        self.workArea = workArea
        self.masks = masks
        self.displays = displays
    }
}

private final class WindowGuardCancellation {
    private let lock = NSLock()
    private var valid = true

    func invalidate() {
        lock.lock()
        valid = false
        lock.unlock()
    }

    func isValid() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }
}

private struct WindowGuardRequest {
    let token: WindowGuardCancellation
    var timer: WindowGuardTimer?
}

private enum WindowGuardResult {
    case corrected(RectD)
    case ignored
    case refused
    case permissionLost
}

public final class WindowGuardController {
    public typealias Schedule = (
        _ delay: TimeInterval,
        _ callback: @escaping () -> Void
    ) -> WindowGuardTimer?

    private let source: WindowGuardEventSource
    private let access: WindowGuardWindowAccess
    private let screenFixPID: pid_t
    private let schedule: Schedule
    private let now: () -> TimeInterval
    private let deliverOnMain: (@escaping () -> Void) -> Void
    private let permissionLost: () -> Void

    private var target: WindowGuardTarget?
    private var sessionToken = WindowGuardCancellation()
    private var requests: [AXWindowIdentity: WindowGuardRequest] = [:]
    private var recentTargets: [AXWindowIdentity: (frame: RectD, expires: TimeInterval)] = [:]
    private var blockedUntil: [AXWindowIdentity: TimeInterval] = [:]
    private var started = false

    public init(
        source: WindowGuardEventSource,
        access: WindowGuardWindowAccess,
        screenFixPID: pid_t = getpid(),
        schedule: @escaping Schedule = WindowGuardController.scheduleOnMainRunLoop,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        deliverOnMain: @escaping (@escaping () -> Void) -> Void = {
            DispatchQueue.main.async(execute: $0)
        },
        permissionLost: @escaping () -> Void
    ) {
        self.source = source
        self.access = access
        self.screenFixPID = screenFixPID
        self.schedule = schedule
        self.now = now
        self.deliverOnMain = deliverOnMain
        self.permissionLost = permissionLost
    }

    public func start(target newTarget: WindowGuardTarget) {
        dispatchPrecondition(condition: .onQueue(.main))
        if started, target == newTarget { return }
        sessionToken.invalidate()
        invalidateRequests()
        sessionToken = WindowGuardCancellation()
        target = newTarget
        recentTargets.removeAll()
        blockedUntil.removeAll()
        guard !started else { return }
        started = true
        source.start()
    }

    public func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard started else { return }
        started = false
        target = nil
        sessionToken.invalidate()
        source.stop()
        invalidateRequests()
        recentTargets.removeAll()
        blockedUntil.removeAll()
    }

    public func handle(_ event: AXWindowEvent) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard started else { return }
        switch event.kind {
        case .destroyed, .minimized:
            retire(event.identity)
        case .seeded, .shown, .created, .focused, .moved, .resized, .deminiaturized:
            debounce(event.identity)
        }
    }

    private func debounce(_ identity: AXWindowIdentity) {
        retireRequest(identity)
        let token = WindowGuardCancellation()
        requests[identity] = WindowGuardRequest(token: token, timer: nil)
        let callback = { [weak self, weak token] in
            guard let self, let token else { return }
            self.fire(identity, token: token)
        }
        guard let timer = schedule(0.15, callback) else {
            if requests[identity]?.token === token { requests.removeValue(forKey: identity) }
            token.invalidate()
            return
        }
        guard requests[identity]?.token === token, token.isValid() else {
            timer.cancel()
            return
        }
        requests[identity]?.timer = timer
    }

    private func fire(_ identity: AXWindowIdentity, token: WindowGuardCancellation) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard started,
              requests[identity]?.token === token,
              token.isValid(),
              let target,
              let lane = source.lane(for: identity.pid) else {
            if requests[identity]?.token === token { requests.removeValue(forKey: identity) }
            return
        }
        requests[identity]?.timer = nil
        prune(identity)
        if let deadline = blockedUntil[identity], deadline > now() {
            requests.removeValue(forKey: identity)
            token.invalidate()
            return
        }
        let session = sessionToken
        let recent = recentTargets[identity]
        lane.submit { [weak self, weak token, weak session] in
            guard let self, let token, let session else { return }
            let result = self.correct(
                identity,
                target: target,
                recent: recent,
                token: token,
                session: session
            )
            guard token.isValid(), session.isValid() else { return }
            self.deliverOnMain { [weak self, weak token, weak session] in
                guard let self, let token, let session else { return }
                self.finish(identity, token: token, session: session, result: result)
            }
        }
    }

    private func correct(
        _ identity: AXWindowIdentity,
        target: WindowGuardTarget,
        recent: (frame: RectD, expires: TimeInterval)?,
        token: WindowGuardCancellation,
        session: WindowGuardCancellation
    ) -> WindowGuardResult {
        do {
            guard valid(token, session) else { return .ignored }
            let facts = try access.facts(for: identity, screenFixPID: screenFixPID, target: target)
            guard valid(token, session), WindowEligibility.isEligible(facts), let frame = facts.frame else {
                return .ignored
            }
            if let recent,
               recent.expires > now(),
               WindowCorrection.framesNear(frame, recent.frame, tolerance: 1) {
                return .ignored
            }
            guard let corrected = WindowCorrection.target(
                window: frame,
                workArea: target.workArea,
                masks: target.masks
            ) else {
                return .ignored
            }
            guard !WindowCorrection.framesNear(frame, corrected, tolerance: 1) else {
                return .ignored
            }

            let needsSize = abs(frame.width - corrected.width) > 1
                || abs(frame.height - corrected.height) > 1
            let needsPosition = abs(frame.x - corrected.x) > 1
                || abs(frame.y - corrected.y) > 1
            if needsSize {
                guard valid(token, session), try access.isSizeSettable(for: identity) else {
                    return .refused
                }
                guard valid(token, session) else { return .ignored }
                try access.setSize(
                    CGSize(width: corrected.width, height: corrected.height),
                    for: identity
                )
            }
            if needsPosition {
                guard valid(token, session) else { return .ignored }
                try access.setPosition(CGPoint(x: corrected.x, y: corrected.y), for: identity)
            }
            guard valid(token, session) else { return .ignored }
            let actual = try access.frame(for: identity)
            guard valid(token, session) else { return .ignored }
            return WindowCorrection.framesNear(actual, corrected, tolerance: 1)
                ? .corrected(corrected)
                : .refused
        } catch AXClientError.api(.apiDisabled) {
            return .permissionLost
        } catch {
            return .refused
        }
    }

    private func finish(
        _ identity: AXWindowIdentity,
        token: WindowGuardCancellation,
        session: WindowGuardCancellation,
        result: WindowGuardResult
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard started,
              session === sessionToken,
              session.isValid(),
              token.isValid(),
              requests[identity]?.token === token else {
            return
        }
        requests.removeValue(forKey: identity)
        token.invalidate()
        switch result {
        case let .corrected(frame):
            recentTargets[identity] = (frame, now() + 0.25)
            blockedUntil.removeValue(forKey: identity)
        case .refused:
            blockedUntil[identity] = now() + 1
        case .permissionLost:
            permissionLost()
        case .ignored:
            break
        }
    }

    private func prune(_ identity: AXWindowIdentity) {
        let current = now()
        if let recent = recentTargets[identity], recent.expires <= current {
            recentTargets.removeValue(forKey: identity)
        }
        if let deadline = blockedUntil[identity], deadline <= current {
            blockedUntil.removeValue(forKey: identity)
        }
    }

    private func retire(_ identity: AXWindowIdentity) {
        retireRequest(identity)
        recentTargets.removeValue(forKey: identity)
        blockedUntil.removeValue(forKey: identity)
    }

    private func retireRequest(_ identity: AXWindowIdentity) {
        guard let request = requests.removeValue(forKey: identity) else { return }
        request.token.invalidate()
        request.timer?.cancel()
    }

    private func invalidateRequests() {
        let retired = requests.values
        requests.removeAll()
        retired.forEach {
            $0.token.invalidate()
            $0.timer?.cancel()
        }
    }

    private func valid(_ request: WindowGuardCancellation, _ session: WindowGuardCancellation) -> Bool {
        request.isValid() && session.isValid()
    }

    public static func scheduleOnMainRunLoop(
        _ delay: TimeInterval,
        _ callback: @escaping () -> Void
    ) -> WindowGuardTimer? {
        MainRunLoopWindowGuardTimer(delay: delay, callback: callback)
    }
}

private final class MainRunLoopWindowGuardTimer: WindowGuardTimer {
    private var timer: Timer?

    init(delay: TimeInterval, callback: @escaping () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in callback() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

public final class SystemWindowGuardAccess: WindowGuardWindowAccess {
    private let client: AXClient
    private let application: (pid_t) -> NSRunningApplication?

    public init(
        client: AXClient = AXClient(),
        application: @escaping (pid_t) -> NSRunningApplication? = NSRunningApplication.init
    ) {
        self.client = client
        self.application = application
    }

    public func facts(
        for identity: AXWindowIdentity,
        screenFixPID: pid_t,
        target: WindowGuardTarget
    ) throws -> WindowFacts {
        let frame = try frame(for: identity)
        let owner = application(identity.pid)
        return WindowFacts(
            ownerPID: identity.pid,
            screenFixPID: screenFixPID,
            ownerIsRegular: owner.map { $0.activationPolicy == .regular },
            ownerIsHidden: owner?.isHidden,
            ownerIsTerminated: owner?.isTerminated,
            role: try client.string(identity.element, attribute: kAXRoleAttribute as CFString),
            subrole: try client.string(identity.element, attribute: kAXSubroleAttribute as CFString),
            minimized: try client.bool(identity.element, attribute: kAXMinimizedAttribute as CFString),
            frame: frame,
            positionSettable: try client.isSettable(
                identity.element,
                attribute: kAXPositionAttribute as CFString
            ),
            assignedDisplayID: DisplayAssignment.stableID(for: frame, displays: target.displays),
            selectedDisplayID: target.selectedDisplayID,
            fullDisplayFrames: target.displays.map(\.frame)
        )
    }

    public func isSizeSettable(for identity: AXWindowIdentity) throws -> Bool {
        try client.isSettable(identity.element, attribute: kAXSizeAttribute as CFString)
    }

    public func setSize(_ size: CGSize, for identity: AXWindowIdentity) throws {
        try client.setSize(identity.element, attribute: kAXSizeAttribute as CFString, value: size)
    }

    public func setPosition(_ position: CGPoint, for identity: AXWindowIdentity) throws {
        try client.setPoint(identity.element, attribute: kAXPositionAttribute as CFString, value: position)
    }

    public func frame(for identity: AXWindowIdentity) throws -> RectD {
        let position = try client.point(identity.element, attribute: kAXPositionAttribute as CFString)
        let size = try client.size(identity.element, attribute: kAXSizeAttribute as CFString)
        return RectD(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }
}
