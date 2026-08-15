import ApplicationServices
import Foundation

public protocol AccessibilityTrustTimer: AnyObject {
    func cancel()
}

private final class SystemAccessibilityTrustTimer: AccessibilityTrustTimer {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer.invalidate()
    }
}

public final class AccessibilityTrustController {
    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> AccessibilityTrustTimer?

    private let promptCheck: () -> Bool
    private let silentCheck: () -> Bool
    private let schedule: Schedule
    private let stateDidChange: (Bool) -> Void

    private var timer: AccessibilityTrustTimer?
    private var timerID: Int?
    private var nextTimerID = 0
    private var generation = 0
    private var needsPermission = false
    private var hasPrompted = false
    private var currentTrust: Bool?

    public init(
        promptCheck: @escaping () -> Bool,
        silentCheck: @escaping () -> Bool,
        schedule: @escaping Schedule,
        stateDidChange: @escaping (Bool) -> Void
    ) {
        self.promptCheck = promptCheck
        self.silentCheck = silentCheck
        self.schedule = schedule
        self.stateDidChange = stateDidChange
    }

    public convenience init(stateDidChange: @escaping (Bool) -> Void) {
        self.init(
            promptCheck: Self.promptedTrustCheck,
            silentCheck: { AXIsProcessTrustedWithOptions(nil) },
            schedule: Self.scheduleOnMainRunLoop,
            stateDidChange: stateDidChange
        )
    }

    public var isTrusted: Bool {
        currentTrust ?? false
    }

    @discardableResult
    public func reconcile(needsPermission: Bool) -> Bool {
        guard needsPermission else {
            deactivate()
            return false
        }
        guard !self.needsPermission else {
            schedulePollIfNeeded(generation: generation)
            return isTrusted
        }

        self.needsPermission = true
        generation += 1
        let activeGeneration = generation
        let trusted: Bool
        if hasPrompted {
            trusted = silentCheck()
        } else {
            hasPrompted = true
            trusted = promptCheck()
        }
        guard self.needsPermission, generation == activeGeneration else { return false }
        currentTrust = trusted
        schedulePollIfNeeded(generation: activeGeneration)
        return trusted
    }

    public func stop() {
        deactivate()
    }

    private func deactivate() {
        generation += 1
        needsPermission = false
        currentTrust = nil
        let retired = timer
        timer = nil
        timerID = nil
        retired?.cancel()
    }

    private func schedulePollIfNeeded(generation activeGeneration: Int) {
        guard needsPermission, generation == activeGeneration, timerID == nil else { return }
        nextTimerID += 1
        let scheduledID = nextTimerID
        timerID = scheduledID
        let candidate = schedule(2) { [weak self] in
            self?.poll(generation: activeGeneration, timerID: scheduledID)
        }
        guard needsPermission, generation == activeGeneration, timerID == scheduledID else {
            candidate?.cancel()
            return
        }
        guard let candidate else {
            timerID = nil
            return
        }
        timer = candidate
    }

    private func poll(generation activeGeneration: Int, timerID scheduledID: Int) {
        guard needsPermission, generation == activeGeneration, timerID == scheduledID else { return }
        timer = nil
        timerID = nil
        let trusted = silentCheck()
        guard needsPermission, generation == activeGeneration else { return }
        let previous = currentTrust
        currentTrust = trusted
        if let previous, previous != trusted {
            stateDidChange(trusted)
        }
        guard needsPermission, generation == activeGeneration else { return }
        schedulePollIfNeeded(generation: activeGeneration)
    }

    private static func promptedTrustCheck() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: kCFBooleanTrue as Any] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func scheduleOnMainRunLoop(
        _ delay: TimeInterval,
        _ callback: @escaping () -> Void
    ) -> AccessibilityTrustTimer? {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in callback() }
        RunLoop.main.add(timer, forMode: .common)
        return SystemAccessibilityTrustTimer(timer: timer)
    }
}
