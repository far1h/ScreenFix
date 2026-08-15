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
    public let visibleFrame: NSRect
    public let topLeftFullFrame: RectD
    public let topLeftVisibleFrame: RectD
    public let nativeScreen: AnyObject

    public init(
        display: ConnectedDisplay,
        fullFrame: NSRect,
        visibleFrame: NSRect? = nil,
        topLeftFullFrame: RectD? = nil,
        topLeftVisibleFrame: RectD? = nil,
        nativeScreen: AnyObject
    ) {
        let fallback = RectD(
            x: Double(fullFrame.minX),
            y: Double(fullFrame.minY),
            width: Double(fullFrame.width),
            height: Double(fullFrame.height)
        )
        self.display = display
        self.fullFrame = fullFrame
        self.visibleFrame = visibleFrame ?? fullFrame
        self.topLeftFullFrame = topLeftFullFrame ?? fallback
        self.topLeftVisibleFrame = topLeftVisibleFrame ?? fallback
        self.nativeScreen = nativeScreen
    }
}

public final class DisplayCatalog {
    public typealias ScreenProvider = () -> [ScreenSnapshot]
    public typealias UUIDProvider = (CGDirectDisplayID) -> String?
    public typealias DiagnosticProvider = (CGDirectDisplayID) -> DisplayDiagnostics
    public typealias DisplayBoundsProvider = (CGDirectDisplayID) -> CGRect

    private let screenProvider: ScreenProvider
    private let uuidProvider: UUIDProvider
    private let diagnosticProvider: DiagnosticProvider
    private let displayBoundsProvider: DisplayBoundsProvider

    public init(
        screenProvider: @escaping ScreenProvider,
        uuidProvider: @escaping UUIDProvider,
        diagnosticProvider: @escaping DiagnosticProvider,
        displayBoundsProvider: @escaping DisplayBoundsProvider
    ) {
        self.screenProvider = screenProvider
        self.uuidProvider = uuidProvider
        self.diagnosticProvider = diagnosticProvider
        self.displayBoundsProvider = displayBoundsProvider
    }

    public convenience init() {
        self.init(
            screenProvider: Self.liveScreenSnapshots,
            uuidProvider: Self.displayUUID,
            diagnosticProvider: Self.displayDiagnostics,
            displayBoundsProvider: CGDisplayBounds
        )
    }

    public func connectedDisplays() -> [ConnectedScreen] {
        screenProvider().map { snapshot in
            let diagnostics = diagnosticProvider(snapshot.directDisplayId)
            let stableId = uuidProvider(snapshot.directDisplayId)?.lowercased()
            let displayBounds = displayBoundsProvider(snapshot.directDisplayId)
            let topLeftFullFrame = RectD(
                x: Double(displayBounds.minX),
                y: Double(displayBounds.minY),
                width: Double(displayBounds.width),
                height: Double(displayBounds.height)
            )
            let leftInset = snapshot.visibleFrame.minX - snapshot.fullFrame.minX
            let rightInset = snapshot.fullFrame.maxX - snapshot.visibleFrame.maxX
            let topInset = snapshot.fullFrame.maxY - snapshot.visibleFrame.maxY
            let bottomInset = snapshot.visibleFrame.minY - snapshot.fullFrame.minY
            let topLeftVisibleFrame = RectD(
                x: topLeftFullFrame.x + Double(leftInset),
                y: topLeftFullFrame.y + Double(topInset),
                width: topLeftFullFrame.width - Double(leftInset + rightInset),
                height: topLeftFullFrame.height - Double(topInset + bottomInset)
            )
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
                visibleFrame: snapshot.visibleFrame,
                topLeftFullFrame: topLeftFullFrame,
                topLeftVisibleFrame: topLeftVisibleFrame,
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
