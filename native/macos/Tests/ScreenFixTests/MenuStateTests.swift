import ScreenFixCore

private let menuDisplay = DisplayIdentity(
    stableId: "menu-uuid",
    name: "Ultrawide",
    width: 3440,
    height: 1440
)

private func menuConfig(enabled: Bool) -> ScreenFixConfiguration {
    DefaultConfiguration.make(for: menuDisplay, enabled: enabled)
}

let menuStateTests = [
    TestCase(name: "MenuState without config asks for monitor selection") {
        let state = MenuState.make(
            configuration: nil,
            displayConnected: false,
            calibrating: false,
            runtimeError: nil
        )
        try expectEqual(state.enabledActionTitle, "Enable")
        try expect(!state.enabledActionEnabled)
        try expect(!state.enabledActionChecked)
        try expect(!state.resetEnabled)
        try expect(!state.calibrateEnabled)
        try expect(!state.calibrating)
        try expectEqual(state.status, "Paused: select a monitor")
    },
    TestCase(name: "MenuState connected enabled config can disable and reset") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: true),
            displayConnected: true,
            calibrating: true,
            runtimeError: nil
        )
        try expectEqual(state.enabledActionTitle, "Disable")
        try expect(state.enabledActionEnabled)
        try expect(state.enabledActionChecked)
        try expect(state.resetEnabled)
        try expect(state.calibrateEnabled)
        try expect(state.calibrating)
        try expectEqual(state.status, nil)
    },
    TestCase(name: "MenuState connected disabled config can enable") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: false),
            displayConnected: true,
            calibrating: false,
            runtimeError: nil
        )
        try expectEqual(state.enabledActionTitle, "Enable")
        try expect(state.enabledActionEnabled)
        try expect(!state.enabledActionChecked)
        try expect(state.resetEnabled)
        try expect(state.calibrateEnabled)
    },
    TestCase(name: "MenuState disconnected enabled config remains explicitly enabled") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: true),
            displayConnected: false,
            calibrating: false,
            runtimeError: nil
        )
        try expectEqual(state.enabledActionTitle, "Disable")
        try expect(state.enabledActionEnabled)
        try expect(state.enabledActionChecked)
        try expect(!state.resetEnabled)
        try expect(!state.calibrateEnabled)
        try expectEqual(state.status, "Paused: saved display is disconnected")
    },
    TestCase(name: "MenuState disconnected disabled config reports pause") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: false),
            displayConnected: false,
            calibrating: false,
            runtimeError: nil
        )
        try expectEqual(state.enabledActionTitle, "Enable")
        try expect(state.enabledActionEnabled)
        try expect(!state.enabledActionChecked)
        try expect(!state.resetEnabled)
        try expectEqual(state.status, "Paused: saved display is disconnected")
    },
    TestCase(name: "MenuState runtime config error overrides ordinary status") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: true),
            displayConnected: true,
            calibrating: false,
            runtimeError: "Paused: config error: malformed JSON"
        )
        try expect(state.status?.hasPrefix("Paused: config error:") == true)
    },
    TestCase(name: "MenuState untrusted correction shows one actionable status") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: true),
            displayConnected: true,
            accessibilityTrusted: false,
            calibrating: false,
            runtimeError: nil
        )

        try expectEqual(
            state.status,
            "Window correction paused: Allow Accessibility in System Settings"
        )
        try expectEqual(state.enabledActionTitle, "Disable")
        try expect(state.enabledActionEnabled)
        try expect(state.enabledActionChecked)
        try expect(state.calibrateEnabled)
        try expect(state.selectMonitorEnabled)
        try expect(state.resetEnabled)
        try expect(state.reloadEnabled)
        try expect(state.quitEnabled)
    },
    TestCase(name: "MenuState runtime errors outrank Accessibility status") {
        for error in [
            "Paused: config error: invalid",
            "Paused: mask error: failed",
        ] {
            let state = MenuState.make(
                configuration: menuConfig(enabled: true),
                displayConnected: true,
                accessibilityTrusted: false,
                calibrating: false,
                runtimeError: error
            )
            try expectEqual(state.status, error)
        }
    },
    TestCase(name: "MenuState permanent controls stay enabled") {
        let state = MenuState.make(
            configuration: menuConfig(enabled: true),
            displayConnected: true,
            calibrating: false,
            runtimeError: nil
        )
        try expect(state.selectMonitorEnabled)
        try expect(state.reloadEnabled)
        try expect(state.quitEnabled)
    },
]
