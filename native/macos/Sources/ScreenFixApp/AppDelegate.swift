import AppKit
import ScreenFixCore

public final class RuntimeWindowGuardEventRelay {
    public weak var runtime: RuntimeController?

    public init() {}

    public func handle(_ event: AXWindowEvent) {
        runtime?.handleWindowGuardEvent(event)
    }

    public func accessibilityPermissionLost() {
        runtime?.accessibilityPermissionLost()
    }

    public func accessibilityTrustDidChange(_ trusted: Bool) {
        runtime?.accessibilityTrustDidChange(trusted)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: RuntimeController?
    private var menuBar: MenuBarController?
    private var eventRelay: RuntimeWindowGuardEventRelay?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileURL: URL
        do {
            fileURL = try ConfigStore.defaultURL()
        } catch {
            NSApplication.shared.terminate(nil)
            return
        }

        let catalog = DisplayCatalog()
        let axClient = AXClient()
        let relay = RuntimeWindowGuardEventRelay()
        let observerRegistry = AXObserverRegistry(
            client: axClient,
            eventSink: { [weak relay] event in relay?.handle(event) }
        )
        let windowAccess = SystemWindowGuardAccess(client: axClient)
        let windowGuard = WindowGuardController(
            source: observerRegistry,
            access: windowAccess,
            permissionLost: { [weak relay] in relay?.accessibilityPermissionLost() }
        )
        let accessibilityTrust = AccessibilityTrustController(
            stateDidChange: { [weak relay] trusted in
                relay?.accessibilityTrustDidChange(trusted)
            }
        )
        let runtime = RuntimeController(
            store: ConfigStore(fileURL: fileURL),
            catalog: catalog,
            maskOwner: MaskPanelController(),
            calibrationOwner: CalibrationPanelController(),
            accessibilityTrustOwner: accessibilityTrust,
            windowGuardOwner: windowGuard,
            notifications: SystemRuntimeNotifications(),
            termination: { NSApplication.shared.terminate(nil) },
            stateDidChange: { [weak self] in self?.menuBar?.refresh() }
        )
        relay.runtime = runtime
        eventRelay = relay
        self.runtime = runtime
        menuBar = MenuBarController(runtime: runtime, catalog: catalog)
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        menuBar?.stop()
        menuBar = nil
        eventRelay?.runtime = nil
        eventRelay = nil
        runtime = nil
    }
}
