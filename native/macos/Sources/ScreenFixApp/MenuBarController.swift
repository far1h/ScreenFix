import AppKit
import ScreenFixCore

final class MenuBarController: NSObject, NSMenuDelegate {
    private let runtime: RuntimeController
    private let catalog: DisplayCatalog
    private var statusItem: NSStatusItem?
    private lazy var modelBuilder = MenuModelBuilder { [weak self] in
        self?.catalog.connectedDisplays().map(\.display) ?? []
    }

    init(runtime: RuntimeController, catalog: DisplayCatalog) {
        self.runtime = runtime
        self.catalog = catalog
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "ScreenFixMenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
        } else {
            item.button?.title = "SF"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refresh()
    }

    func refresh() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        let snapshot = runtime.snapshot
        let models = modelBuilder.build(
            state: snapshot.menuState,
            savedStableId: snapshot.configuration?.display.stableId
        )
        for model in models {
            menu.addItem(makeItem(from: model))
        }
    }

    func stop() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func makeItem(from model: MenuItemModel) -> NSMenuItem {
        if model.identifier == "separator" {
            return .separator()
        }
        let item = NSMenuItem(title: model.title, action: action(for: model.identifier), keyEquivalent: "")
        item.target = self
        item.isEnabled = model.isEnabled
        item.state = model.isChecked ? .on : .off
        item.identifier = NSUserInterfaceItemIdentifier(model.identifier)
        item.representedObject = model.stableId
        if !model.children.isEmpty {
            let submenu = NSMenu(title: model.title)
            for child in model.children {
                submenu.addItem(makeItem(from: child))
            }
            item.submenu = submenu
        }
        return item
    }

    private func action(for identifier: String) -> Selector? {
        if identifier == "enabled-action" { return #selector(toggleEnabled) }
        if identifier == "reset-defaults" { return #selector(resetDefaults) }
        if identifier == "reload" { return #selector(reload) }
        if identifier == "quit" { return #selector(quit) }
        if identifier.hasPrefix("display-") { return #selector(selectDisplay(_:)) }
        return nil
    }

    @objc private func toggleEnabled() {
        let enabled = runtime.snapshot.configuration?.enabled ?? false
        runtime.setEnabled(!enabled)
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let stableId = sender.representedObject as? String else { return }
        runtime.selectDisplay(stableId: stableId)
    }

    @objc private func resetDefaults() {
        runtime.resetToDefaults()
    }

    @objc private func reload() {
        runtime.reload()
    }

    @objc private func quit() {
        runtime.quit()
    }
}
