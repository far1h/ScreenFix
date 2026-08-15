public struct CalibrationControlLayout: Equatable {
    public let save: RectD
    public let cancel: RectD
    public let instruction: RectD
    public let instructionDot: RectD
    public let instructionText: RectD
    public let instructionTextSize: Double

    public init(
        save: RectD,
        cancel: RectD,
        instruction: RectD,
        instructionDot: RectD,
        instructionText: RectD,
        instructionTextSize: Double
    ) {
        self.save = save
        self.cancel = cancel
        self.instruction = instruction
        self.instructionDot = instructionDot
        self.instructionText = instructionText
        self.instructionTextSize = instructionTextSize
    }
}

public enum CalibrationPointerEvent: Equatable {
    case primaryDown(PointD)
    case primaryDragged(PointD)
    case pointerMoved(PointD)
    case primaryUp(PointD)
}

public enum CalibrationEffect: Equatable {
    case none
    case redraw
    case saveRequested
    case cancelRequested
}

public struct CalibrationInteraction {
    private struct Drag {
        let hit: CalibrationHit
        let pressPoint: PointD
        var lastPoint: PointD
        var rawBand: NormalizedRect
        var moved: Bool
        var latched: Bool
    }

    public private(set) var workingBands: [NormalizedRect]
    public private(set) var isLatched = false
    private var drag: Drag?

    public init(workingBands: [NormalizedRect]) {
        self.workingBands = workingBands
    }

    public mutating func handle(
        _ event: CalibrationPointerEvent,
        displaySize: RectD,
        controls: CalibrationControlLayout
    ) -> CalibrationEffect {
        switch event {
        case let .primaryDown(point):
            return begin(at: point, displaySize: displaySize, controls: controls)
        case let .primaryDragged(point):
            guard drag?.latched == false else { return .none }
            return update(at: point, displaySize: displaySize)
        case let .pointerMoved(point):
            guard drag?.latched == true else { return .none }
            return update(at: point, displaySize: displaySize)
        case let .primaryUp(point):
            guard isFinite(point), var current = drag, !current.latched else { return .none }
            if current.moved {
                drag = nil
                isLatched = false
            } else {
                current.latched = true
                drag = current
                isLatched = true
            }
            return .none
        }
    }

    private mutating func begin(
        at point: PointD,
        displaySize: RectD,
        controls: CalibrationControlLayout
    ) -> CalibrationEffect {
        guard isFinite(point) else { return .none }
        if controls.save.contains(point) { return .saveRequested }
        if controls.cancel.contains(point) { return .cancelRequested }
        if drag?.latched == true {
            drag = nil
            isLatched = false
            return .none
        }
        guard isUsable(displaySize) else { return .none }
        let frames = MaskGeometry.localFrames(
            bands: workingBands,
            displayWidth: displaySize.width,
            displayHeight: displaySize.height
        )
        guard let hit = CalibrationGeometry.hitTest(point: point, frames: frames, handleSize: 8),
              workingBands.indices.contains(hit.bandIndex) else {
            drag = nil
            isLatched = false
            return .none
        }
        drag = Drag(
            hit: hit,
            pressPoint: point,
            lastPoint: point,
            rawBand: workingBands[hit.bandIndex],
            moved: false,
            latched: false
        )
        isLatched = false
        return .none
    }

    private mutating func update(at point: PointD, displaySize: RectD) -> CalibrationEffect {
        guard isFinite(point), isUsable(displaySize), var current = drag,
              workingBands.indices.contains(current.hit.bandIndex) else {
            return .none
        }
        if !current.moved {
            let x = point.x - current.pressPoint.x
            let y = point.y - current.pressPoint.y
            guard x * x + y * y >= 16 else { return .none }
        }
        let delta = PointD(x: point.x - current.lastPoint.x, y: point.y - current.lastPoint.y)
        let rawCandidate = CalibrationGeometry.drag(
            band: current.rawBand,
            part: current.hit.part,
            delta: delta,
            displaySize: displaySize,
            minimumSize: 20
        )
        guard isNormalized(rawCandidate) else { return .none }
        let visibleCandidate = CalibrationGeometry.snap(
            rawBand: rawCandidate,
            activeIndex: current.hit.bandIndex,
            part: current.hit.part,
            bands: workingBands,
            displaySize: displaySize,
            threshold: 12
        )
        guard isNormalized(visibleCandidate) else { return .none }
        current.rawBand = rawCandidate
        current.lastPoint = point
        current.moved = true
        drag = current
        workingBands[current.hit.bandIndex] = visibleCandidate
        return .redraw
    }

    private func isUsable(_ rect: RectD) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private func isFinite(_ point: PointD) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private func isNormalized(_ rect: NormalizedRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.w.isFinite && rect.h.isFinite
            && rect.x >= 0 && rect.y >= 0 && rect.w > 0 && rect.h > 0
            && rect.x + rect.w <= 1 && rect.y + rect.h <= 1
    }
}

private extension RectD {
    func contains(_ point: PointD) -> Bool {
        point.x >= x && point.x <= right && point.y >= y && point.y <= bottom
    }
}
