@main
enum Main {
    static func main() {
        runTests(
            defaultConfigurationTests
                + calibrationGeometryTests
                + calibrationInteractionTests
                + calibrationLayoutTests
                + calibrationPanelTests
                + maskGeometryTests
                + windowCorrectionTests
                + configValidatorTests
                + displaySelectorTests
                + configStoreTests
                + maskPanelTests
                + displayCatalogTests
                + menuStateTests
                + menuModelTests
                + runtimeCalibrationTests
                + runtimeControllerTests
        )
    }
}
