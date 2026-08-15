using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class RectDTests
{
    [Fact]
    public void Intersects_TreatsRectanglesAsHalfOpen()
    {
        Assert.False(new RectD(0, 0, 10, 10).Intersects(new RectD(10, 0, 5, 5)));
        Assert.True(new RectD(0, 0, 10, 10).Intersects(new RectD(9, 9, 5, 5)));
    }

    [Fact]
    public void ToAbsolute_AddsNegativeDisplayOrigin()
    {
        var normalized = new RectD(0.25, 0.5, 0.5, 0.25);
        var display = new RectD(-1920, 0, 1920, 1080);

        Assert.Equal(new RectD(-1440, 540, 960, 270), normalized.ToAbsolute(display));
    }
}
