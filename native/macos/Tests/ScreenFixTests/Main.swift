@main
enum Main {
    static func main() {
        runTests(
            defaultConfigurationTests
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
