namespace ScreenFix.Core.Geometry;

public enum DragPart
{
    Body,
    Left,
    Right,
    Top,
    Bottom,
}

public readonly record struct PointD(double X, double Y);

public readonly record struct EditorHit(int Index, DragPart Part);

public static class CalibrationGeometry
{
    private const double PointToleranceFactor = 3.552713678800501e-15;

    public static EditorHit? HitTest(
        PointD point,
        IReadOnlyList<RectD> localBands,
        double handleSize)
    {
        ArgumentNullException.ThrowIfNull(localBands);
        RequireFinite(point.X, nameof(point));
        RequireFinite(point.Y, nameof(point));
        RequirePositiveFinite(handleSize, nameof(handleSize));

        for (var index = localBands.Count - 1; index >= 0; index--)
        {
            var band = localBands[index];
            RequirePositiveRect(band, nameof(localBands));
            var withinHeight = point.Y >= band.Y && point.Y <= band.Bottom;
            var withinWidth = point.X >= band.X && point.X <= band.Right;

            if (withinWidth && Math.Abs(point.Y - band.Bottom) <= handleSize)
            {
                return new EditorHit(index, DragPart.Bottom);
            }

            if (withinWidth && Math.Abs(point.Y - band.Y) <= handleSize)
            {
                return new EditorHit(index, DragPart.Top);
            }

            if (withinHeight && Math.Abs(point.X - band.Right) <= handleSize)
            {
                return new EditorHit(index, DragPart.Right);
            }

            if (withinHeight && Math.Abs(point.X - band.X) <= handleSize)
            {
                return new EditorHit(index, DragPart.Left);
            }
        }

        for (var index = localBands.Count - 1; index >= 0; index--)
        {
            var band = localBands[index];
            if (point.X >= band.X && point.X <= band.Right &&
                point.Y >= band.Y && point.Y <= band.Bottom)
            {
                return new EditorHit(index, DragPart.Body);
            }
        }

        return null;
    }

    public static RectD DragBand(
        RectD normalizedBand,
        DragPart part,
        PointD localDelta,
        RectD fullFrame,
        double minimumSize)
    {
        RequireNormalizedRect(normalizedBand, nameof(normalizedBand));
        RequireFullFrame(fullFrame);
        RequireFinite(localDelta.X, nameof(localDelta));
        RequireFinite(localDelta.Y, nameof(localDelta));
        RequirePositiveFinite(minimumSize, nameof(minimumSize));

        var deltaX = localDelta.X / fullFrame.Width;
        var deltaY = localDelta.Y / fullFrame.Height;
        var minimumWidth = minimumSize / fullFrame.Width;
        var minimumHeight = minimumSize / fullFrame.Height;

        return part switch
        {
            DragPart.Body => MoveBody(normalizedBand, deltaX, deltaY),
            DragPart.Left => ResizeLeft(normalizedBand, deltaX, minimumWidth),
            DragPart.Right => ResizeRight(normalizedBand, deltaX, minimumWidth),
            DragPart.Top => ResizeTop(normalizedBand, deltaY, minimumHeight),
            DragPart.Bottom => ResizeBottom(normalizedBand, deltaY, minimumHeight),
            _ => throw new ArgumentOutOfRangeException(nameof(part)),
        };
    }

    public static RectD SnapBand(
        RectD rawBand,
        int activeIndex,
        DragPart part,
        IReadOnlyList<RectD> bands,
        RectD fullFrame,
        double threshold,
        double minimumSize)
    {
        ArgumentNullException.ThrowIfNull(bands);
        RequireNormalizedRect(rawBand, nameof(rawBand));
        RequireFullFrame(fullFrame);
        RequireFinite(threshold, nameof(threshold));
        RequirePositiveFinite(minimumSize, nameof(minimumSize));
        if (threshold < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(threshold));
        }

