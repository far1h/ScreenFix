import AppKit
import ScreenFixCore

public protocol RuntimeConfigurationStore: AnyObject {
    func load() throws -> ScreenFixConfiguration?
    func save(_ configuration: ScreenFixConfiguration) throws
}

extension ConfigStore: RuntimeConfigurationStore {}

public protocol RuntimeDisplayCatalog: AnyObject {
    func connectedDisplays() -> [ConnectedScreen]
}

extension DisplayCatalog: RuntimeDisplayCatalog {}

public protocol RuntimeMaskOwner: AnyObject {
    func replace(
        frames: [RectD],
        screenFrame: NSRect,
        beforeRetire: () throws -> Void
    ) throws
    func removeAll()
}

extension MaskPanelController: RuntimeMaskOwner {
    public func replace(
        frames: [RectD],
        screenFrame: NSRect,
        beforeRetire: () throws -> Void
    ) throws {
        let prepared = try prepare(frames: frames, screenFrame: screenFrame)
        try commit(prepared, beforeRetire: beforeRetire)
    }
}

public protocol RuntimeCalibrationOwner: AnyObject {
    func start(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void,
        commitGuard: () throws -> Bool
    ) throws
    func stop()
}

extension CalibrationPanelController: RuntimeCalibrationOwner {
    public func start(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void,
        commitGuard: () throws -> Bool
    ) throws {
        let prepared = try prepare(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            bands: bands,
            onSave: onSave,
            onCancel: onCancel
        )
        do {
            try commit(prepared, commitGuard: commitGuard)
        } catch {
            discard(prepared)
            throw error
        }
    }
}

public protocol RuntimeAccessibilityTrustOwner: AnyObject {
    var isTrusted: Bool { get }
    @discardableResult
    func reconcile(needsPermission: Bool) -> Bool
    func stop()
}

extension AccessibilityTrustController: RuntimeAccessibilityTrustOwner {}

public protocol RuntimeWindowGuardOwner: AnyObject {
    func start(target: WindowGuardTarget)
    func stop()
    func handle(_ event: AXWindowEvent)
}

extension WindowGuardController: RuntimeWindowGuardOwner {}

private final class NoopRuntimeAccessibilityTrustOwner: RuntimeAccessibilityTrustOwner {
    var isTrusted: Bool { true }

    func reconcile(needsPermission: Bool) -> Bool {
        needsPermission
    }

    func stop() {}
}

private final class NoopRuntimeWindowGuardOwner: RuntimeWindowGuardOwner {
    func start(target: WindowGuardTarget) {}
    func stop() {}
    func handle(_ event: AXWindowEvent) {}
}

public protocol RuntimeNotifications: AnyObject {
    func subscribe(
        displayChanged: @escaping () -> Void,
        willSleep: @escaping () -> Void,
        woke: @escaping () -> Void
    ) -> [AnyObject]
    func unsubscribe(_ tokens: [AnyObject])
}

public final class SystemRuntimeNotifications: RuntimeNotifications {
    private let defaultCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter

    public init(
        defaultCenter: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.defaultCenter = defaultCenter
        self.workspaceCenter = workspaceCenter
    }

    public func subscribe(
        displayChanged: @escaping () -> Void,
        willSleep: @escaping () -> Void,
        woke: @escaping () -> Void
    ) -> [AnyObject] {
        let screenToken = defaultCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in displayChanged() }
        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in willSleep() }
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in woke() }
        return [screenToken as AnyObject, sleepToken as AnyObject, wakeToken as AnyObject]
    }

    public func unsubscribe(_ tokens: [AnyObject]) {
        guard tokens.count == 3 else { return }
        defaultCenter.removeObserver(tokens[0])
        workspaceCenter.removeObserver(tokens[1])
        workspaceCenter.removeObserver(tokens[2])
    }
}

public struct RuntimeSnapshot {
    public let configuration: ScreenFixConfiguration?
    public let displayConnected: Bool
    public let calibrating: Bool
    public let menuState: MenuState

    public init(
        configuration: ScreenFixConfiguration?,
        displayConnected: Bool,
        calibrating: Bool,
        menuState: MenuState
    ) {
        self.configuration = configuration
        self.displayConnected = displayConnected
        self.calibrating = calibrating
        self.menuState = menuState
    }
}

