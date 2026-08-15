import Foundation

public enum ConfigurationError: Error, Equatable {
    case unsupportedSchemaVersion
    case missingDisplayIdentity
    case invalidDisplayDimensions
    case invalidBandCount
    case invalidBand(index: Int)
}

public enum ConfigValidator {
    public static func validate(_ configuration: ScreenFixConfiguration) throws {
        guard configuration.schemaVersion == 1 else {
            throw ConfigurationError.unsupportedSchemaVersion
        }
        guard !configuration.display.stableId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.missingDisplayIdentity
        }
        guard configuration.display.width.isFinite,
              configuration.display.height.isFinite,
              configuration.display.width > 0,
              configuration.display.height > 0 else {
            throw ConfigurationError.invalidDisplayDimensions
        }
        guard configuration.bands.count == 3 else {
            throw ConfigurationError.invalidBandCount
        }

        for (index, band) in configuration.bands.enumerated() {
            guard band.x.isFinite,
                  band.y.isFinite,
                  band.w.isFinite,
                  band.h.isFinite,
                  band.x >= 0,
                  band.y >= 0,
                  band.w > 0,
                  band.h > 0,
                  band.x + band.w <= 1,
                  band.y + band.h <= 1 else {
                throw ConfigurationError.invalidBand(index: index)
            }
        }
    }
}
