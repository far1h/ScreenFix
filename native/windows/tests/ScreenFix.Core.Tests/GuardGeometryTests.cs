using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class GuardGeometryTests
{
    [Fact]
    public void CorrectedFrame_ReturnsNullWithoutIntersection()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(0, 100, 300, 400),
            new RectD(0, 0, 1200, 800),
            [new RectD(400, 0, 300, 800)]);

        Assert.Null(result);
    }

    [Theory]
    [InlineData(50)]
    [InlineData(350)]
    [InlineData(650)]
    public void CorrectedFrame_CorrectsTopMiddleAndLowerIntersections(double y)
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(450, y, 100, 100),
            new RectD(0, 0, 1000, 800),
            [new RectD(400, y, 200, 100)]);

        Assert.Equal(new RectD(300, y, 100, 100), result);
    }

    [Fact]
    public void CorrectedFrame_CombinesBandsCrossedByTallWindow()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(350, 100, 500, 600),
            new RectD(0, 0, 1200, 800),
            [new RectD(400, 0, 100, 300), new RectD(600, 500, 100, 300)]);

        Assert.Equal(new RectD(700, 100, 500, 600), result);
    }

    [Fact]
    public void CorrectedFrame_ChoosesNearestLeftCandidate()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(-700, 100, 1400, 700),
            new RectD(-951, 25, 3440, 1415),
            [new RectD(214, 0, 755, 1440)]);

        Assert.Equal(new RectD(-951, 100, 1165, 700), result);
    }

    [Fact]
    public void CorrectedFrame_ChoosesNearestRightCandidate()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(700, 100, 1400, 700),
            new RectD(-951, 25, 3440, 1415),
            [new RectD(214, 0, 755, 1440)]);

        Assert.Equal(new RectD(969, 100, 1400, 700), result);
    }

    [Fact]
    public void CorrectedFrame_PrefersMovementBeforeSizeReduction()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(100, 100, 500, 300),
            new RectD(0, 0, 1000, 800),
            [new RectD(200, 0, 400, 800)]);

        Assert.Equal(new RectD(0, 100, 200, 300), result);
    }

    [Fact]
    public void CorrectedFrame_ChoosesLeftOnExactTie()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(350, 100, 300, 400),
            new RectD(0, 0, 1000, 800),
            [new RectD(400, 0, 200, 800)]);

        Assert.Equal(new RectD(100, 100, 300, 400), result);
    }

    [Fact]
    public void CorrectedFrame_ClampsOversizedWidthAndHeight()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(300, -100, 1000, 1000),
            new RectD(0, 0, 1200, 800),
            [new RectD(400, 0, 300, 800)]);

        Assert.Equal(new RectD(0, 0, 400, 800), result);
    }

    [Fact]
    public void CorrectedFrame_PreservesNegativeWorkAreaCoordinates()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(-850, 100, 500, 400),
            new RectD(-1200, 0, 1200, 800),
            [new RectD(-800, 0, 300, 800)]);

        Assert.Equal(new RectD(-500, 100, 500, 400), result);
    }

    [Fact]
    public void CorrectedFrame_ReturnsNullWhenNoSafeCandidateExists()
    {
        var result = GuardGeometry.CorrectedFrame(
            new RectD(100, 100, 500, 400),
            new RectD(0, 0, 1200, 800),
            [new RectD(0, 0, 1200, 800)]);

        Assert.Null(result);
    }
}
