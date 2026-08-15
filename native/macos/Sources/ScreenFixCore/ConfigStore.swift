import Foundation

public final class ConfigStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return applicationSupport
            .appendingPathComponent("ScreenFix", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> ScreenFixConfiguration? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(ScreenFixConfiguration.self, from: data)
        try ConfigValidator.validate(configuration)
        return configuration
    }

    public func save(_ configuration: ScreenFixConfiguration) throws {
        try ConfigValidator.validate(configuration)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(configuration)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
    }
}
