import ScreenFixCore

private let validDisplay = DisplayIdentity(
    stableId: "saved-uuid",
    name: "Ultrawide",
    width: 3440,
    height: 1440
)

private func configuration(
    schemaVersion: Int = 1,
    display: DisplayIdentity = validDisplay,
    bands: [NormalizedRect]? = nil
) -> ScreenFixConfiguration {
    ScreenFixConfiguration(
        schemaVersion: schemaVersion,
        enabled: true,
        display: display,
        bands: bands ?? DefaultConfiguration.make(for: validDisplay, enabled: true).bands
    )
}

private func expectConfigurationError(_ config: ScreenFixConfiguration) throws {
    do {
        try ConfigValidator.validate(config)
    } catch is ConfigurationError {
        return
    }
    throw TestFailure(description: "expected typed ConfigurationError")
}

let configValidatorTests = [
    TestCase(name: "ConfigValidator accepts the exact valid default") {
        try ConfigValidator.validate(configuration())
    },
    TestCase(name: "ConfigValidator rejects unknown schema versions") {
        try expectConfigurationError(configuration(schemaVersion: 0))
        try expectConfigurationError(configuration(schemaVersion: 2))
    },
    TestCase(name: "ConfigValidator rejects missing display identity") {
        for stableId in ["", "   \n"] {
            try expectConfigurationError(configuration(display: DisplayIdentity(
                stableId: stableId,
                name: "Ultrawide",
                width: 3440,
                height: 1440
            )))
        }
    },
    TestCase(name: "ConfigValidator rejects invalid display dimensions") {
        for value in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
            try expectConfigurationError(configuration(display: DisplayIdentity(
                stableId: "saved-uuid",
                name: "Ultrawide",
                width: value,
                height: 1440
            )))
            try expectConfigurationError(configuration(display: DisplayIdentity(
                stableId: "saved-uuid",
                name: "Ultrawide",
                width: 3440,
                height: value
            )))
        }
    },
    TestCase(name: "ConfigValidator requires exactly three bands") {
        let validBands = DefaultConfiguration.make(for: validDisplay, enabled: true).bands
        try expectConfigurationError(configuration(bands: Array(validBands.prefix(2))))
        try expectConfigurationError(configuration(bands: validBands + [validBands[0]]))
    },
    TestCase(name: "ConfigValidator rejects non-finite band fields") {
        let invalids = [Double.nan, Double.infinity, -Double.infinity]
        for value in invalids {
            try expectConfigurationError(configuration(bands: [
                NormalizedRect(x: value, y: 0, w: 0.2, h: 0.2),
                NormalizedRect(x: 0, y: value, w: 0.2, h: 0.2),
                NormalizedRect(x: 0, y: 0, w: value, h: value),
            ]))
        }
    },
    TestCase(name: "ConfigValidator rejects out-of-range and non-positive bands") {
        let invalidBands = [
            NormalizedRect(x: -0.1, y: 0, w: 0.2, h: 0.2),
            NormalizedRect(x: 0, y: -0.1, w: 0.2, h: 0.2),
            NormalizedRect(x: 0, y: 0, w: 0, h: 0.2),
            NormalizedRect(x: 0, y: 0, w: 0.2, h: 0),
            NormalizedRect(x: 0.9, y: 0, w: 0.2, h: 0.2),
            NormalizedRect(x: 0, y: 0.9, w: 0.2, h: 0.2),
        ]
        let valid = NormalizedRect(x: 0, y: 0, w: 0.2, h: 0.2)
        for invalid in invalidBands {
            try expectConfigurationError(configuration(bands: [invalid, valid, valid]))
        }
    },
    TestCase(name: "ConfigValidator accepts bands touching right and bottom boundaries") {
        let bands = [
            NormalizedRect(x: 0.8, y: 0, w: 0.2, h: 1),
            NormalizedRect(x: 0, y: 0.8, w: 1, h: 0.2),
            NormalizedRect(x: 0, y: 0, w: 1, h: 1),
        ]
        try ConfigValidator.validate(configuration(bands: bands))
    },
]
