import AppKit
import ScreenFixCore

public final class CalibrationPanel: NSPanel, CalibrationSurface {
    private var calibrationView: CalibrationView?

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    public func configure(eventHandler: @escaping (CalibrationPointerEvent) -> Void) throws {
        let view = CalibrationView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.eventHandler = eventHandler
        contentView = view
        calibrationView = view
    }

    public func render(bands: [NormalizedRect], controls: CalibrationControlLayout) throws {
        guard let calibrationView else { throw CalibrationPanelError.notConfigured }
        calibrationView.update(bands: bands, controls: controls)
    }

    public func orderAndVerify() throws {
        guard let calibrationView else { throw CalibrationPanelError.notConfigured }
        calibrationView.updateTrackingAreas()
        guard calibrationView.hasRequiredTrackingArea else {
            throw CalibrationPanelError.invalidTrackingArea
        }
        orderFrontRegardless()
        guard isVisible else { throw CalibrationPanelError.notVisible }
    }

    public override func close() {
        calibrationView?.eventHandler = nil
        calibrationView?.stopTracking()
        super.close()
    }
}

public struct CalibrationPanelFactory {
    public init() {}

    public func make(frame: NSRect) -> CalibrationPanel {
        let panel = CalibrationPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow))
        )
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