private enum RuntimeOperationError: Error {
    case configuration(Error)
    case mask(Error)
    case superseded
}

private enum RuntimeCalibrationCommitError: Error {
    case displayChanged
    case superseded
}

private struct RuntimeCalibrationSession {
    let token: Int
    let lifecycleGeneration: Int
    let target: ScreenFixConfiguration
    let base: ScreenFixConfiguration?
    let screenStableId: String?
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let pausedGuardTarget: WindowGuardTarget?
}

public final class RuntimeController {
    private let store: RuntimeConfigurationStore
    private let catalog: RuntimeDisplayCatalog
    private let maskOwner: RuntimeMaskOwner
    private let calibrationOwner: RuntimeCalibrationOwner
    private let accessibilityTrustOwner: RuntimeAccessibilityTrustOwner
    private let windowGuardOwner: RuntimeWindowGuardOwner
    private let notifications: RuntimeNotifications
    private let termination: () -> Void
    private let stateDidChange: () -> Void

    private var configuration: ScreenFixConfiguration?
    private var runtimeError: String?
    private var displayConnected = false
    private var accessibilityTrusted = false
    private var notificationTokens: [AnyObject] = []
    private var availableGuardTarget: WindowGuardTarget?
    private var activeGuardTarget: WindowGuardTarget?
    private var calibrationSession: RuntimeCalibrationSession?
    private var nextCalibrationToken = 0
    private var generation = 0
    private var started = false
    private var stopping = false
    private var sleeping = false
    private var terminated = false
    private var permissionRevoked = false
    private var guardTransitionInProgress = false
    private var calibrationCommitInProgress = false
    private var deferredRuntimeMutations: [() -> Void] = []

    public init(
        store: RuntimeConfigurationStore,
        catalog: RuntimeDisplayCatalog,
        maskOwner: RuntimeMaskOwner,
        calibrationOwner: RuntimeCalibrationOwner = CalibrationPanelController(),
        accessibilityTrustOwner: RuntimeAccessibilityTrustOwner,
        windowGuardOwner: RuntimeWindowGuardOwner,
        notifications: RuntimeNotifications,
        termination: @escaping () -> Void,
        stateDidChange: @escaping () -> Void
    ) {
        self.store = store
        self.catalog = catalog
        self.maskOwner = maskOwner
        self.calibrationOwner = calibrationOwner
        self.accessibilityTrustOwner = accessibilityTrustOwner
        self.windowGuardOwner = windowGuardOwner
        self.notifications = notifications
        self.termination = termination
        self.stateDidChange = stateDidChange
    }

    public convenience init(
        store: RuntimeConfigurationStore,
        catalog: RuntimeDisplayCatalog,
        maskOwner: RuntimeMaskOwner,
        calibrationOwner: RuntimeCalibrationOwner = CalibrationPanelController(),
        notifications: RuntimeNotifications,
        termination: @escaping () -> Void,
        stateDidChange: @escaping () -> Void
    ) {
        self.init(
            store: store,
            catalog: catalog,
            maskOwner: maskOwner,
            calibrationOwner: calibrationOwner,
            accessibilityTrustOwner: NoopRuntimeAccessibilityTrustOwner(),
            windowGuardOwner: NoopRuntimeWindowGuardOwner(),
            notifications: notifications,
            termination: termination,
            stateDidChange: stateDidChange
        )
    }

    public var snapshot: RuntimeSnapshot {
        RuntimeSnapshot(
            configuration: configuration,
            displayConnected: displayConnected,
            calibrating: calibrationSession != nil,
            menuState: MenuState.make(
                configuration: configuration,
                displayConnected: displayConnected,
                accessibilityTrusted: accessibilityTrusted,
                calibrating: calibrationSession != nil,
                runtimeError: runtimeError
            )
        )
    }

