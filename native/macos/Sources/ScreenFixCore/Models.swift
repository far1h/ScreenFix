import Foundation

public struct NormalizedRect: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct DisplayIdentity: Codable, Equatable {
    public let stableId: String
    public let name: String
    public let width: Double
    public let height: Double
    public let vendorId: UInt32?
    public let modelId: UInt32?
    public let serialNumber: UInt32?

    public init(
        stableId: String,
        name: String,
        width: Double,
        height: Double,
        vendorId: UInt32? = nil,
        modelId: UInt32? = nil,
        serialNumber: UInt32? = nil
    ) {
        self.stableId = stableId
        self.name = name
        self.width = width
        self.height = height
        self.vendorId = vendorId
        self.modelId = modelId
        self.serialNumber = serialNumber
    }
}

public struct ScreenFixConfiguration: Codable, Equatable {
    public let schemaVersion: Int
    public let enabled: Bool
    public let display: DisplayIdentity
    public let bands: [NormalizedRect]

    public init(
        schemaVersion: Int,
        enabled: Bool,
        display: DisplayIdentity,
        bands: [NormalizedRect]
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.display = display
        self.bands = bands
    }
}

public struct RectD: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var right: Double { x + width }
    public var bottom: Double { y + height }

    public func intersects(_ other: RectD) -> Bool {
        x < other.right && other.x < right && y < other.bottom && other.y < bottom
    }
}

public struct TopLeftDisplayBounds: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MenuState: Equatable {
    public let status: String?
    public let enabledActionTitle: String
    public let enabledActionEnabled: Bool
    public let enabledActionChecked: Bool
    public let calibrateEnabled: Bool
    public let calibrating: Bool
    public let resetEnabled: Bool
    public let selectMonitorEnabled: Bool
    public let reloadEnabled: Bool
    public let quitEnabled: Bool

    public static func make(
        configuration: ScreenFixConfiguration?,
        displayConnected: Bool,
        accessibilityTrusted: Bool = true,
        calibrating: Bool = false,
        runtimeError: String?
    ) -> MenuState {
        let enabled = configuration?.enabled ?? false
        let ordinaryStatus: String?
        if configuration == nil {
            ordinaryStatus = "Paused: select a monitor"
        } else if !displayConnected {
            ordinaryStatus = "Paused: saved display is disconnected"
        } else if enabled && !calibrating && !accessibilityTrusted {
            ordinaryStatus = "Window correction paused: Allow Accessibility in System Settings"
        } else {
            ordinaryStatus = nil
        }
        return MenuState(
            status: runtimeError ?? ordinaryStatus,
            enabledActionTitle: enabled ? "Disable" : "Enable",
            enabledActionEnabled: configuration != nil,
            enabledActionChecked: enabled,
            calibrateEnabled: configuration != nil && displayConnected,
            calibrating: calibrating,
            resetEnabled: configuration != nil && displayConnected,
            selectMonitorEnabled: true,
            reloadEnabled: true,
            quitEnabled: true
        )
    }
}

public struct MenuItemModel: Equatable {
    public let identifier: String
    public let title: String
    public let isEnabled: Bool
    public let isChecked: Bool
    public let stableId: String?
    public let children: [MenuItemModel]

    public init(
        identifier: String,
        title: String,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        stableId: String? = nil,
        children: [MenuItemModel] = []
    ) {
        self.identifier = identifier
        self.title = title
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.stableId = stableId
        self.children = children
    }
}

public final class MenuModelBuilder {
    private let displayProvider: () -> [ConnectedDisplay]

    public init(displayProvider: @escaping () -> [ConnectedDisplay]) {
        self.displayProvider = displayProvider
    }

    public func build(state: MenuState, savedStableId: String?) -> [MenuItemModel] {
        var items: [MenuItemModel] = []
        if let status = state.status {
            items.append(MenuItemModel(identifier: "paused-status", title: status, isEnabled: false))
        }
        items.append(MenuItemModel(
            identifier: "enabled-action",
            title: state.enabledActionTitle,
            isEnabled: state.enabledActionEnabled,
            isChecked: state.enabledActionChecked
        ))
        items.append(MenuItemModel(
            identifier: "calibrate",
            title: "Calibrate",
            isEnabled: state.calibrateEnabled,
            isChecked: state.calibrating
        ))
        let displays = displayProvider()
        let children = displays.enumerated().map { index, display in
            let identifiable = display.stableId != nil
            let isCurrent = display.stableId.map { candidate in
                savedStableId?.caseInsensitiveCompare(candidate) == .orderedSame
            } ?? false
            return MenuItemModel(
                identifier: "display-\(index)",
                title: identifiable ? display.name : "\(display.name) (identity unavailable)",
                isEnabled: identifiable,
                isChecked: isCurrent,
                stableId: display.stableId
            )
        }
        items.append(MenuItemModel(
            identifier: "select-monitor",
            title: "Select Monitor",
            isEnabled: state.selectMonitorEnabled,
            children: children
        ))
        items.append(MenuItemModel(
            identifier: "reset-defaults",
            title: "Reset to Defaults",
            isEnabled: state.resetEnabled
        ))
        items.append(MenuItemModel(identifier: "reload", title: "Reload", isEnabled: state.reloadEnabled))
        items.append(MenuItemModel(identifier: "separator", title: "", isEnabled: false))
        items.append(MenuItemModel(identifier: "quit", title: "Quit", isEnabled: state.quitEnabled))
        return items
    }
}
