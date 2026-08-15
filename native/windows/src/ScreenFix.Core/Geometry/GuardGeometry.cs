namespace ScreenFix.Core.Geometry;

public static class GuardGeometry
{
    public static RectD? CorrectedFrame(
        RectD windowFrame,
        RectD workArea,
        IReadOnlyList<RectD> maskBands)
    {
        ArgumentNullException.ThrowIfNull(maskBands);

        if (!maskBands.Any(windowFrame.Intersects))
        {
            return null;
        }

        var adjusted = ClampVertically(windowFrame, workArea);
        var overlapping = maskBands.Where(mask => OverlapsVertically(adjusted, mask)).ToArray();
        if (overlapping.Length == 0)
        {
            return adjusted;
        }

        var leftBoundary = overlapping.Min(mask => mask.X);
        var rightBoundary = overlapping.Max(mask => mask.Right);
        var left = BuildCandidate(
            adjusted,
            workArea.X,
            Math.Clamp(leftBoundary, workArea.X, workArea.Right));
        var right = BuildCandidate(
            adjusted,
            Math.Clamp(rightBoundary, workArea.X, workArea.Right),
            workArea.Right);

        return ChooseCandidate(windowFrame, left, right);
    }

    private static RectD ClampVertically(RectD frame, RectD workArea)
    {
        var height = Math.Min(frame.Height, workArea.Height);
        var y = Math.Clamp(frame.Y, workArea.Y, workArea.Bottom - height);
        return new RectD(frame.X, y, frame.Width, height);
    }

    private static bool OverlapsVertically(RectD frame, RectD mask) =>
        frame.Y < mask.Bottom && mask.Y < frame.Bottom;

    private static RectD? BuildCandidate(RectD frame, double regionStart, double regionEnd)
    {
        var regionWidth = regionEnd - regionStart;
        if (regionWidth <= 0)
        {
            return null;
        }

        var width = Math.Min(frame.Width, regionWidth);
        var x = Math.Clamp(frame.X, regionStart, regionEnd - width);
        return new RectD(x, frame.Y, width, frame.Height);
    }

    private static RectD? ChooseCandidate(RectD original, RectD? left, RectD? right)
    {
        if (left is null)
        {
            return right;
        }

        if (right is null)
        {
            return left;
        }

        var leftCost = CandidateCost(original, left.Value, 0);
        var rightCost = CandidateCost(original, right.Value, 1);
        return leftCost.CompareTo(rightCost) < 0 ? left : right;
    }

    private static (double Movement, double Reduction, int SideRank) CandidateCost(
        RectD original,
        RectD candidate,
        int sideRank) =>
        (
            Math.Abs(original.X - candidate.X) + Math.Abs(original.Y - candidate.Y),
            (original.Width - candidate.Width) + (original.Height - candidate.Height),
            sideRank
        );
}
