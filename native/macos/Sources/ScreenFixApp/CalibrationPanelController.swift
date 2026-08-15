import AppKit
import ScreenFixCore

public enum CalibrationPanelError: Error {
    case invalidFrame
    case invalidBands
    case commitRejected
    case notConfigured
    case notVisible
    case invalidTrackingArea
}

public protocol CalibrationSurface: AnyObject {
    var frame: NSRect { get }
    var isVisible: Bool { get }
    func configure(eventHandler: @escaping (CalibrationPointerEvent) -> Void) throws
    func render(bands: [NormalizedRect], controls: CalibrationControlLayout) throws
    func orderAndVerify() throws
    func close()
}

private final class CalibrationEditorSession {
    let token: Int
    let surface: CalibrationSurface
    let displaySize: RectD
    let controls: CalibrationControlLayout
    let onSave: ([NormalizedRect]) throws -> Void
    let onCancel: () throws -> Void
    var interaction: CalibrationInteraction

    init(
        token: Int,
        surface: CalibrationSurface,
        displaySize: RectD,
        controls: CalibrationControlLayout,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void
    ) {
        self.token = token
        self.surface = surface
        self.displaySize = displaySize
        self.controls = controls
        self.onSave = onSave
        self.onCancel = onCancel
        interaction = CalibrationInteraction(workingBands: bands)
    }
}

public final class PreparedCalibrationEditor {
    private var session: CalibrationEditorSession?

    fileprivate init(session: CalibrationEditorSession) {
        self.session = session
    }

    fileprivate func take() -> CalibrationEditorSession? {
        defer { session = nil }
        return session
    }
}

public final class CalibrationPanelController {
    public typealias Factory = (NSRect) throws -> CalibrationSurface

    private let factory: Factory
    private let reportError: (Error) -> Void
    private var nextToken = 0
    private var active: CalibrationEditorSession?

    public init(
        factory: @escaping Factory = { CalibrationPanelFactory().make(frame: $0) },
        initialCommitted: CalibrationSurface? = nil,
        reportError: @escaping (Error) -> Void = { _ in }
    ) {
        self.factory = factory
        self.reportError = reportError
        if let initialCommitted,
           let controls = CalibrationControlLayout.make(
               width: initialCommitted.frame.width,
               height: initialCommitted.frame.height
           ) {
            active = CalibrationEditorSession(
                token: 0,
                surface: initialCommitted,
                displaySize: Self.displaySize(for: initialCommitted.frame),
                controls: controls,
                bands: [],
                onSave: { _ in },
                onCancel: {}
            )
        }
    }

    public var isEditing: Bool { active != nil }
    public var workingBands: [NormalizedRect] { active?.interaction.workingBands ?? [] }

    public func prepare(
        screenFrame: NSRect,
        bands: [NormalizedRect],
        onSave: @escaping ([NormalizedRect]) throws -> Void,
        onCancel: @escaping () throws -> Void
    ) throws -> PreparedCalibrationEditor {
        guard Self.isFinite(screenFrame), screenFrame.width > 0, screenFrame.height > 0,
              let controls = CalibrationControlLayout.make(
                  width: screenFrame.width,
                  height: screenFrame.height
              ) else {
            throw CalibrationPanelError.invalidFrame
        }
        guard Self.areValid(bands) else { throw CalibrationPanelError.invalidBands }

        nextToken += 1
        let token = nextToken
        let candidate = try factory(screenFrame)
        let session = CalibrationEditorSession(
            token: token,
            surface: candidate,
            displaySize: Self.displaySize(for: screenFrame),
            controls: controls,
            bands: bands,
            onSave: onSave,
            onCancel: onCancel
        )
        do {
            try candidate.configure { [weak self] event in
                self?.dispatch(event, token: token)
            }
            try candidate.render(bands: bands, controls: controls)
            try candidate.orderAndVerify()
        } catch {
            candidate.close()
            throw error
        }
        return PreparedCalibrationEditor(session: session)
    }

    public func commit(
        _ prepared: PreparedCalibrationEditor,
        commitGuard: () throws -> Bool = { true }
    ) throws {
        guard let candidate = prepared.take() else { return }
        do {
            guard try commitGuard() else { throw CalibrationPanelError.commitRejected }
        } catch {
            candidate.surface.close()
            throw error
        }
        let previous = active
        active = candidate
        previous?.surface.close()
    }

    public func discard(_ prepared: PreparedCalibrationEditor) {
        prepared.take()?.surface.close()
    }

    public func stop() {
        let previous = active
        active = nil
        previous?.surface.close()
    }

    private func dispatch(_ event: CalibrationPointerEvent, token: Int) {
        guard let session = active, session.token == token else { return }
        var staged = session.interaction
        let effect = staged.handle(event, displaySize: session.displaySize, controls: session.controls)
        switch effect {
        case .none:
            guard active?.token == token else { return }
            session.interaction = staged
        case .redraw:
            do {
                try session.surface.render(bands: staged.workingBands, controls: session.controls)
                guard active?.token == token else { return }
                session.interaction = staged
            } catch {
                reportError(error)
            }
        case .saveRequested:
            do {
                try session.onSave(staged.workingBands)
                guard active?.token == token else { return }
                stop()
            } catch {
                reportError(error)
            }
        case .cancelRequested:
            active = nil
            session.surface.close()
            do {
                try session.onCancel()
            } catch {
                reportError(error)
            }
        }
    }

    private static func displaySize(for frame: NSRect) -> RectD {
        RectD(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    private static func isFinite(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }

    private static func areValid(_ bands: [NormalizedRect]) -> Bool {
        bands.count == 3 && bands.allSatisfy { band in
            band.x.isFinite && band.y.isFinite && band.w.isFinite && band.h.isFinite
                && band.x >= 0 && band.y >= 0 && band.w > 0 && band.h > 0
                && band.x + band.w <= 1 && band.y + band.h <= 1
        }
    }
}
