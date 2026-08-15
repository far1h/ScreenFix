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
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void,
        commitGuard: () throws -> Bool
    ) throws {
        let prepared = try prepare(
            screenFrame: screenFrame,
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

public protocol RuntimeNotifications: AnyObject {
    func subscribe(
        displayChanged: @escaping () -> Void,
        woke: @escaping () -> Void
    ) -> [AnyObject]
    func unsubscribe(_ tokens: [AnyObject])
}

public final class SystemRuntimeNotifications: RuntimeNotifications {
    public init() {}

    public func subscribe(
        displayChanged: @escaping () -> Void,
        woke: @escaping () -> Void
    ) -> [AnyObject] {
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in displayChanged() }
        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in woke() }
        return [screenToken as AnyObject, wakeToken as AnyObject]
    }

    public func unsubscribe(_ tokens: [AnyObject]) {
        guard tokens.count == 2 else { return }
        NotificationCenter.default.removeObserver(tokens[0])
        NSWorkspace.shared.notificationCenter.removeObserver(tokens[1])
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
}

public final class RuntimeController {
    private let store: RuntimeConfigurationStore
    private let catalog: RuntimeDisplayCatalog
    private let maskOwner: RuntimeMaskOwner
    private let calibrationOwner: RuntimeCalibrationOwner
    private let notifications: RuntimeNotifications
    private let termination: () -> Void
    private let stateDidChange: () -> Void

    private var configuration: ScreenFixConfiguration?
    private var runtimeError: String?
    private var displayConnected = false
    private var notificationTokens: [AnyObject] = []
    private var calibrationSession: RuntimeCalibrationSession?
    private var nextCalibrationToken = 0
    private var generation = 0
    private var started = false
    private var stopping = false
    private var terminated = false

    public init(
        store: RuntimeConfigurationStore,
        catalog: RuntimeDisplayCatalog,
        maskOwner: RuntimeMaskOwner,
        calibrationOwner: RuntimeCalibrationOwner = CalibrationPanelController(),
        notifications: RuntimeNotifications,
        termination: @escaping () -> Void,
        stateDidChange: @escaping () -> Void
    ) {
        self.store = store
        self.catalog = catalog
        self.maskOwner = maskOwner
        self.calibrationOwner = calibrationOwner
        self.notifications = notifications
        self.termination = termination
        self.stateDidChange = stateDidChange
    }

    public var snapshot: RuntimeSnapshot {
        RuntimeSnapshot(
            configuration: configuration,
            displayConnected: displayConnected,
            calibrating: calibrationSession != nil,
            menuState: MenuState.make(
                configuration: configuration,
                displayConnected: displayConnected,
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
            woke: { [weak self] in
                guard let self, self.started, self.generation == activeGeneration else { return }
                self.reconcile()
            }
        )
        do {
            configuration = try store.load()
            reconcileLoadedConfiguration(configuration)
        } catch {
            configuration = nil
            displayConnected = false
            maskOwner.removeAll()
            reportConfiguration(error)
        }
        stateDidChange()
    }

    public func setEnabled(_ enabled: Bool) {
        guard started else { return }
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
            do {
                try store.save(desired)
                guard started, generation == activeGeneration else { return }
                configuration = desired
                maskOwner.removeAll()
                refreshConnection()
                runtimeError = nil
            } catch {
                guard started, generation == activeGeneration else { return }
                reportConfiguration(error)
            }
            stateDidChange()
            return
        }

        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: desired.display, from: screens) else {
            do {
                try store.save(desired)
                configuration = desired
                displayConnected = false
                runtimeError = nil
            } catch {
                reportConfiguration(error)
            }
            stateDidChange()
            return
        }

        replace(with: desired, on: screen, persist: true)
        stateDidChange()
    }

    public func selectDisplay(stableId: String) {
        guard started else { return }
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
        guard started else { return }
        if calibrationSession != nil {
            if cancelCalibrationAndRestore() { stateDidChange() }
            return
        }
        guard let configuration else { return }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: configuration.display, from: screens) else {
            displayConnected = false
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
        guard started else { return }
        guard cancelCalibrationAndRestore() else { return }
        guard let current = configuration else {
            stateDidChange()
            return
        }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: current.display, from: screens) else {
            displayConnected = false
            maskOwner.removeAll()
            runtimeError = nil
            stateDidChange()
            return
        }
        let desired = DefaultConfiguration.make(for: current.display, enabled: current.enabled)
        if desired.enabled {
            replace(with: desired, on: screen, persist: true)
        } else {
            do {
                try store.save(desired)
                configuration = desired
                displayConnected = true
                runtimeError = nil
            } catch {
                reportConfiguration(error)
            }
        }
        stateDidChange()
    }

    public func reload() {
        guard started else { return }
        guard cancelCalibrationAndRestore() else { return }
        do {
            let loaded = try store.load()
            reconcileLoadedConfiguration(loaded)
        } catch {
            reportConfiguration(error)
        }
        stateDidChange()
    }

    public func reconcile() {
        guard started else { return }
        if reconcileCalibrationTopology() {
            stateDidChange()
            return
        }
        reconcileLoadedConfiguration(configuration)
        stateDidChange()
    }

    public func stop() {
        guard started else { return }
        stopping = true
        generation += 1
        started = false
        notifications.unsubscribe(notificationTokens)
        notificationTokens = []
        calibrationSession = nil
        nextCalibrationToken += 1
        calibrationOwner.stop()
        maskOwner.removeAll()
        stopping = false
        stateDidChange()
    }

    public func quit() {
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
        guard Self.isValidCalibrationFrame(screen.fullFrame) else {
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
            screenFrame: screen.fullFrame
        )
        calibrationSession = session

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
                    restoreBaseRuntime(base)
                    runtimeError = "Paused: mask error: \(error)"
                }
                return
            }
        }
        do {
            try calibrationOwner.start(
                screenFrame: screen.fullFrame,
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
                    return self.liveScreen(for: session)?.fullFrame == session.screenFrame
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
        guard let screen = liveScreen(for: session), screen.fullFrame == session.screenFrame else {
            let error = RuntimeCalibrationCommitError.displayChanged
            runtimeError = "Paused: calibration error: display changed"
            stateDidChange()
            throw error
        }

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
            maskOwner.removeAll()
        }
        stateDidChange()
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
              Self.isValidCalibrationFrame(screen.fullFrame) else {
            _ = cancelCalibrationAndRestore()
            return true
        }
        if screen.fullFrame == session.screenFrame {
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
            maskOwner.removeAll()
            displayConnected = false
            runtimeError = nil
            return
        }
        guard let screen = selectedScreen(for: base.display, from: catalog.connectedDisplays()) else {
            maskOwner.removeAll()
            displayConnected = false
            runtimeError = nil
            return
        }
        if base.enabled {
            replace(with: base, on: screen, persist: false)
        } else {
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
        let screens = catalog.connectedDisplays()
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

    private static func isValidCalibrationFrame(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width >= 260 && frame.height >= 180
    }

    private func reconcileLoadedConfiguration(_ desired: ScreenFixConfiguration?) {
        guard let desired else {
            maskOwner.removeAll()
            configuration = nil
            displayConnected = false
            runtimeError = nil
            return
        }
        let screens = catalog.connectedDisplays()
        guard let screen = selectedScreen(for: desired.display, from: screens) else {
            maskOwner.removeAll()
            configuration = desired
            displayConnected = false
            runtimeError = nil
            return
        }
        if !desired.enabled {
            maskOwner.removeAll()
            configuration = desired
            displayConnected = true
            runtimeError = nil
            return
        }
        replace(with: desired, on: screen, persist: false)
    }

    private func replace(
        with desired: ScreenFixConfiguration,
        on screen: ConnectedScreen,
        persist: Bool
    ) {
        let frames = MaskGeometry.localFrames(
            bands: desired.bands,
            displayWidth: Double(screen.fullFrame.width),
            displayHeight: Double(screen.fullFrame.height)
        )
        do {
            try maskOwner.replace(frames: frames, screenFrame: screen.fullFrame) {
                guard persist else { return }
                do {
                    try self.store.save(desired)
                } catch {
                    throw RuntimeOperationError.configuration(error)
                }
            }
            configuration = desired
            displayConnected = true
            runtimeError = nil
        } catch RuntimeOperationError.configuration(let error) {
            reportConfiguration(error)
        } catch {
            runtimeError = "Paused: mask error: \(error)"
        }
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
