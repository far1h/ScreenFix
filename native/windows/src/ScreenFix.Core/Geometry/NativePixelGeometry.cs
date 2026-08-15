namespace ScreenFix.Core.Geometry;

public static class NativePixelGeometry
{
    public static IReadOnlyList<RectD> ToNativeBands(
        RectD full,
        IReadOnlyList<RectD> bands)
    {
        ArgumentNullException.ThrowIfNull(bands);
        RequireFullFrame(full);
        foreach (var band in bands)
        {
            RequireNormalizedBand(band);
        }

        return bands.Select(band =>
        {
            var left = Round(full.X + (band.X * full.Width));
            var top = Round(full.Y + (band.Y * full.Height));
            var right = Round(full.X + (band.Right * full.Width));
            var bottom = Round(full.Y + (band.Bottom * full.Height));
            return new RectD(left, top, right - left, bottom - top);
        }).ToArray();
    }

    private static double Round(double value) =>
        Math.Round(value, MidpointRounding.AwayFromZero);

    private static void RequireFullFrame(RectD full)
    {
        if (!IsFinite(full.X) || !IsFinite(full.Y) ||
            !IsFinite(full.Width) || !IsFinite(full.Height) ||
            full.Width <= 0 || full.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(full));
        }
    }

    private static void RequireNormalizedBand(RectD band)
    {
        if (!IsFinite(band.X) || !IsFinite(band.Y) ||
            !IsFinite(band.Width) || !IsFinite(band.Height) ||
            band.X < 0 || band.Y < 0 || band.Width <= 0 || band.Height <= 0 ||
            band.Right > 1 || band.Bottom > 1)
        {
            throw new ArgumentOutOfRangeException(nameof(band));
        }
    }

    private static bool IsFinite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
}
