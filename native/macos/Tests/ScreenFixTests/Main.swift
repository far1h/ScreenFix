@main
enum Main {
    static func main() {
        runTests(
            defaultConfigurationTests
                + calibrationGeometryTests
                + maskGeometryTests
                + configValidatorTests
                + displaySelectorTests
                + configStoreTests
                + maskPanelTests
                + displayCatalogTests
                + menuStateTests
                + menuModelTests
                + runtimeControllerTests
        )
    }
}
