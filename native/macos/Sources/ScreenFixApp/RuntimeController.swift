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
    public let menuState: MenuState

    public init(
        configuration: ScreenFixConfiguration?,
        displayConnected: Bool,
        menuState: MenuState
    ) {
        self.configuration = configuration
        self.displayConnected = displayConnected
        self.menuState = menuState
    }
}

private enum RuntimeOperationError: Error {
    case configuration(Error)
    case mask(Error)
}

public final class RuntimeController {
    private let store: RuntimeConfigurationStore
    private let catalog: RuntimeDisplayCatalog
    private let maskOwner: RuntimeMaskOwner
    private let notifications: RuntimeNotifications
    private let termination: () -> Void
    private let stateDidChange: () -> Void

    private var configuration: ScreenFixConfiguration?
    private var runtimeError: String?
    private var displayConnected = false
    private var notificationTokens: [AnyObject] = []
    private var generation = 0
    private var started = false
    private var terminated = false

    public init(
        store: RuntimeConfigurationStore,
        catalog: RuntimeDisplayCatalog,
        maskOwner: RuntimeMaskOwner,
        notifications: RuntimeNotifications,
        termination: @escaping () -> Void,
        stateDidChange: @escaping () -> Void
    ) {
        self.store = store
        self.catalog = catalog
        self.maskOwner = maskOwner
        self.notifications = notifications
        self.termination = termination
        self.stateDidChange = stateDidChange
    }

    public var snapshot: RuntimeSnapshot {
        RuntimeSnapshot(
            configuration: configuration,
            displayConnected: displayConnected,
            menuState: MenuState.make(
                configuration: configuration,
                displayConnected: displayConnected,
                runtimeError: runtimeError
            )
        )
    }

    public func start() {
        guard !started else { return }
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
        guard started, let current = configuration, current.enabled != enabled else { return }
        let desired = ScreenFixConfiguration(
            schemaVersion: current.schemaVersion,
            enabled: enabled,
            display: current.display,
            bands: current.bands
        )

        if !enabled {
            maskOwner.removeAll()
            do {
                try store.save(desired)
                configuration = desired
                refreshConnection()
                runtimeError = nil
            } catch {
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
        replace(with: desired, on: screen, persist: true)
        stateDidChange()
    }

    public func resetToDefaults() {
        guard started, let current = configuration else { return }
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
        reconcileLoadedConfiguration(configuration)
        stateDidChange()
    }

    public func stop() {
        guard started else { return }
        generation += 1
        notifications.unsubscribe(notificationTokens)
        notificationTokens = []
        maskOwner.removeAll()
        started = false
        stateDidChange()
    }

    public func quit() {
        guard !terminated else { return }
        terminated = true
        stop()
        termination()
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
