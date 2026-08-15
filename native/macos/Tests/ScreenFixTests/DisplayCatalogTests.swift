import AppKit
import CoreGraphics
import ScreenFixApp
import ScreenFixCore

private func snapshot(
    id: CGDirectDisplayID,
    name: String,
    frame: NSRect,
    visibleFrame: NSRect? = nil,
    token: AnyObject = NSObject()
) -> ScreenSnapshot {
    ScreenSnapshot(
        directDisplayId: id,
        name: name,
        fullFrame: frame,
        visibleFrame: visibleFrame ?? frame,
        nativeScreen: token
    )
}

let displayCatalogTests = [
    TestCase(name: "DisplayCatalog reads a fresh screen snapshot every time") {
        var calls = 0
        let catalog = DisplayCatalog(
            screenProvider: {
                calls += 1
                return calls == 1
                    ? [snapshot(id: 1, name: "A", frame: NSRect(x: 0, y: 0, width: 100, height: 100))]
                    : [snapshot(id: 2, name: "B", frame: NSRect(x: 100, y: 0, width: 200, height: 100))]
            },
            uuidProvider: { "UUID-\($0)" },
            diagnosticProvider: { _ in DisplayDiagnostics() },
            displayBoundsProvider: { id in
                CGRect(x: id == 1 ? 0 : 100, y: 0, width: id == 1 ? 100 : 200, height: 100)
            }
        )

        try expectEqual(catalog.connectedDisplays().map(\.display.name), ["A"])
        try expectEqual(catalog.connectedDisplays().map(\.display.name), ["B"])
        try expectEqual(calls, 2)
    },
    TestCase(name: "DisplayCatalog normalizes UUID and preserves full negative frame") {
        let token = NSObject()
        let catalog = DisplayCatalog(
            screenProvider: {
                [snapshot(
                    id: 7,
                    name: "Ultrawide",
                    frame: NSRect(x: -3440, y: -900, width: 3440, height: 1440),
                    visibleFrame: NSRect(x: -3400, y: -850, width: 3300, height: 1300),
                    token: token
                )]
            },
            uuidProvider: { _ in "AbC-DeF" },
            diagnosticProvider: { _ in DisplayDiagnostics(vendorId: 11, modelId: 22, serialNumber: 33) },
            displayBoundsProvider: { _ in
                CGRect(x: -3440, y: 900, width: 3440, height: 1440)
            }
        )
        let result = catalog.connectedDisplays()[0]

        try expectEqual(result.display.stableId, "abc-def")
        try expectEqual(result.display.width, 3440)
        try expectEqual(result.display.height, 1440)
        try expectEqual(result.fullFrame.origin.x, -3440)
        try expectEqual(result.fullFrame.origin.y, -900)
        try expectEqual(result.visibleFrame, NSRect(x: -3400, y: -850, width: 3300, height: 1300))
        try expectEqual(
            result.topLeftFullFrame,
            RectD(x: -3440, y: 900, width: 3440, height: 1440)
        )
        try expect(result.nativeScreen === token)
        try expectEqual(result.display.vendorId, 11)
        try expectEqual(result.display.modelId, 22)
        try expectEqual(result.display.serialNumber, 33)
    },
    TestCase(name: "DisplayCatalog never synthesizes unavailable UUID") {
        let catalog = DisplayCatalog(
            screenProvider: {
                [snapshot(id: 98765, name: "Unknown", frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))]
            },
            uuidProvider: { _ in nil },
            diagnosticProvider: { _ in DisplayDiagnostics(vendorId: 1, modelId: 2, serialNumber: 3) },
            displayBoundsProvider: { _ in CGRect(x: 0, y: 0, width: 1920, height: 1080) }
        )

        try expectEqual(catalog.connectedDisplays()[0].display.stableId, nil)
    },
    TestCase(name: "DisplayCatalog maps AppKit work-area insets into top-left coordinates") {
        let catalog = DisplayCatalog(
            screenProvider: {
                [snapshot(
                    id: 8,
                    name: "Inset Display",
                    frame: NSRect(x: 100, y: -900, width: 1920, height: 1080),
                    visibleFrame: NSRect(x: 140, y: -850, width: 1800, height: 1000)
                )]
            },
            uuidProvider: { _ in "inset" },
            diagnosticProvider: { _ in DisplayDiagnostics() },
            displayBoundsProvider: { _ in
                CGRect(x: 100, y: 20, width: 1920, height: 1080)
            }
        )

        let result = catalog.connectedDisplays()[0]

        try expectEqual(
            result.topLeftFullFrame,
            RectD(x: 100, y: 20, width: 1920, height: 1080)
        )
        try expectEqual(
            result.topLeftVisibleFrame,
            RectD(x: 140, y: 50, width: 1800, height: 1000)
        )
    },
    TestCase(name: "DisplayCatalog reads fresh Core Graphics bounds for every snapshot") {
        var screenCalls = 0
        var boundsIds: [CGDirectDisplayID] = []
        let catalog = DisplayCatalog(
            screenProvider: {
                screenCalls += 1
                let id: CGDirectDisplayID = screenCalls == 1 ? 10 : 11
                return [snapshot(
                    id: id,
                    name: "Retina",
                    frame: NSRect(x: 0, y: 0, width: 1728, height: 1117)
                )]
            },
            uuidProvider: { "uuid-\($0)" },
            diagnosticProvider: { _ in DisplayDiagnostics() },
            displayBoundsProvider: { id in
                boundsIds.append(id)
                return CGRect(
                    x: id == 10 ? 0 : -1728,
                    y: id == 10 ? 0 : -1117,
                    width: 1728,
                    height: 1117
                )
            }
        )

        let first = catalog.connectedDisplays()[0]
        let second = catalog.connectedDisplays()[0]

        try expectEqual(first.topLeftFullFrame.width, 1728)
        try expectEqual(first.topLeftFullFrame.height, 1117)
        try expectEqual(second.topLeftFullFrame.x, -1728)
        try expectEqual(second.topLeftFullFrame.y, -1117)
        try expectEqual(boundsIds, [10, 11])
    },
]
