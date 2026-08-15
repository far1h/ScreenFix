public struct PointD: Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum CalibrationPart: Equatable {
    case body
    case left
    case right
    case top
    case bottom
}

public struct CalibrationHit: Equatable {
    public let bandIndex: Int
    public let part: CalibrationPart

    public init(bandIndex: Int, part: CalibrationPart) {
        self.bandIndex = bandIndex
        self.part = part
    }
}

public enum CalibrationGeometry {
    private static let toleranceFactor = Double(sign: .plus, exponent: -48, significand: 1)

    private enum Axis {
        case horizontal
        case vertical
    }

    private enum Edge {
        case leading
        case trailing
    }

    public static func hitTest(
        point: PointD,
        frames: [RectD],
        handleSize: Double
    ) -> CalibrationHit? {
        guard point.x.isFinite, point.y.isFinite, handleSize.isFinite, handleSize >= 0 else {
            return nil
        }
        for index in frames.indices.reversed() {
            let frame = frames[index]
            guard isFinite(frame), frame.width >= 0, frame.height >= 0 else { continue }
            let withinWidth = point.x >= frame.x && point.x <= frame.right
            let withinHeight = point.y >= frame.y && point.y <= frame.bottom
            if withinWidth, abs(point.y - frame.bottom) <= handleSize {
                return CalibrationHit(bandIndex: index, part: .bottom)
            }
            if withinWidth, abs(point.y - frame.y) <= handleSize {
                return CalibrationHit(bandIndex: index, part: .top)
            }
            if withinHeight, abs(point.x - frame.right) <= handleSize {
                return CalibrationHit(bandIndex: index, part: .right)
            }
            if withinHeight, abs(point.x - frame.x) <= handleSize {
                return CalibrationHit(bandIndex: index, part: .left)
            }
        }
        for index in frames.indices.reversed() {
            let frame = frames[index]
            guard isFinite(frame), frame.width >= 0, frame.height >= 0 else { continue }
            if point.x >= frame.x, point.x <= frame.right,
               point.y >= frame.y, point.y <= frame.bottom {
                return CalibrationHit(bandIndex: index, part: .body)
            }
        }
        return nil
    }

    public static func drag(
        band: NormalizedRect,
        part: CalibrationPart,
        delta: PointD,
        displaySize: RectD,
        minimumSize: Double
    ) -> NormalizedRect {
        guard isFinite(band), isFinite(displaySize),
              displaySize.width > 0, displaySize.height > 0,
              delta.x.isFinite, delta.y.isFinite,
              minimumSize.isFinite, minimumSize >= 0 else {
            return band
        }

        var x = band.x
        var y = band.y
        var width = band.w
        var height = band.h
        switch part {
        case .body:
            x = clamp(x + delta.x / displaySize.width, minimum: 0, maximum: 1 - width)
            y = clamp(y + delta.y / displaySize.height, minimum: 0, maximum: 1 - height)
        case .left:
            let fixedRight = x + width
            x = clampEdge(
                current: x,
                delta: delta.x / displaySize.width,
                minimum: 0,
                maximum: max(0, fixedRight - minimumSize / displaySize.width)
            )
            width = fixedRight - x
        case .right:
            let right = clampEdge(
                current: x + width,
                delta: delta.x / displaySize.width,
                minimum: min(1, x + minimumSize / displaySize.width),
                maximum: 1
            )
            width = right - x
        case .top:
            let fixedBottom = y + height
            y = clampEdge(
                current: y,
                delta: delta.y / displaySize.height,
                minimum: 0,
                maximum: max(0, fixedBottom - minimumSize / displaySize.height)
            )
            height = fixedBottom - y
        case .bottom:
            let bottom = clampEdge(
                current: y + height,
                delta: delta.y / displaySize.height,
                minimum: min(1, y + minimumSize / displaySize.height),
                maximum: 1
            )
            height = bottom - y
        }
        return NormalizedRect(x: x, y: y, w: width, h: height)
    }

    public static func snap(
        rawBand: NormalizedRect,
        activeIndex: Int,
        part: CalibrationPart,
        bands: [NormalizedRect],
        displaySize: RectD,
        threshold: Double
    ) -> NormalizedRect {
        guard isNormalized(rawBand), bands.indices.contains(activeIndex),
              isFinite(displaySize), displaySize.width > 0, displaySize.height > 0,
              threshold.isFinite, threshold >= 0 else {
            return rawBand
        }

        switch part {
        case .body:
            let horizontalTargets = targets(
                axis: .horizontal,
                screenTargets: [0, 1],
                bands: bands,
                activeIndex: activeIndex
            )
            let verticalTargets = targets(
                axis: .vertical,
                screenTargets: [0, 1],
                bands: bands,
                activeIndex: activeIndex
            )
            let horizontallySnapped = snapAxis(
                rawBand,
                axis: .horizontal,
                edges: [.leading, .trailing],
                targets: horizontalTargets,
                threshold: threshold,
                displaySize: displaySize,
                part: part,
                resizeEdge: nil
            )
            return snapAxis(
                horizontallySnapped,
                axis: .vertical,
                edges: [.leading, .trailing],
                targets: verticalTargets,
                threshold: threshold,
                displaySize: displaySize,
                part: part,
                resizeEdge: nil
            )
        case .left:
            return snapResize(
                rawBand,
                axis: .horizontal,
                edge: .leading,
                screenTarget: 0,
                activeIndex: activeIndex,
                part: part,
                bands: bands,
                displaySize: displaySize,
                threshold: threshold
            )
        case .right:
            return snapResize(
                rawBand,
                axis: .horizontal,
                edge: .trailing,
                screenTarget: 1,
                activeIndex: activeIndex,
                part: part,
                bands: bands,
                displaySize: displaySize,
                threshold: threshold
            )
        case .top:
            return snapResize(
                rawBand,
                axis: .vertical,
                edge: .leading,
                screenTarget: 0,
                activeIndex: activeIndex,
                part: part,
                bands: bands,
                displaySize: displaySize,
                threshold: threshold
            )
        case .bottom:
            return snapResize(
                rawBand,
                axis: .vertical,
                edge: .trailing,
                screenTarget: 1,
                activeIndex: activeIndex,
                part: part,
                bands: bands,
                displaySize: displaySize,
                threshold: threshold
            )
        }
    }