    public func start() {
        guard !started, !stopping else { return }
        started = true
        generation += 1
        let activeGeneration = generation
        notificationTokens = notifications.subscribe(
            displayChanged: { [weak self] in
                guard let self, self.started, self.generation == activeGeneration else { return }
                self.reconcile()
            },
            willSleep: { [weak self] in
                guard let self, self.started, self.generation == activeGeneration else { return }
                self.prepareForSleep()
            },
            woke: { [weak self] in
                guard let self, self.started, self.generation == activeGeneration else { return }
                self.resumeAfterWake()
            }
        )
        do {
            configuration = try store.load()
            guard started, generation == activeGeneration else { return }
            reconcileLoadedConfiguration(configuration)
        } catch {
            guard started, generation == activeGeneration else { return }
            configuration = nil
            displayConnected = false
            maskOwner.removeAll()
            reportConfiguration(error)
        }
        stateDidChange()
    }

    public func setEnabled(_ enabled: Bool) {
        if deferDuringCalibrationCommit({ runtime in runtime.setEnabled(enabled) }) { return }
        guard started, !sleeping else { return }
        guard cancelCalibrationAndRestore() else { return }
        guard let current = configuration, current.enabled != enabled else {
            stateDidChange()
            return
        }
        let desired = ScreenFixConfiguration(
            schemaVersion: current.schemaVersion,
            enabled: enabled,
            display: current.display,
            bands: current.bands
        )

        if !enabled {
            let activeGeneration = generation
            guardTransitionInProgress = true
            stopWindowGuard()
            do {
                try store.save(desired)
                guard started, generation == activeGeneration else {
                    guardTransitionInProgress = false
                    return
                }
                configuration = desired
                availableGuardTarget = nil
                guardTransitionInProgress = false
                stopAccessibilityTrust()
                maskOwner.removeAll()
                refreshConnection()
                runtimeError = nil
            } catch {
                guard started, generation == activeGeneration else {
                    guardTransitionInProgress = false
                    return
                }
                guardTransitionInProgress = false
                reportConfiguration(error)
                restoreAvailableWindowGuard()
            }
            stateDidChange()
            return
        }

        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: desired.display, from: screens) else {
            let activeGeneration = generation
            do {
                try store.save(desired)
                guard started, generation == activeGeneration else { return }
                configuration = desired
                displayConnected = false
                availableGuardTarget = nil
                stopAccessibilityTrust()
                runtimeError = nil
            } catch {
                guard started, generation == activeGeneration else { return }
                reportConfiguration(error)
            }
            stateDidChange()
            return
        }

