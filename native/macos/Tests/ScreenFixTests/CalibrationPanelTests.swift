import AppKit
import ScreenFixApp
import ScreenFixCore

private enum FakeCalibrationError: Error {
    case requested
}

private final class FakeCalibrationSurface: CalibrationSurface {
    let identifier: Int
    let frame: NSRect
    var isVisible = true
    private let log: NSMutableArray
    private let failConfigure: Bool
    private let failRender: Bool
    private let failOrder: Bool
    var onClose: (() -> Void)?
    private(set) var handler: ((CalibrationPointerEvent) -> Void)?
    private(set) var renderedBands: [NormalizedRect] = []

    init(
        identifier: Int,
        frame: NSRect,
        log: NSMutableArray,
        failConfigure: Bool = false,
        failRender: Bool = false,
        failOrder: Bool = false
    ) {
        self.identifier = identifier
        self.frame = frame
        self.log = log
        self.failConfigure = failConfigure
        self.failRender = failRender
        self.failOrder = failOrder
    }

    func configure(eventHandler: @escaping (CalibrationPointerEvent) -> Void) throws {
        log.add("configure-\(identifier)")
        if failConfigure { throw FakeCalibrationError.requested }
        handler = eventHandler
    }

    func render(bands: [NormalizedRect], controls: CalibrationControlLayout) throws {
        log.add("render-\(identifier)")
        if failRender { throw FakeCalibrationError.requested }
        renderedBands = bands
    }

    func orderAndVerify() throws {
        log.add("order-\(identifier)")
        if failOrder { throw FakeCalibrationError.requested }
        log.add("visible-\(identifier)")
    }

    func close() {
        log.add("close-\(identifier)")
        let callback = onClose
        onClose = nil
        callback?()
    }

    func send(_ event: CalibrationPointerEvent) {
        handler?(event)
    }
}

private func panelEvents(_ log: NSMutableArray) -> [String] {
    log.compactMap { $0 as? String }
}

private let panelFrame = NSRect(x: -1_000, y: -200, width: 1_000, height: 800)
private let panelBands = [
    NormalizedRect(x: 0.20, y: 0, w: 0.20, h: 0.33),
    NormalizedRect(x: 0.20, y: 0.33, w: 0.20, h: 0.34),
    NormalizedRect(x: 0.20, y: 0.67, w: 0.20, h: 0.33),
]

private func makeCalibrationController(
    log: NSMutableArray,
    old: FakeCalibrationSurface? = nil,
    failCreateAt: Int? = nil,
    failConfigureAt: Int? = nil,
    failRenderAt: Int? = nil,
    failOrderAt: Int? = nil,
    surfaces: NSMutableArray? = nil
) -> CalibrationPanelController {
    var nextIdentifier = 0
    return CalibrationPanelController(
        factory: { frame in
            nextIdentifier += 1
            log.add("create-\(nextIdentifier)")
            if nextIdentifier == failCreateAt { throw FakeCalibrationError.requested }
            let surface = FakeCalibrationSurface(
                identifier: nextIdentifier,
                frame: frame,
                log: log,
                failConfigure: nextIdentifier == failConfigureAt,
                failRender: nextIdentifier == failRenderAt,
                failOrder: nextIdentifier == failOrderAt
            )
            surfaces?.add(surface)
            return surface
        },
        initialCommitted: old
    )
}

