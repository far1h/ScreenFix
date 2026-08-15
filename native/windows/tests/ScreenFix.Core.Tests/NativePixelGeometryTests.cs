using ScreenFix.Core.Configuration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class NativePixelGeometryTests
{
    [Fact]
    public void ToNativeBands_RoundsDefaultEdgesSeparatelyOnNegativeOriginDisplay()
    {
        var display = new DisplayIdentity("display", "Ultrawide", 3440, 1440);
        var bands = DefaultConfiguration.Create(display).Bands;

        var native = NativePixelGeometry.ToNativeBands(
            new RectD(-3440, -200, 3440, 1440),
            bands);

        Assert.All(native, band => Assert.Equal(-2225, band.X));
        Assert.All(native, band => Assert.Equal(-1520, band.Right));
        Assert.Equal(native[0].Bottom, native[1].Y);
        Assert.Equal(native[1].Bottom, native[2].Y);
        Assert.Equal(-200, native[0].Y);
        Assert.Equal(1240, native[2].Bottom);
        Assert.All(native, band =>
        {
            Assert.InRange(band.X, -3440, 0);
            Assert.InRange(band.Right, -3440, 0);
            Assert.InRange(band.Y, -200, 1240);
            Assert.InRange(band.Bottom, -200, 1240);
        });
    }

    [Fact]
    public void ToNativeBands_RoundsHalfAwayFromZeroAtPositiveAndNegativeOrigins()
    {
        var band = new RectD(1d / 6d, 1d / 6d, 2d / 3d, 2d / 3d);

        var positive = NativePixelGeometry.ToNativeBands(new RectD(0, 0, 3, 3), [band]);
        var negative = NativePixelGeometry.ToNativeBands(new RectD(-3, -3, 3, 3), [band]);

        Assert.Equal(new RectD(1, 1, 2, 2), positive[0]);
        Assert.Equal(new RectD(-3, -3, 2, 2), negative[0]);
    }

    [Fact]
    public void ToNativeBands_RejectsEveryBandBeforeReturningAResult()
    {
        RectD[] bands =
        [
            new RectD(0, 0, 0.5, 0.5),
            new RectD(0.5, 0.5, double.NaN, 0.5),
        ];

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            NativePixelGeometry.ToNativeBands(new RectD(0, 0, 100, 100), bands));
    }

    [Fact]
    public void ToNativeBands_RejectsInvalidFullFrame()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            NativePixelGeometry.ToNativeBands(
                new RectD(0, 0, double.PositiveInfinity, 100),
                [new RectD(0, 0, 0.5, 0.5)]));
    }
}
