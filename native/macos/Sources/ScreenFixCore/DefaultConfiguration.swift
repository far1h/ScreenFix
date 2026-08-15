public enum DefaultConfiguration {
    public static func make(
        for display: DisplayIdentity,
        enabled: Bool
    ) -> ScreenFixConfiguration {
        let left = 1215.0 / 3440.0
        let width = (1920.0 - 1215.0) / 3440.0
        return ScreenFixConfiguration(
            schemaVersion: 1,
            enabled: enabled,
            display: display,
            bands: [
                NormalizedRect(x: left, y: 0.0, w: width, h: 0.34),
                NormalizedRect(x: left, y: 0.34, w: width, h: 0.39),
                NormalizedRect(x: left, y: 0.73, w: width, h: 0.27),
            ]
        )
    }
}
