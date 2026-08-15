import AppKit
import CoreFoundation
import CoreGraphics
import ScreenFixCore

public struct DisplayDiagnostics {
    public let vendorId: UInt32?
    public let modelId: UInt32?
    public let serialNumber: UInt32?

    public init(
        vendorId: UInt32? = nil,
        modelId: UInt32? = nil,
        serialNumber: UInt32? = nil
    ) {
        self.vendorId = vendorId
        self.modelId = modelId
        self.serialNumber = serialNumber
    }
}

public struct ScreenSnapshot {
    public let directDisplayId: CGDirectDisplayID
    public let name: String
    public let fullFrame: NSRect
    public let visibleFrame: NSRect
    public let nativeScreen: AnyObject

    public init(
        directDisplayId: CGDirectDisplayID,
        name: String,
        fullFrame: NSRect,
        visibleFrame: NSRect,
        nativeScreen: AnyObject
    ) {
        self.directDisplayId = directDisplayId
        self.name = name
        self.fullFrame = fullFrame
        self.visibleFrame = visibleFrame
        self.nativeScreen = nativeScreen
    }
}

public struct ConnectedScreen {
    public let display: ConnectedDisplay
    public let fullFrame: NSRect
    public let nativeScreen: AnyObject

    public init(display: ConnectedDisplay, fullFrame: NSRect, nativeScreen: AnyObject) {
        self.display = display
        self.fullFrame = fullFrame
        self.nativeScreen = nativeScreen
    }
}

public final class DisplayCatalog {
    public typealias ScreenProvider = () -> [ScreenSnapshot]
    public typealias UUIDProvider = (CGDirectDisplayID) -> String?
    public typealias DiagnosticProvider = (CGDirectDisplayID) -> DisplayDiagnostics

    private let screenProvider: ScreenProvider
    private let uuidProvider: UUIDProvider
    private let diagnosticProvider: DiagnosticProvider

    public init(
        screenProvider: @escaping ScreenProvider,
        uuidProvider: @escaping UUIDProvider,
        diagnosticProvider: @escaping DiagnosticProvider
    ) {
        self.screenProvider = screenProvider
        self.uuidProvider = uuidProvider
        self.diagnosticProvider = diagnosticProvider
    }

    public convenience init() {
        self.init(
            screenProvider: Self.liveScreenSnapshots,
            uuidProvider: Self.displayUUID,
            diagnosticProvider: Self.displayDiagnostics
        )
    }

    public func connectedDisplays() -> [ConnectedScreen] {
        screenProvider().map { snapshot in
            let diagnostics = diagnosticProvider(snapshot.directDisplayId)
            let stableId = uuidProvider(snapshot.directDisplayId)?.lowercased()
            let display = ConnectedDisplay(
                stableId: stableId,
                name: snapshot.name,
                width: Double(snapshot.fullFrame.width),
                height: Double(snapshot.fullFrame.height),
                vendorId: diagnostics.vendorId,
                modelId: diagnostics.modelId,
                serialNumber: diagnostics.serialNumber
            )
            return ConnectedScreen(
                display: display,
                fullFrame: snapshot.fullFrame,
                nativeScreen: snapshot.nativeScreen
            )
        }
    }

    private static func liveScreenSnapshots() -> [ScreenSnapshot] {
        NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            return ScreenSnapshot(
                directDisplayId: CGDirectDisplayID(number.uint32Value),
                name: screen.localizedName,
                fullFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                nativeScreen: screen
            )
        }
    }

    private static func displayUUID(_ displayId: CGDirectDisplayID) -> String? {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayId) else { return nil }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func displayDiagnostics(_ displayId: CGDirectDisplayID) -> DisplayDiagnostics {
        DisplayDiagnostics(
            vendorId: CGDisplayVendorNumber(displayId),
            modelId: CGDisplayModelNumber(displayId),
            serialNumber: CGDisplaySerialNumber(displayId)
        )
    }
}
