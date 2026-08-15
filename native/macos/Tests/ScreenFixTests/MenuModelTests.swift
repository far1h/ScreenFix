import AppKit
import ScreenFixApp
import ScreenFixCore

private func menuConnected(_ id: String?, name: String) -> ConnectedDisplay {
    ConnectedDisplay(stableId: id, name: name, width: 100, height: 100)
}

let menuModelTests = [
    TestCase(name: "MenuModel status icon uses a proportionate visible size") {
        try expectEqual(StatusIconMetrics.imageSize, NSSize(width: 24, height: 15))
    },
    TestCase(name: "MenuModel hides unfinished features and keeps exact app order") {
        let state = MenuState.make(configuration: nil, displayConnected: false, runtimeError: nil)
        let builder = MenuModelBuilder(displayProvider: { [] })
        let model = builder.build(state: state, savedStableId: nil)

        try expectEqual(model.map(\.identifier), [
            "paused-status", "enabled-action", "select-monitor", "reset-defaults",
            "reload", "separator", "quit",
        ])
        try expect(!model.contains(where: { $0.identifier.contains("phase2") }))
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
