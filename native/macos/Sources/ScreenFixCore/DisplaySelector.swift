import Foundation

public struct ConnectedDisplay: Equatable {
    public let stableId: String?
    public let name: String
    public let width: Double
    public let height: Double
    public let vendorId: UInt32?
    public let modelId: UInt32?
    public let serialNumber: UInt32?

    public init(
        stableId: String?,
        name: String,
        width: Double,
        height: Double,
        vendorId: UInt32? = nil,
        modelId: UInt32? = nil,
        serialNumber: UInt32? = nil
    ) {
        self.stableId = stableId
        self.name = name
        self.width = width
        self.height = height
        self.vendorId = vendorId
        self.modelId = modelId
        self.serialNumber = serialNumber
    }
}

public enum DisplaySelector {
    public static func select(
        saved: DisplayIdentity,
        from connectedDisplays: [ConnectedDisplay]
    ) -> ConnectedDisplay? {
        if let stableMatch = connectedDisplays.first(where: { display in
            display.stableId?.caseInsensitiveCompare(saved.stableId) == .orderedSame
        }) {
            return stableMatch
        }

        let fallbackMatches = connectedDisplays.filter { display in
            display.name == saved.name
                && display.width == saved.width
                && display.height == saved.height
        }
        return fallbackMatches.count == 1 ? fallbackMatches[0] : nil
    }
}