let calibrationPanelTests = [
    TestCase(name: "CalibrationPanel candidate is configured rendered ordered before old closes") {
        let log = NSMutableArray()
        let old = FakeCalibrationSurface(identifier: 90, frame: panelFrame, log: log)
        let controller = makeCalibrationController(log: log, old: old)
        let prepared = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in },
            onCancel: {}
        )
        try controller.commit(prepared)

        try expectEqual(panelEvents(log), [
            "create-1", "configure-1", "render-1", "order-1", "visible-1", "close-90",
        ])
        try expect(controller.isEditing)
    },
    TestCase(name: "CalibrationPanel preparation failures close only candidate and preserve old") {
        for failure in ["create", "configure", "render", "order"] {
            let log = NSMutableArray()
            let old = FakeCalibrationSurface(identifier: 90, frame: panelFrame, log: log)
            let controller = makeCalibrationController(
                log: log,
                old: old,
                failCreateAt: failure == "create" ? 1 : nil,
                failConfigureAt: failure == "configure" ? 1 : nil,
                failRenderAt: failure == "render" ? 1 : nil,
                failOrderAt: failure == "order" ? 1 : nil
            )
            try expectThrows {
                _ = try controller.prepare(
                    screenFrame: panelFrame,
                    bands: panelBands,
                    onSave: { _ in },
                    onCancel: {}
                )
            }
            try expect(controller.isEditing)
            try expect(!panelEvents(log).contains("close-90"))
            if failure != "create" {
                try expect(panelEvents(log).contains("close-1"))
            }
        }
    },
    TestCase(name: "CalibrationPanel commit guard failure preserves active editor") {
        let log = NSMutableArray()
        let old = FakeCalibrationSurface(identifier: 90, frame: panelFrame, log: log)
        let controller = makeCalibrationController(log: log, old: old)
        let prepared = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in },
            onCancel: {}
        )
        try expectThrows { try controller.commit(prepared) { false } }

        try expect(controller.isEditing)
        try expect(!panelEvents(log).contains("close-90"))
        try expectEqual(Array(panelEvents(log).suffix(2)), ["visible-1", "close-1"])
    },
    TestCase(name: "CalibrationPanel prepared editor is single use") {
        let log = NSMutableArray()
        let controller = makeCalibrationController(log: log)
        let prepared = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in },
            onCancel: {}
        )
        try controller.commit(prepared)
        try controller.commit(prepared)
        controller.discard(prepared)
        try expectEqual(panelEvents(log).filter { $0 == "close-1" }.count, 0)
    },
    TestCase(name: "CalibrationPanel stop revokes callbacks before close and is idempotent") {
        let log = NSMutableArray()
        let surfaces = NSMutableArray()
        var saves = 0
        let controller = makeCalibrationController(log: log, surfaces: surfaces)
        let prepared = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in saves += 1 },
            onCancel: {}
        )
        try controller.commit(prepared)
        let surface = try requireSurface(surfaces.firstObject as? FakeCalibrationSurface)
        controller.stop()
        surface.send(.primaryDown(PointD(x: 50, y: 750)))
        controller.stop()

        try expectEqual(saves, 0)
        try expectEqual(panelEvents(log).filter { $0 == "close-1" }.count, 1)
        try expect(!controller.isEditing)
    },
    TestCase(name: "CalibrationPanel retired callbacks cannot redraw save cancel or mutate") {
        let log = NSMutableArray()
        let surfaces = NSMutableArray()
        var saves = 0
        var cancels = 0
        let controller = makeCalibrationController(log: log, surfaces: surfaces)
        let first = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in saves += 1 },
            onCancel: { cancels += 1 }
        )
        try controller.commit(first)
        let retired = try requireSurface(surfaces.firstObject as? FakeCalibrationSurface)
        let second = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in saves += 10 },
            onCancel: { cancels += 10 }
        )
        try controller.commit(second)
        let before = controller.workingBands
        retired.send(.primaryDown(PointD(x: 350, y: 200)))
        retired.send(.primaryDragged(PointD(x: 370, y: 200)))
        retired.send(.primaryDown(PointD(x: 50, y: 750)))
        retired.send(.primaryDown(PointD(x: 170, y: 750)))

        try expectEqual(controller.workingBands, before)
        try expectEqual(saves, 0)
        try expectEqual(cancels, 0)
    },
    TestCase(name: "CalibrationPanel preserves exact negative full display frame and properties") {
        _ = NSApplication.shared
        let panel = CalibrationPanelFactory().make(frame: panelFrame)
        defer { panel.close() }

        try expectEqual(panel.frame, panelFrame)
        try expectEqual(panel.constrainFrameRect(panelFrame, to: NSScreen.main), panelFrame)
        try expect(panel.styleMask.contains(.borderless))
        try expect(panel.styleMask.contains(.nonactivatingPanel))
        try expect(!panel.canBecomeKey)
        try expect(!panel.canBecomeMain)
        try expect(!panel.hasShadow)
        try expect(!panel.ignoresMouseEvents)
        try expect(!panel.hidesOnDeactivate)
        try expect(panel.acceptsMouseMovedEvents)
        try expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        try expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        try expect(panel.collectionBehavior.contains(.stationary))
        try expect(panel.collectionBehavior.contains(.ignoresCycle))
        try expect(panel.level.rawValue > NSWindow.Level.floating.rawValue)
    },
    TestCase(name: "CalibrationPanel view is flipped accepts first mouse and replaces tracking area") {
        _ = NSApplication.shared
        let view = CalibrationView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 800))
        try expect(view.isFlipped)
        try expect(view.acceptsFirstMouse(for: nil))
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        try expectEqual(view.trackingAreas.count, 1)
        let options = view.trackingAreas[0].options
        try expect(options.contains(.mouseMoved))
        try expect(options.contains(.activeAlways))
        try expect(options.contains(.inVisibleRect))
        view.stopTracking()
        try expectEqual(view.trackingAreas.count, 0)
    },
    TestCase(name: "CalibrationPanel reentrant commit guard cannot replace a newer editor") {
        let log = NSMutableArray()
        let surfaces = NSMutableArray()
        let controller = makeCalibrationController(log: log, surfaces: surfaces)
        let first = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in },
            onCancel: {}
        )
        let replacementBands = panelBands.map { band in
            NormalizedRect(x: band.x + 0.10, y: band.y, w: band.w, h: band.h)
        }

        try expectThrows {
            try controller.commit(first) {
                let replacement = try controller.prepare(
                    screenFrame: panelFrame,
                    bands: replacementBands,
                    onSave: { _ in },
                    onCancel: {}
                )
                try controller.commit(replacement)
                return true
            }
        }

        try expect(controller.isEditing)
        try expectEqual(controller.workingBands, replacementBands)
        try expect(panelEvents(log).contains("close-1"))
        try expect(!panelEvents(log).contains("close-2"))
    },
    TestCase(name: "CalibrationPanel reentrant Save cannot stop a newer editor") {
        let log = NSMutableArray()
        let surfaces = NSMutableArray()
        let controller = makeCalibrationController(log: log, surfaces: surfaces)
        let replacementBands = panelBands.map { band in
            NormalizedRect(x: band.x + 0.10, y: band.y, w: band.w, h: band.h)
        }
        let first = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in
                let replacement = try controller.prepare(
                    screenFrame: panelFrame,
                    bands: replacementBands,
                    onSave: { _ in },
                    onCancel: {}
                )
                try controller.commit(replacement)
            },
            onCancel: {}
        )
        try controller.commit(first)
        let firstSurface = try requireSurface(surfaces.firstObject as? FakeCalibrationSurface)

        firstSurface.send(.primaryDown(PointD(x: 50, y: 750)))

        try expect(controller.isEditing)
        try expectEqual(controller.workingBands, replacementBands)
        try expectEqual(panelEvents(log).filter { $0 == "close-1" }.count, 1)
        try expect(!panelEvents(log).contains("close-2"))
    },
    TestCase(name: "CalibrationPanel reentrant close cannot retire a newer editor") {
        let log = NSMutableArray()
        let surfaces = NSMutableArray()
        let controller = makeCalibrationController(log: log, surfaces: surfaces)
        let replacementBands = panelBands.map { band in
            NormalizedRect(x: band.x + 0.10, y: band.y, w: band.w, h: band.h)
        }
        var cancels = 0
        let first = try controller.prepare(
            screenFrame: panelFrame,
            bands: panelBands,
            onSave: { _ in },
            onCancel: { cancels += 1 }
        )
        try controller.commit(first)
        let firstSurface = try requireSurface(surfaces.firstObject as? FakeCalibrationSurface)
        firstSurface.onClose = {
            guard let replacement = try? controller.prepare(
                screenFrame: panelFrame,
                bands: replacementBands,
                onSave: { _ in },
                onCancel: {}
            ) else { return }
            try? controller.commit(replacement)
        }

        firstSurface.send(.primaryDown(PointD(x: 170, y: 750)))

        try expectEqual(cancels, 1)
        try expect(controller.isEditing)
        try expectEqual(controller.workingBands, replacementBands)
        try expect(!panelEvents(log).contains("close-2"))
    },
]

private func requireSurface(_ surface: FakeCalibrationSurface?) throws -> FakeCalibrationSurface {
    guard let surface else { throw TestFailure(description: "expected calibration surface") }
    return surface
}
