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
