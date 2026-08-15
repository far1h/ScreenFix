public enum MaskGeometry {
    public static func localFrames(
        bands: [NormalizedRect],
        displayWidth: Double,
        displayHeight: Double
    ) -> [RectD] {
        bands.map { band in
            RectD(
                x: band.x * displayWidth,
                y: band.y * displayHeight,
                width: band.w * displayWidth,
                height: band.h * displayHeight
            )
        }
    }

    public static func absoluteTopLeftFrames(
        bands: [NormalizedRect],
        in bounds: TopLeftDisplayBounds
    ) -> [RectD] {
        localFrames(
            bands: bands,
            displayWidth: bounds.width,
            displayHeight: bounds.height
        ).map { frame in
            RectD(
                x: bounds.x + frame.x,
                y: bounds.y + frame.y,
                width: frame.width,
                height: frame.height
            )
        }
    }
}
