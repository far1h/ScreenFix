public struct NormalizedRect: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct DisplayIdentity: Codable, Equatable {
    public let stableId: String
    public let name: String
    public let width: Double
    public let height: Double
    public let vendorId: UInt32?
    public let modelId: UInt32?
    public let serialNumber: UInt32?

    public init(
        stableId: String,
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

public struct ScreenFixConfiguration: Codable, Equatable {
    public let schemaVersion: Int
    public let enabled: Bool
    public let display: DisplayIdentity
    public let bands: [NormalizedRect]

    public init(
        schemaVersion: Int,
        enabled: Bool,
        display: DisplayIdentity,
        bands: [NormalizedRect]
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.display = display
        self.bands = bands
    }
}

public struct RectD: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var right: Double { x + width }
    public var bottom: Double { y + height }

    public func intersects(_ other: RectD) -> Bool {
        x < other.right && other.x < right && y < other.bottom && other.y < bottom
    }
}

public struct TopLeftDisplayBounds: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
