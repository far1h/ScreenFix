import ScreenFixCore

private func menuConnected(_ id: String?, name: String) -> ConnectedDisplay {
    ConnectedDisplay(stableId: id, name: name, width: 100, height: 100)
}

let menuModelTests = [
    TestCase(name: "MenuModel has exact Phase 1 order and disabled unavailable rows") {
        let state = MenuState.make(configuration: nil, displayConnected: false, runtimeError: nil)
        let builder = MenuModelBuilder(displayProvider: { [] })
        let model = builder.build(state: state, savedStableId: nil)

        try expectEqual(model.map(\.identifier), [
            "paused-status", "window-guard-phase2", "enabled-action", "calibrate-phase2",
            "select-monitor", "reset-defaults", "reload", "separator", "quit",
        ])
        try expect(model.first(where: { $0.identifier == "calibrate-phase2" })?.isEnabled == false)
        try expect(model.first(where: { $0.identifier == "window-guard-phase2" })?.isEnabled == false)
    },
    TestCase(name: "MenuModel refreshes displays on every build") {
        var calls = 0
        let builder = MenuModelBuilder(displayProvider: {
            calls += 1
            return calls == 1
                ? [menuConnected("a", name: "Display A")]
                : [menuConnected("b", name: "Display B")]
        })
        let state = MenuState.make(configuration: nil, displayConnected: false, runtimeError: nil)

        let first = builder.build(state: state, savedStableId: nil)
        let second = builder.build(state: state, savedStableId: nil)
        let firstTitles = first.first(where: { $0.identifier == "select-monitor" })?.children.map(\.title)
        let secondTitles = second.first(where: { $0.identifier == "select-monitor" })?.children.map(\.title)
        try expectEqual(firstTitles, ["Display A"])
        try expectEqual(secondTitles, ["Display B"])
        try expectEqual(calls, 2)
    },
    TestCase(name: "MenuModel disables unidentified displays and checks UUID only") {
        let builder = MenuModelBuilder(displayProvider: {
            [menuConnected(nil, name: "Unknown"), menuConnected("CURRENT", name: "Current")]
        })
        let state = MenuState.make(configuration: nil, displayConnected: false, runtimeError: nil)
        let children = builder.build(state: state, savedStableId: "current")
            .first(where: { $0.identifier == "select-monitor" })?.children ?? []

        try expectEqual(children[0].title, "Unknown (identity unavailable)")
        try expect(!children[0].isEnabled)
        try expect(!children[0].isChecked)
        try expect(children[1].isEnabled)
        try expect(children[1].isChecked)
    },
]
