using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Configuration;

public static class DefaultConfiguration
{
    public static ScreenFixConfig Create(DisplayIdentity display)
    {
        ArgumentNullException.ThrowIfNull(display);

        var left = 1215d / 3440d;
        var width = (1920d - 1215d) / 3440d;
        RectD[] bands =
        [
            new(left, 0, width, 0.34),
            new(left, 0.34, width, 0.39),
            new(left, 0.73, width, 0.27),
        ];

        return new ScreenFixConfig(1, true, display, bands);
    }
}
