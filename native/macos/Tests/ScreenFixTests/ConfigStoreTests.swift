import Foundation
import ScreenFixCore

private func temporaryStore() -> (directory: URL, file: URL, store: ConfigStore) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenFixTests-\(UUID().uuidString)", isDirectory: true)
    let file = directory
        .appendingPathComponent("ScreenFix", isDirectory: true)
        .appendingPathComponent("config.json")
    return (directory, file, ConfigStore(fileURL: file))
}

private func storeConfiguration(enabled: Bool = true) -> ScreenFixConfiguration {
    DefaultConfiguration.make(
        for: DisplayIdentity(
            stableId: "store-uuid",
            name: "Ultrawide",
            width: 3440,
            height: 1440,
            vendorId: 11,
            modelId: 22,
            serialNumber: 33
        ),
        enabled: enabled
    )
}

let configStoreTests = [
    TestCase(name: "ConfigStore missing file returns nil without creating defaults") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try expectEqual(try fixture.store.load(), nil)
        try expect(!FileManager.default.fileExists(atPath: fixture.file.path))
    },
    TestCase(name: "ConfigStore save creates its parent directory") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try fixture.store.save(storeConfiguration())
        try expect(FileManager.default.fileExists(atPath: fixture.file.path))
    },
    TestCase(name: "ConfigStore valid configuration round trips exactly") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let expected = storeConfiguration()

        try fixture.store.save(expected)
        try expectEqual(try fixture.store.load(), expected)
    },
    TestCase(name: "ConfigStore emits the logical JSON keys") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.save(storeConfiguration())

        let text = try String(contentsOf: fixture.file, encoding: .utf8)
        for key in ["schemaVersion", "enabled", "display", "bands", "x", "y", "w", "h"] {
            try expect(text.contains("\"\(key)\""), "missing JSON key \(key)")
        }
        try expect(text.hasSuffix("\n"), "JSON must end with one newline")
    },
    TestCase(name: "ConfigStore malformed JSON is preserved") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(
            at: fixture.file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("{ definitely not JSON".utf8)
        try original.write(to: fixture.file)

        try expectThrows { _ = try fixture.store.load() }
        try expectEqual(try Data(contentsOf: fixture.file), original)
    },
    TestCase(name: "ConfigStore contract-invalid JSON is preserved") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(
            at: fixture.file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let invalid = ScreenFixConfiguration(
            schemaVersion: 1,
            enabled: true,
            display: storeConfiguration().display,
            bands: []
        )
        let encoder = JSONEncoder()
        let original = try encoder.encode(invalid)
        try original.write(to: fixture.file)

        try expectThrows { _ = try fixture.store.load() }
        try expectEqual(try Data(contentsOf: fixture.file), original)
    },
    TestCase(name: "ConfigStore valid save atomically replaces older valid config") {
        let fixture = temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try fixture.store.save(storeConfiguration(enabled: true))
        try fixture.store.save(storeConfiguration(enabled: false))
        let loaded = try fixture.store.load()
        try expectEqual(loaded, storeConfiguration(enabled: false))
    },
]
