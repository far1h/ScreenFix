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
                + accessibilityTrustTests
                + axClientTests
                + axObserverRegistryTests
                + windowGuardTests
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