    private static func snapResize(
        _ band: NormalizedRect,
        axis: Axis,
        edge: Edge,
        screenTarget: Double,
        activeIndex: Int,
        part: CalibrationPart,
        bands: [NormalizedRect],
        displaySize: RectD,
        threshold: Double
    ) -> NormalizedRect {
        snapAxis(
            band,
            axis: axis,
            edges: [edge],
            targets: targets(
                axis: axis,
                screenTargets: [screenTarget],
                bands: bands,
                activeIndex: activeIndex
            ),
            threshold: threshold,
            displaySize: displaySize,
            part: part,
            resizeEdge: edge
        )
    }

    private static func snapAxis(
        _ band: NormalizedRect,
        axis: Axis,
        edges: [Edge],
        targets: [Double],
        threshold: Double,
        displaySize: RectD,
        part: CalibrationPart,
        resizeEdge: Edge?
    ) -> NormalizedRect {
        let pointScale = axis == .horizontal ? displaySize.width : displaySize.height
        let tolerance = pointScale * toleranceFactor
        var best: NormalizedRect?
        var bestDistance: Double?
        for target in targets {
            for edge in edges {
                let leading = axis == .horizontal ? band.x : band.y
                let size = axis == .horizontal ? band.w : band.h
                let edgePosition = edge == .leading ? leading : leading + size
                let distance = abs(target - edgePosition) * pointScale
                let candidate = corrected(
                    band,
                    axis: axis,
                    edge: edge,
                    target: target,
                    resizeEdge: resizeEdge
                )
                if distance <= threshold + tolerance,
                   isLegalSnap(candidate, displaySize: displaySize, part: part),
                   bestDistance == nil || distance < bestDistance! - tolerance {
                    best = candidate
                    bestDistance = distance
                }
            }
        }
        return best ?? band
    }

    private static func targets(
        axis: Axis,
        screenTargets: [Double],
        bands: [NormalizedRect],
        activeIndex: Int
    ) -> [Double] {
        var result = screenTargets
        for index in bands.indices where index != activeIndex {
            let band = bands[index]
            guard isNormalized(band) else { continue }
            let leading = axis == .horizontal ? band.x : band.y
            let size = axis == .horizontal ? band.w : band.h
            result.append(leading)
            result.append(leading + size)
        }
        return result
    }

    private static func corrected(
        _ band: NormalizedRect,
        axis: Axis,
        edge: Edge,
        target: Double,
        resizeEdge: Edge?
    ) -> NormalizedRect {
        var position = axis == .horizontal ? band.x : band.y
        var size = axis == .horizontal ? band.w : band.h
        if resizeEdge == .leading {
            let fixedEnd = position + size
            position = target
            size = fixedEnd - target
        } else if resizeEdge == .trailing {
            size = target - position
        } else if edge == .leading {
            position = target
        } else {
            position = target - size
        }
        if axis == .horizontal {
            return NormalizedRect(x: position, y: band.y, w: size, h: band.h)
        }
        return NormalizedRect(x: band.x, y: position, w: band.w, h: size)
    }

    private static func isLegalSnap(
        _ band: NormalizedRect,
        displaySize: RectD,
        part: CalibrationPart
    ) -> Bool {
        guard isWithinBounds(band) else { return false }
        switch part {
        case .left, .right:
            return band.w * displaySize.width + displaySize.width * toleranceFactor >= 20
        case .top, .bottom:
            return band.h * displaySize.height + displaySize.height * toleranceFactor >= 20
        case .body:
            return true
        }
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        max(minimum, min(value, maximum))
    }

    private static func clampEdge(
        current: Double,
        delta: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        if current < minimum, delta <= 0 { return current }
        if current > maximum, delta >= 0 { return current }
        return clamp(current + delta, minimum: minimum, maximum: maximum)
    }

    private static func isFinite(_ rect: RectD) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    private static func isFinite(_ rect: NormalizedRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.w.isFinite && rect.h.isFinite
    }

    private static func isNormalized(_ rect: NormalizedRect) -> Bool {
        isFinite(rect) && rect.w > 0 && rect.h > 0 && isWithinBounds(rect)
    }

    private static func isWithinBounds(_ rect: NormalizedRect) -> Bool {
        isFinite(rect) && rect.x >= 0 && rect.y >= 0 && rect.w >= 0 && rect.h >= 0
            && rect.x + rect.w <= 1 && rect.y + rect.h <= 1
    }
}
