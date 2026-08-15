import AppKit
import ScreenFixCore

public final class CalibrationView: NSView {
    public var eventHandler: ((CalibrationPointerEvent) -> Void)?
    private var calibrationTrackingArea: NSTrackingArea?
    private var bands: [NormalizedRect] = []
    private var controls: CalibrationControlLayout?

    public override var isFlipped: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public func update(bands: [NormalizedRect], controls: CalibrationControlLayout) {
        self.bands = bands
        self.controls = controls
        needsDisplay = true
    }

    public override func updateTrackingAreas() {
        if let calibrationTrackingArea {
            removeTrackingArea(calibrationTrackingArea)
        }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        calibrationTrackingArea = trackingArea
    }

    public var hasRequiredTrackingArea: Bool {
        guard trackingAreas.count == 1 else { return false }
        let options = trackingAreas[0].options
        return options.contains(.mouseMoved)
            && options.contains(.activeAlways)
            && options.contains(.inVisibleRect)
    }

    public func stopTracking() {
        if let calibrationTrackingArea {
            removeTrackingArea(calibrationTrackingArea)
            self.calibrationTrackingArea = nil
        }
    }

    public override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        eventHandler?(.primaryDown(localPoint(for: event)))
    }

    public override func mouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        eventHandler?(.primaryDragged(localPoint(for: event)))
    }

    public override func mouseMoved(with event: NSEvent) {
        eventHandler?(.pointerMoved(localPoint(for: event)))
    }

    public override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        eventHandler?(.primaryUp(localPoint(for: event)))
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let controls else { return }
        NSGraphicsContext.current?.shouldAntialias = true
        let frames = MaskGeometry.localFrames(
            bands: bands,
            displayWidth: bounds.width,
            displayHeight: bounds.height
        )
        drawBands(frames)
        drawControls(controls)
    }

    private func localPoint(for event: NSEvent) -> PointD {
        let point = convert(event.locationInWindow, from: nil)
        return PointD(x: point.x, y: point.y)
    }

    private func drawBands(_ frames: [RectD]) {
        for frame in frames {
            let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            NSColor(calibratedRed: 0.95, green: 0.12, blue: 0.08, alpha: 0.45).setFill()
            rect.fill()
            NSColor(calibratedRed: 1, green: 0.55, blue: 0.15, alpha: 1).setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 3
            outline.stroke()
            NSColor.white.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: 8, height: rect.height).fill()
            NSRect(x: rect.maxX - 8, y: rect.minY, width: 8, height: rect.height).fill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 8).fill()
            NSRect(x: rect.minX, y: rect.maxY - 8, width: rect.width, height: 8).fill()
        }
    }

    private func drawControls(_ layout: CalibrationControlLayout) {
        drawPill(
            layout.save,
            color: NSColor(
                calibratedRed: 22.0 / 255,
                green: 163.0 / 255,
                blue: 74.0 / 255,
                alpha: 1
            ),
            radius: 9
        )
        drawCenteredLabel("Save", in: layout.save, size: 16)
        drawPill(
            layout.cancel,
            color: NSColor(
                calibratedRed: 53.0 / 255,
                green: 58.0 / 255,
                blue: 66.0 / 255,
                alpha: 1
            ),
            radius: 9
        )
        drawCenteredLabel("Cancel", in: layout.cancel, size: 16)

        let instructionPath = NSBezierPath(
            roundedRect: appKit(layout.instruction),
            xRadius: 10,
            yRadius: 10
        )
        NSColor(calibratedWhite: 0, alpha: 0.88).setFill()
        instructionPath.fill()
        NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
        instructionPath.lineWidth = 1
        instructionPath.stroke()
        drawPill(
            layout.instructionDot,
            color: NSColor(
                calibratedRed: 1,
                green: 100.0 / 255,
                blue: 59.0 / 255,
                alpha: 1
            ),
            radius: 4
        )
        drawLeftLabel(
            "Drag red bands or white edges",
            in: layout.instructionText,
            size: layout.instructionTextSize
        )
    }

    private func drawPill(_ frame: RectD, color: NSColor, radius: Double) {
        color.setFill()
        NSBezierPath(
            roundedRect: appKit(frame),
            xRadius: radius,
            yRadius: radius
        ).fill()
    }

    private func drawCenteredLabel(_ value: String, in frame: RectD, size: Double) {
        let attributes = textAttributes(size: size)
        let bounds = measuredBounds(value, attributes: attributes)
        let target = NSRect(
            x: frame.x + (frame.width - bounds.width) / 2,
            y: frame.y + (frame.height - bounds.height) / 2,
            width: bounds.width,
            height: bounds.height
        )
        (value as NSString).draw(in: target, withAttributes: attributes)
    }

    private func drawLeftLabel(_ value: String, in frame: RectD, size: Double) {
        let attributes = textAttributes(size: size)
        let measured = measuredBounds(value, attributes: attributes)
        let target = NSRect(
            x: frame.x,
            y: frame.y + (frame.height - measured.height) / 2,
            width: frame.width,
            height: measured.height
        )
        (value as NSString).draw(in: target, withAttributes: attributes)
    }

    private func textAttributes(size: Double) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
    }

    private func measuredBounds(
        _ value: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSRect {
        (value as NSString).boundingRect(
            with: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func appKit(_ rect: RectD) -> NSRect {
        NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
