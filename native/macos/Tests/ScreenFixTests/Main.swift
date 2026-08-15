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
                + displayAssignmentTests
                + windowEligibilityTests
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
