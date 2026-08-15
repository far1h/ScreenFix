import ScreenFixCore

private let ultrawide = DisplayIdentity(
    stableId: "3F8D0E18-EXAMPLE",
    name: "Ultrawide",
    width: 3440,
    height: 1440,
    vendorId: 1,
    modelId: 2,
    serialNumber: 3
)

let defaultConfigurationTests = [
    TestCase(name: "DefaultConfiguration uses exact permanent bands") {
        let config = DefaultConfiguration.make(for: ultrawide, enabled: true)

        try expectEqual(config.schemaVersion, 1)
        try expect(config.enabled)
        try expectEqual(config.bands.count, 3)
        try expectEqual(config.bands[0].x, 1215.0 / 3440.0, accuracy: 1e-12)
        try expectEqual(config.bands[0].w, (1920.0 - 1215.0) / 3440.0, accuracy: 1e-12)
        try expectEqual(config.bands.map(\.y), [0.0, 0.34, 0.73])
        try expectEqual(config.bands.map(\.h), [0.34, 0.39, 0.27])
    },
    TestCase(name: "DefaultConfiguration preserves disabled state") {
        let config = DefaultConfiguration.make(for: ultrawide, enabled: false)
        try expect(!config.enabled)
    },
    TestCase(name: "DefaultConfiguration returns independent values") {
        var first = DefaultConfiguration.make(for: ultrawide, enabled: true)
        let second = DefaultConfiguration.make(for: ultrawide, enabled: true)
        first = ScreenFixConfiguration(
            schemaVersion: first.schemaVersion,
            enabled: first.enabled,
            display: first.display,
            bands: []
        )
        try expectEqual(first.bands.count, 0)
        try expectEqual(second.bands.count, 3)
    },
]