        replace(with: desired, on: screen, screens: screens, persist: true)
        stateDidChange()
    }

    public func selectDisplay(stableId: String) {
        if deferDuringCalibrationCommit({ runtime in runtime.selectDisplay(stableId: stableId) }) { return }
        guard started, !sleeping else { return }
        let screens = catalog.connectedDisplays()
        guard let screen = screens.first(where: { candidate in
            candidate.display.stableId?.caseInsensitiveCompare(stableId) == .orderedSame
        }), let selectedId = screen.display.stableId else { return }
        guard cancelCalibrationAndRestore() else { return }
        let identity = DisplayIdentity(
            stableId: selectedId,
            name: screen.display.name,
            width: screen.display.width,
            height: screen.display.height,
            vendorId: screen.display.vendorId,
            modelId: screen.display.modelId,
            serialNumber: screen.display.serialNumber
        )
        let desired = DefaultConfiguration.make(for: identity, enabled: true)
        beginCalibration(target: desired, on: screen, base: configuration, needsTemporaryMasks: true)
        stateDidChange()
    }

    public func toggleCalibration() {
        if deferDuringCalibrationCommit({ runtime in runtime.toggleCalibration() }) { return }
        guard started, !sleeping else { return }
        if calibrationSession != nil {
            if cancelCalibrationAndRestore() { stateDidChange() }
            return
        }
        guard let configuration else { return }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: configuration.display, from: screens) else {
            retireWindowCorrection()
            displayConnected = false
            maskOwner.removeAll()
            runtimeError = nil
            stateDidChange()
            return
        }
        beginCalibration(
            target: configuration,
            on: screen,
            base: configuration,
            needsTemporaryMasks: !configuration.enabled
        )
        stateDidChange()
    }

    public func resetToDefaults() {
        if deferDuringCalibrationCommit({ runtime in runtime.resetToDefaults() }) { return }
        guard started, !sleeping else { return }
        guard cancelCalibrationAndRestore() else { return }
        guard let current = configuration else {
            stateDidChange()
            return
        }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: current.display, from: screens) else {
            displayConnected = false
            retireWindowCorrection()
            maskOwner.removeAll()
            runtimeError = nil
            stateDidChange()
            return
        }
        let desired = DefaultConfiguration.make(for: current.display, enabled: current.enabled)
        if desired.enabled {
            replace(with: desired, on: screen, screens: screens, persist: true)
        } else {
            let activeGeneration = generation
            do {
                try store.save(desired)
                guard started, generation == activeGeneration else { return }
                configuration = desired
                displayConnected = true
                runtimeError = nil
            } catch {
                guard started, generation == activeGeneration else { return }
                reportConfiguration(error)
            }
        }
        stateDidChange()
    }

    public func reload() {
        if deferDuringCalibrationCommit({ runtime in runtime.reload() }) { return }
        guard started, !sleeping else { return }
        guard cancelCalibrationAndRestore() else { return }
        let activeGeneration = generation
        do {
            let loaded = try store.load()
            guard started, generation == activeGeneration else { return }
            reconcileLoadedConfiguration(loaded)
        } catch {
            guard started, generation == activeGeneration else { return }
            reportConfiguration(error)
        }
        stateDidChange()
    }

    public func reconcile() {
        if deferDuringCalibrationCommit({ runtime in runtime.reconcile() }) { return }
        guard started, !sleeping else { return }
        if reconcileCalibrationTopology() {
            stateDidChange()
            return
        }
        reconcileLoadedConfiguration(configuration)
        stateDidChange()
    }

    public func accessibilityTrustDidChange(_ trusted: Bool) {
        guard started, !sleeping, calibrationSession == nil else { return }
        permissionRevoked = !trusted
        accessibilityTrusted = trusted
        if trusted, let target = availableGuardTarget, correctionIsNeeded {
            startWindowGuard(target)
        } else if !trusted {
            stopWindowGuard()
        }
        stateDidChange()
    }

    public func accessibilityPermissionLost() {
        accessibilityTrustDidChange(false)
    }

    public func handleWindowGuardEvent(_ event: AXWindowEvent) {
        guard started, !sleeping, activeGuardTarget != nil else { return }
        windowGuardOwner.handle(event)
    }

    private func prepareForSleep() {
        if deferDuringCalibrationCommit({ runtime in runtime.prepareForSleep() }) { return }
        guard started, !sleeping else { return }
        sleeping = true
        stopWindowGuard()
        stopAccessibilityTrust()
        _ = cancelCalibrationAndRestore()
        stateDidChange()
    }

    private func resumeAfterWake() {
        if deferDuringCalibrationCommit({ runtime in runtime.resumeAfterWake() }) { return }
        guard started, sleeping else { return }
        sleeping = false
        reconcileLoadedConfiguration(configuration)
        stateDidChange()
    }

    public func stop() {
        if deferDuringCalibrationCommit({ runtime in runtime.stop() }) { return }
        guard started else { return }
        stopping = true
        generation += 1
        started = false
        notifications.unsubscribe(notificationTokens)
        notificationTokens = []
        stopAccessibilityTrust()
        stopWindowGuard(force: true)
        availableGuardTarget = nil
        calibrationSession = nil
        nextCalibrationToken += 1
        calibrationOwner.stop()
        maskOwner.removeAll()
        sleeping = false
        guardTransitionInProgress = false
        stopping = false
        stateDidChange()
    }

    public func quit() {
        if deferDuringCalibrationCommit({ runtime in runtime.quit() }) { return }
        guard !terminated else { return }
        terminated = true
        stop()
        termination()
    }

    private func beginCalibration(
        target: ScreenFixConfiguration,
        on screen: ConnectedScreen,
        base: ScreenFixConfiguration?,
        needsTemporaryMasks: Bool
    ) {
        guard Self.isValidCalibrationFrames(
            screenFrame: screen.fullFrame,
            visibleFrame: screen.visibleFrame
        ) else {
            runtimeError = "Paused: calibration error: display is too small or invalid"
            return
        }
        nextCalibrationToken += 1
        let session = RuntimeCalibrationSession(
            token: nextCalibrationToken,
            lifecycleGeneration: generation,
            target: target,
            base: base,
            screenStableId: screen.display.stableId,
            screenFrame: screen.fullFrame,
            visibleFrame: screen.visibleFrame,
            pausedGuardTarget: availableGuardTarget
        )
        calibrationSession = session
        pauseWindowCorrection()

        if needsTemporaryMasks {
            do {
                try replaceMasks(for: target, on: screen)
                guard isCurrentCalibration(
                    token: session.token,
                    lifecycleGeneration: session.lifecycleGeneration
                ) else { return }
            } catch {
                if isCurrentCalibration(
                    token: session.token,
                    lifecycleGeneration: session.lifecycleGeneration
                ) {
                    calibrationSession = nil
                    restorePausedWindowCorrection(session)
                    runtimeError = "Paused: mask error: \(error)"
                }
                return
            }
        }
        do {
            try calibrationOwner.start(
                screenFrame: screen.fullFrame,
                visibleFrame: screen.visibleFrame,
                bands: target.bands,
                onSave: { [weak self] bands in
                    guard let self else { return }
                    try self.saveCalibration(
                        bands,
                        token: session.token,
                        lifecycleGeneration: session.lifecycleGeneration
                    )
                },
                onCancel: { [weak self] in
                    self?.cancelCalibration(
                        token: session.token,
                        lifecycleGeneration: session.lifecycleGeneration
                    )
                },
                commitGuard: { [weak self] in
                    guard let self,
                          self.isCurrentCalibration(
                              token: session.token,
                              lifecycleGeneration: session.lifecycleGeneration
                          ) else {
                        return false
                    }
                    guard let screen = self.liveScreen(for: session) else { return false }
                    return Self.matchesCalibrationTopology(screen, session: session)
                }
            )
            guard isCurrentCalibration(
                token: session.token,
                lifecycleGeneration: session.lifecycleGeneration
            ) else {
                calibrationOwner.stop()
                return
            }
            displayConnected = true
            runtimeError = nil
        } catch {
            if isCurrentCalibration(
                token: session.token,
                lifecycleGeneration: session.lifecycleGeneration
            ) {
                calibrationSession = nil
                calibrationOwner.stop()
                restoreBaseRuntime(session.base)
                runtimeError = "Paused: calibration error: \(error)"
            }
        }
    }

    private func saveCalibration(
        _ bands: [NormalizedRect],
        token: Int,
        lifecycleGeneration: Int
    ) throws {
        guard isCurrentCalibration(
            token: token,
            lifecycleGeneration: lifecycleGeneration
        ), let session = calibrationSession else {
            return
        }
        let desired = ScreenFixConfiguration(
            schemaVersion: session.target.schemaVersion,
            enabled: session.target.enabled,
            display: session.target.display,
            bands: bands
        )
        do {
            try ConfigValidator.validate(desired)
        } catch {
            reportConfiguration(error)
            stateDidChange()
            throw error
        }
        let screens = catalog.connectedDisplays()
        guard let screen = liveScreen(for: session, from: screens),
              Self.matchesCalibrationTopology(screen, session: session) else {
            let error = RuntimeCalibrationCommitError.displayChanged
            runtimeError = "Paused: calibration error: display changed"
            stateDidChange()
            throw error
        }
        guard !calibrationCommitInProgress else {
            throw RuntimeCalibrationCommitError.superseded
        }
        calibrationCommitInProgress = true
        defer { finishCalibrationCommit() }

        do {
            let frames = maskFrames(for: desired, on: screen)
            try maskOwner.replace(frames: frames, screenFrame: screen.fullFrame) {
                guard self.isCurrentCalibration(
                    token: token,
                    lifecycleGeneration: lifecycleGeneration
                ) else {
                    throw RuntimeCalibrationCommitError.superseded
                }
                do {
                    try self.store.save(desired)
                } catch {
                    throw RuntimeOperationError.configuration(error)
                }
                guard self.isCurrentCalibration(
                    token: token,
                    lifecycleGeneration: lifecycleGeneration
                ) else {
                    throw RuntimeCalibrationCommitError.superseded
                }
            }
        } catch RuntimeOperationError.configuration(let error) {
            if isCurrentCalibration(
                token: token,
                lifecycleGeneration: lifecycleGeneration
            ) {
                reportConfiguration(error)
                stateDidChange()
            }
            throw error
        } catch {
            if isCurrentCalibration(
                token: token,
                lifecycleGeneration: lifecycleGeneration
            ) {
                runtimeError = "Paused: mask error: \(error)"
                stateDidChange()
            }
            throw error
        }

        guard isCurrentCalibration(
            token: token,
            lifecycleGeneration: lifecycleGeneration
        ) else { return }
        configuration = desired
        displayConnected = true
        calibrationSession = nil
        runtimeError = nil
        if !desired.enabled {
            availableGuardTarget = nil
            stopAccessibilityTrust()
            maskOwner.removeAll()
        } else if let target = windowGuardTarget(for: desired, on: screen, screens: screens) {
            reconcileWindowCorrection(target)
        }
        stateDidChange()
    }

    private func deferDuringCalibrationCommit(
        _ mutation: @escaping (RuntimeController) -> Void
    ) -> Bool {
        guard calibrationCommitInProgress else { return false }
        deferredRuntimeMutations.append { [weak self] in
            guard let self else { return }
            mutation(self)
        }
        return true
    }

    private func finishCalibrationCommit() {
        calibrationCommitInProgress = false
        let mutations = deferredRuntimeMutations
        deferredRuntimeMutations.removeAll()
        for mutation in mutations {
            mutation()
        }
    }

    private func cancelCalibration(token: Int, lifecycleGeneration: Int) {
        guard isCurrentCalibration(
            token: token,
            lifecycleGeneration: lifecycleGeneration
        ), let session = calibrationSession else {
            return
        }
        calibrationSession = nil
        nextCalibrationToken += 1
        let invalidationToken = nextCalibrationToken
        calibrationOwner.stop()
        guard started, calibrationSession == nil, nextCalibrationToken == invalidationToken else {
            return
        }
        restoreBaseRuntime(session.base)
        stateDidChange()
    }

    @discardableResult
    private func cancelCalibrationAndRestore() -> Bool {
        guard let session = calibrationSession else { return true }
        calibrationSession = nil
        nextCalibrationToken += 1
        let invalidationToken = nextCalibrationToken
        calibrationOwner.stop()
        guard started, calibrationSession == nil, nextCalibrationToken == invalidationToken else {
            return false
        }
        restoreBaseRuntime(session.base)
        return true
    }

    private func reconcileCalibrationTopology() -> Bool {
        guard let session = calibrationSession else { return false }
        guard let screen = liveScreen(for: session),
              Self.isValidCalibrationFrames(
                  screenFrame: screen.fullFrame,
                  visibleFrame: screen.visibleFrame
              ) else {
            _ = cancelCalibrationAndRestore()
            return true
        }
        if Self.matchesCalibrationTopology(screen, session: session) {
            displayConnected = true
            runtimeError = nil
            return true
        }
        _ = cancelCalibrationAndRestore()
        return true
    }

    private func restoreBaseRuntime(_ base: ScreenFixConfiguration?) {
        configuration = base
        guard let base else {
            retireWindowCorrection()
            maskOwner.removeAll()
            displayConnected = false
            runtimeError = nil
            return
        }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: base.display, from: screens) else {
            retireWindowCorrection()
            maskOwner.removeAll()
            displayConnected = false
            runtimeError = nil
            return
        }
        if base.enabled {
            do {
                try replaceMasks(for: base, on: screen)
                displayConnected = true
                runtimeError = nil
                if let target = windowGuardTarget(for: base, on: screen, screens: screens) {
                    reconcileWindowCorrection(target)
                }
            } catch {
                retireWindowCorrection()
                maskOwner.removeAll()
                displayConnected = true
                runtimeError = "Paused: mask error: \(error)"
            }
        } else {
            retireWindowCorrection()
            maskOwner.removeAll()
            displayConnected = true
            runtimeError = nil
        }
    }

    private func isCurrentCalibration(token: Int, lifecycleGeneration: Int) -> Bool {
        started && generation == lifecycleGeneration
            && calibrationSession?.token == token
            && calibrationSession?.lifecycleGeneration == lifecycleGeneration
    }

    private func liveScreen(for session: RuntimeCalibrationSession) -> ConnectedScreen? {
        liveScreen(for: session, from: catalog.connectedDisplays())
    }

    private func liveScreen(
        for session: RuntimeCalibrationSession,
        from screens: [ConnectedScreen]
    ) -> ConnectedScreen? {
        if let screenStableId = session.screenStableId {
            return screens.first { screen in
                screen.display.stableId?.caseInsensitiveCompare(screenStableId) == .orderedSame
            }
        }
        return selectedScreen(for: session.target.display, from: screens)
    }

    private func maskFrames(
        for configuration: ScreenFixConfiguration,
        on screen: ConnectedScreen
    ) -> [RectD] {
        MaskGeometry.localFrames(
            bands: configuration.bands,
            displayWidth: Double(screen.fullFrame.width),
            displayHeight: Double(screen.fullFrame.height)
        )
    }

    private func replaceMasks(
        for configuration: ScreenFixConfiguration,
        on screen: ConnectedScreen
    ) throws {
        try maskOwner.replace(
            frames: maskFrames(for: configuration, on: screen),
            screenFrame: screen.fullFrame,
            beforeRetire: {}
        )
    }

    private var correctionIsNeeded: Bool {
        started
            && !sleeping
            && !guardTransitionInProgress
            && calibrationSession == nil
            && configuration?.enabled == true
            && displayConnected
    }

    private func windowGuardTarget(
        for configuration: ScreenFixConfiguration,
        on screen: ConnectedScreen,
        screens: [ConnectedScreen]
    ) -> WindowGuardTarget? {
        guard let selectedDisplayID = screen.display.stableId else { return nil }
        let bounds = TopLeftDisplayBounds(
            x: screen.topLeftFullFrame.x,
            y: screen.topLeftFullFrame.y,
            width: screen.topLeftFullFrame.width,
            height: screen.topLeftFullFrame.height
        )
        return WindowGuardTarget(
            selectedDisplayID: selectedDisplayID,
            workArea: screen.topLeftVisibleFrame,
            masks: MaskGeometry.absoluteTopLeftFrames(bands: configuration.bands, in: bounds),
            displays: screens.map { candidate in
                DisplayFrame(stableID: candidate.display.stableId, frame: candidate.topLeftFullFrame)
            }
        )
    }

    private func reconcileWindowCorrection(_ target: WindowGuardTarget) {
        availableGuardTarget = target
        guard correctionIsNeeded else { return }
        let trusted = accessibilityTrustOwner.reconcile(needsPermission: true)
        accessibilityTrusted = trusted && !permissionRevoked
        if accessibilityTrusted {
            startWindowGuard(target)
        } else {
            stopWindowGuard()
        }
    }

    private func restoreAvailableWindowGuard() {
        guard let target = availableGuardTarget, correctionIsNeeded else { return }
        reconcileWindowCorrection(target)
    }

    private func restorePausedWindowCorrection(_ session: RuntimeCalibrationSession) {
        guard let target = session.pausedGuardTarget else { return }
        availableGuardTarget = target
        restoreAvailableWindowGuard()
    }

    private func retireWindowCorrection() {
        stopWindowGuard()
        availableGuardTarget = nil
        stopAccessibilityTrust()
    }

    private func pauseWindowCorrection() {
        stopWindowGuard()
        availableGuardTarget = nil
        stopAccessibilityTrust()
    }

    private func stopAccessibilityTrust() {
        accessibilityTrustOwner.stop()
        permissionRevoked = false
    }

    private func startWindowGuard(_ target: WindowGuardTarget) {
        guard activeGuardTarget != target else { return }
        activeGuardTarget = target
        windowGuardOwner.start(target: target)
    }

    private func stopWindowGuard(force: Bool = false) {
        let hadActiveGuard = activeGuardTarget != nil
        activeGuardTarget = nil
        guard force || hadActiveGuard else { return }
        windowGuardOwner.stop()
    }

    private static func isValidCalibrationFrames(
        screenFrame: NSRect,
        visibleFrame: NSRect
    ) -> Bool {
        isFinite(screenFrame) && isFinite(visibleFrame)
            && screenFrame.width >= 260 && screenFrame.height >= 180
            && visibleFrame.width >= 260 && visibleFrame.height >= 180
            && visibleFrame.minX >= screenFrame.minX
            && visibleFrame.minY >= screenFrame.minY
            && visibleFrame.maxX <= screenFrame.maxX
            && visibleFrame.maxY <= screenFrame.maxY
    }

    private static func isFinite(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }

    private static func matchesCalibrationTopology(
        _ screen: ConnectedScreen,
        session: RuntimeCalibrationSession
    ) -> Bool {
        screen.fullFrame == session.screenFrame && screen.visibleFrame == session.visibleFrame
    }

    private func reconcileLoadedConfiguration(_ desired: ScreenFixConfiguration?) {
        guard let desired else {
            retireWindowCorrection()
            maskOwner.removeAll()
            configuration = nil
            displayConnected = false
            runtimeError = nil
            return
        }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: desired.display, from: screens) else {
            retireWindowCorrection()
            maskOwner.removeAll()
            configuration = desired
            displayConnected = false
            runtimeError = nil
            return
        }
        if !desired.enabled {
            retireWindowCorrection()
            maskOwner.removeAll()
            configuration = desired
            displayConnected = true
            runtimeError = nil
            return
        }
        replace(with: desired, on: screen, screens: screens, persist: false)
    }

    private func replace(
        with desired: ScreenFixConfiguration,
        on screen: ConnectedScreen,
        screens: [ConnectedScreen],
        persist: Bool
    ) {
        let activeGeneration = generation
        let pausedGuardTarget = activeGuardTarget
        let frames = MaskGeometry.localFrames(
            bands: desired.bands,
            displayWidth: Double(screen.fullFrame.width),
            displayHeight: Double(screen.fullFrame.height)
        )
        guardTransitionInProgress = true
        stopWindowGuard()
        do {
            try maskOwner.replace(frames: frames, screenFrame: screen.fullFrame) {
                guard self.started, self.generation == activeGeneration else {
                    throw RuntimeOperationError.superseded
                }
                guard persist else { return }
                do {
                    try self.store.save(desired)
                } catch {
                    throw RuntimeOperationError.configuration(error)
                }
                guard self.started, self.generation == activeGeneration else {
                    throw RuntimeOperationError.superseded
                }
            }
            guard started, generation == activeGeneration else {
                guardTransitionInProgress = false
                maskOwner.removeAll()
                return
            }
            guardTransitionInProgress = false
            configuration = desired
            displayConnected = true
            runtimeError = nil
            if let target = windowGuardTarget(for: desired, on: screen, screens: screens) {
                reconcileWindowCorrection(target)
            } else {
                retireWindowCorrection()
            }
        } catch RuntimeOperationError.configuration(let error) {
            guardTransitionInProgress = false
            reportConfiguration(error)
            restoreWindowGuard(pausedGuardTarget)
        } catch RuntimeOperationError.superseded {
            guardTransitionInProgress = false
            return
        } catch {
            guardTransitionInProgress = false
            runtimeError = "Paused: mask error: \(error)"
            restoreWindowGuard(pausedGuardTarget)
        }
    }

    private func restoreWindowGuard(_ target: WindowGuardTarget?) {
        guard let target, started else { return }
        availableGuardTarget = target
        restoreAvailableWindowGuard()
    }

    private func selectedScreen(
        for saved: DisplayIdentity,
        from screens: [ConnectedScreen]
    ) -> ConnectedScreen? {
        guard let selected = DisplaySelector.select(saved: saved, from: screens.map(\.display)) else {
            return nil
        }
        return screens.first(where: { $0.display == selected })
    }

    private func refreshConnection() {
        guard let configuration else {
            displayConnected = false
            return
        }
        displayConnected = selectedScreen(
            for: configuration.display,
            from: catalog.connectedDisplays()
        ) != nil
    }

    private func reportConfiguration(_ error: Error) {
        runtimeError = "Paused: config error: \(error)"
    }
}