        if (activeIndex < 0 || activeIndex >= bands.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(activeIndex));
        }

        return part switch
        {
            DragPart.Body => SnapBody(rawBand, activeIndex, bands, fullFrame, threshold),
            DragPart.Left => SnapAxis(
                rawBand,
                horizontal: true,
                leadingEdges: true,
                trailingEdges: false,
                BuildTargets(horizontal: true, [0], bands, activeIndex),
                threshold,
                fullFrame,
                DragPart.Left,
                minimumSize),
            DragPart.Right => SnapAxis(
                rawBand,
                horizontal: true,
                leadingEdges: false,
                trailingEdges: true,
                BuildTargets(horizontal: true, [1], bands, activeIndex),
                threshold,
                fullFrame,
                DragPart.Right,
                minimumSize),
            DragPart.Top => SnapAxis(
                rawBand,
                horizontal: false,
                leadingEdges: true,
                trailingEdges: false,
                BuildTargets(horizontal: false, [0], bands, activeIndex),
                threshold,
                fullFrame,
                DragPart.Top,
                minimumSize),
            DragPart.Bottom => SnapAxis(
                rawBand,
                horizontal: false,
                leadingEdges: false,
                trailingEdges: true,
                BuildTargets(horizontal: false, [1], bands, activeIndex),
                threshold,
                fullFrame,
                DragPart.Bottom,
                minimumSize),
            _ => throw new ArgumentOutOfRangeException(nameof(part)),
        };
    }

    private static RectD SnapBody(
        RectD rawBand,
        int activeIndex,
        IReadOnlyList<RectD> bands,
        RectD fullFrame,
        double threshold)
    {
        var result = SnapAxis(
            rawBand,
            horizontal: true,
            leadingEdges: true,
            trailingEdges: true,
            BuildTargets(horizontal: true, [0, 1], bands, activeIndex),
            threshold,
            fullFrame,
            null,
            null);

        return SnapAxis(
            result,
            horizontal: false,
            leadingEdges: true,
            trailingEdges: true,
            BuildTargets(horizontal: false, [0, 1], bands, activeIndex),
            threshold,
            fullFrame,
            null,
            null);
    }

    private static RectD SnapAxis(
        RectD rect,
        bool horizontal,
        bool leadingEdges,
        bool trailingEdges,
        IReadOnlyList<double> targets,
        double threshold,
        RectD fullFrame,
        DragPart? resizePart,
        double? minimumSize)
    {
        var pointScale = horizontal ? fullFrame.Width : fullFrame.Height;
        var tolerance = pointScale * PointToleranceFactor;
        RectD? best = null;
        double? bestDistance = null;

        foreach (var target in targets)
        {
            if (leadingEdges)
            {
                ConsiderSnap(target, trailing: false);
            }

            if (trailingEdges)
            {
                ConsiderSnap(target, trailing: true);
            }
        }

        return best ?? rect;

        void ConsiderSnap(double target, bool trailing)
        {
            var leading = horizontal ? rect.X : rect.Y;
            var size = horizontal ? rect.Width : rect.Height;
            var edge = trailing ? leading + size : leading;
            var distance = Math.Abs(target - edge) * pointScale;
            var candidate = CorrectedRect(rect, horizontal, trailing, target, resizePart);

            if (distance <= threshold + tolerance &&
                IsSnapCandidate(candidate, fullFrame, tolerance, minimumSize) &&
                (bestDistance is null || distance < bestDistance.Value - tolerance))
            {
                best = candidate;
                bestDistance = distance;
            }
        }
    }

    private static IReadOnlyList<double> BuildTargets(
        bool horizontal,
        IReadOnlyList<double> screenTargets,
        IReadOnlyList<RectD> bands,
        int activeIndex)
    {
        var targets = new List<double>(screenTargets);
        for (var index = 0; index < bands.Count; index++)
        {
            if (index == activeIndex || !IsNormalizedRect(bands[index]))
            {
                continue;
            }

            var band = bands[index];
            targets.Add(horizontal ? band.X : band.Y);
            targets.Add(horizontal ? band.Right : band.Bottom);
        }

        return targets;
    }

    private static RectD CorrectedRect(
        RectD rect,
        bool horizontal,
        bool trailing,
        double target,
        DragPart? resizePart)
    {
        if (horizontal)
        {
            if (resizePart == DragPart.Left)
            {
                return new RectD(target, rect.Y, rect.Right - target, rect.Height);
            }

            if (resizePart == DragPart.Right)
            {
                return new RectD(rect.X, rect.Y, target - rect.X, rect.Height);
            }

            return new RectD(
                trailing ? target - rect.Width : target,
                rect.Y,
                rect.Width,
                rect.Height);
        }

        if (resizePart == DragPart.Top)
        {
            return new RectD(rect.X, target, rect.Width, rect.Bottom - target);
        }

        if (resizePart == DragPart.Bottom)
        {
            return new RectD(rect.X, rect.Y, rect.Width, target - rect.Y);
        }

        return new RectD(
            rect.X,
            trailing ? target - rect.Height : target,
            rect.Width,
            rect.Height);
    }

    private static RectD MoveBody(RectD band, double deltaX, double deltaY) => new(
        Math.Clamp(band.X + deltaX, 0, 1 - band.Width),
        Math.Clamp(band.Y + deltaY, 0, 1 - band.Height),
        band.Width,
        band.Height);

    private static RectD ResizeLeft(RectD band, double delta, double minimumWidth)
    {
        var right = band.Right;
        var left = Math.Clamp(band.X + delta, 0, Math.Max(0, right - minimumWidth));
        return new RectD(left, band.Y, right - left, band.Height);
    }

    private static RectD ResizeRight(RectD band, double delta, double minimumWidth)
    {
        var right = Math.Clamp(band.Right + delta, Math.Min(1, band.X + minimumWidth), 1);
        return new RectD(band.X, band.Y, right - band.X, band.Height);
    }

    private static RectD ResizeTop(RectD band, double delta, double minimumHeight)
    {
        var bottom = band.Bottom;
        var top = Math.Clamp(band.Y + delta, 0, Math.Max(0, bottom - minimumHeight));
        return new RectD(band.X, top, band.Width, bottom - top);
    }

    private static RectD ResizeBottom(RectD band, double delta, double minimumHeight)
    {
        var bottom = Math.Clamp(band.Bottom + delta, Math.Min(1, band.Y + minimumHeight), 1);
        return new RectD(band.X, band.Y, band.Width, bottom - band.Y);
    }

    private static bool IsSnapCandidate(
        RectD rect,
        RectD fullFrame,
        double tolerance,
        double? minimumSize) =>
        IsNormalizedRect(rect) &&
        (minimumSize is null ||
            ((rect.Width * fullFrame.Width) + tolerance >= minimumSize.Value &&
             (rect.Height * fullFrame.Height) + tolerance >= minimumSize.Value));

    private static bool IsNormalizedRect(RectD rect) =>
        IsFiniteRect(rect) &&
        rect.X >= 0 &&
        rect.Y >= 0 &&
        rect.Width > 0 &&
        rect.Height > 0 &&
        rect.Right <= 1 &&
        rect.Bottom <= 1;

    private static void RequireNormalizedRect(RectD rect, string parameterName)
    {
        if (!IsNormalizedRect(rect))
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequirePositiveRect(RectD rect, string parameterName)
    {
        if (!IsFiniteRect(rect) || rect.Width <= 0 || rect.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequireFullFrame(RectD fullFrame)
    {
        if (!IsFiniteRect(fullFrame) || fullFrame.Width <= 0 || fullFrame.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(fullFrame));
        }
    }

    private static bool IsFiniteRect(RectD rect) =>
        double.IsFinite(rect.X) &&
        double.IsFinite(rect.Y) &&
        double.IsFinite(rect.Width) &&
        double.IsFinite(rect.Height);

    private static void RequireFinite(double value, string parameterName)
    {
        if (!double.IsFinite(value))
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequirePositiveFinite(double value, string parameterName)
    {
        RequireFinite(value, parameterName);
        if (value <= 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
}
