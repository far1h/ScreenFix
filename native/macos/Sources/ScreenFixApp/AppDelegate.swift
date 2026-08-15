import AppKit
import ScreenFixCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: RuntimeController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileURL: URL
        do {
            fileURL = try ConfigStore.defaultURL()
        } catch {
            NSApplication.shared.terminate(nil)
            return
        }

        let catalog = DisplayCatalog()
        let runtime = RuntimeController(
            store: ConfigStore(fileURL: fileURL),
            catalog: catalog,
            maskOwner: MaskPanelController(),
            notifications: SystemRuntimeNotifications(),
            termination: { NSApplication.shared.terminate(nil) },
            stateDidChange: { [weak self] in self?.menuBar?.refresh() }
        )
        self.runtime = runtime
        menuBar = MenuBarController(runtime: runtime, catalog: catalog)
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        menuBar?.stop()
        menuBar = nil
        runtime = nil
    }
}
