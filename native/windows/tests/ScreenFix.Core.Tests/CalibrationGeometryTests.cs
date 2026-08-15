using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class CalibrationGeometryTests
{
    private static readonly RectD FullFrame = new(0, 0, 100, 100);

    [Fact]
    public void HitTest_PrefersLaterBandWhenBodiesOverlap()
    {
        RectD[] bands = [new(0, 0, 60, 60), new(20, 20, 60, 60)];

        var hit = CalibrationGeometry.HitTest(new PointD(40, 40), bands, 8);

        Assert.Equal(new EditorHit(1, DragPart.Body), hit);
    }

    [Theory]
    [InlineData(28, 50, DragPart.Left)]
    [InlineData(72, 50, DragPart.Right)]
    [InlineData(50, 28, DragPart.Top)]
    [InlineData(50, 72, DragPart.Bottom)]
    public void HitTest_PrefersEdgesOverBody(double x, double y, DragPart expected)
    {
        var hit = CalibrationGeometry.HitTest(
            new PointD(x, y),
            [new RectD(20, 20, 60, 60)],
            8);

        Assert.Equal(new EditorHit(0, expected), hit);
    }

    [Theory]
    [InlineData(-100, 0, 0, 0.4)]
    [InlineData(100, 0, 0.8, 0.4)]
    [InlineData(0, -100, 0.4, 0)]
    [InlineData(0, 100, 0.4, 0.8)]
    public void DragBand_BodyClampsInsideDisplay(
        double deltaX,
        double deltaY,
        double expectedX,
        double expectedY)
    {
        var result = CalibrationGeometry.DragBand(
            new RectD(0.4, 0.4, 0.2, 0.2),
            DragPart.Body,
            new PointD(deltaX, deltaY),
            FullFrame,
            20);

        AssertRect(new RectD(expectedX, expectedY, 0.2, 0.2), result);
    }

    [Theory]
    [InlineData(DragPart.Left, 10, 0, 0.3, 0.2, 0.3, 0.4)]
    [InlineData(DragPart.Right, -10, 0, 0.2, 0.2, 0.3, 0.4)]
    [InlineData(DragPart.Top, 0, 10, 0.2, 0.3, 0.4, 0.3)]
    [InlineData(DragPart.Bottom, 0, -10, 0.2, 0.2, 0.4, 0.3)]
    public void DragBand_ResizeKeepsOppositeEdgeFixed(
        DragPart part,
        double deltaX,
        double deltaY,
        double x,
        double y,
        double width,
        double height)
    {
        var result = CalibrationGeometry.DragBand(
            new RectD(0.2, 0.2, 0.4, 0.4),
            part,
            new PointD(deltaX, deltaY),
            FullFrame,
            20);

        AssertRect(new RectD(x, y, width, height), result);
    }

    [Theory]
    [InlineData(DragPart.Left, 100, 0, 0.4, 0.2, 0.2, 0.4)]
    [InlineData(DragPart.Right, -100, 0, 0.2, 0.2, 0.2, 0.4)]
    [InlineData(DragPart.Top, 0, 100, 0.2, 0.4, 0.4, 0.2)]
    [InlineData(DragPart.Bottom, 0, -100, 0.2, 0.2, 0.4, 0.2)]
    public void DragBand_ResizeEnforcesMinimumSize(
        DragPart part,
        double deltaX,
        double deltaY,
        double x,
        double y,
        double width,
        double height)
    {
        var result = CalibrationGeometry.DragBand(
            new RectD(0.2, 0.2, 0.4, 0.4),
            part,
            new PointD(deltaX, deltaY),
            FullFrame,
            20);

        AssertRect(new RectD(x, y, width, height), result);
    }

    [Theory]
    [InlineData(0.1, 0.4, 0.2, 0.2, 0, 0.4)]
    [InlineData(0.71, 0.4, 0.2, 0.2, 0.8, 0.4)]
    [InlineData(0.4, 0.1, 0.2, 0.2, 0.4, 0)]
    [InlineData(0.4, 0.71, 0.2, 0.2, 0.4, 0.8)]
    public void SnapBand_BodySnapsToEachScreenEdge(
        double x,
        double y,
        double width,
        double height,
        double expectedX,
        double expectedY)
    {
        var raw = new RectD(x, y, width, height);

        var result = CalibrationGeometry.SnapBand(raw, 0, DragPart.Body, [raw], FullFrame, 12);

        AssertRect(new RectD(expectedX, expectedY, width, height), result);
    }

    [Theory]
    [InlineData(0.31, 0.4, 0.2, 0.2, 0.3, 0, 0.3, 0.4)]
    [InlineData(0.29, 0.4, 0.2, 0.2, 0.3, 0, 0.3, 0.4)]
    [InlineData(0.4, 0.31, 0.2, 0.2, 0, 0.3, 0.4, 0.3)]
    [InlineData(0.4, 0.29, 0.2, 0.2, 0, 0.3, 0.4, 0.3)]
    public void SnapBand_BodySnapsEachEdgeToCorrespondingPeerEdge(
        double x,
        double y,
        double width,
        double height,
        double peerX,
        double peerY,
        double expectedX,
        double expectedY)
    {
        var raw = new RectD(x, y, width, height);
        RectD[] bands = [raw, new RectD(peerX, peerY, 0.2, 0.2)];

        var result = CalibrationGeometry.SnapBand(raw, 0, DragPart.Body, bands, FullFrame, 12);

        AssertRect(new RectD(expectedX, expectedY, width, height), result);
    }

    [Theory]
    [InlineData(DragPart.Left, 0.31, 0.2, 0.29, 0.4, 0.3, 0.2, 0.3, 0.4)]
    [InlineData(DragPart.Right, 0.2, 0.2, 0.29, 0.4, 0.2, 0.2, 0.3, 0.4)]
    [InlineData(DragPart.Top, 0.2, 0.31, 0.4, 0.29, 0.2, 0.3, 0.4, 0.3)]
    [InlineData(DragPart.Bottom, 0.2, 0.2, 0.4, 0.29, 0.2, 0.2, 0.4, 0.3)]
    public void SnapBand_ResizeSnapsEachEdgeToCorrespondingPeerEdge(
        DragPart part,
        double x,
        double y,
        double width,
        double height,
        double expectedX,
        double expectedY,
        double expectedWidth,
        double expectedHeight)
    {
        var raw = new RectD(x, y, width, height);
        RectD[] bands = [raw, new RectD(0.3, 0.3, 0.2, 0.2)];

        var result = CalibrationGeometry.SnapBand(raw, 0, part, bands, FullFrame, 12);

        AssertRect(new RectD(expectedX, expectedY, expectedWidth, expectedHeight), result);
    }

    [Fact]
    public void SnapBand_SnapsAtInclusiveThreshold()
    {
        var raw = new RectD(0.12, 0.4, 0.2, 0.2);

        var result = CalibrationGeometry.SnapBand(raw, 0, DragPart.Body, [raw], FullFrame, 12);

        AssertRect(new RectD(0, 0.4, 0.2, 0.2), result);
    }

    [Fact]
    public void SnapBand_DoesNotSnapBeyondThreshold()
    {
        var raw = new RectD(0.12001, 0.4, 0.2, 0.2);

        var result = CalibrationGeometry.SnapBand(raw, 0, DragPart.Body, [raw], FullFrame, 12);

        AssertRect(raw, result);
    }

    [Fact]
    public void SnapBand_ScreenEdgeWinsEqualDistanceTie()
    {
        var raw = new RectD(0.1, 0.4, 0.2, 0.2);
        RectD[] bands = [raw, new RectD(0.2, 0, 0.2, 0.2)];

        var result = CalibrationGeometry.SnapBand(raw, 0, DragPart.Body, bands, FullFrame, 12);

        AssertRect(new RectD(0, 0.4, 0.2, 0.2), result);
    }

    [Fact]
    public void SnapBand_LowerPeerIndexWinsEqualDistanceTie()
    {
        var raw = new RectD(0.4, 0.4, 0.2, 0.2);
        RectD[] bands =
        [
            new RectD(0.3, 0, 0.5, 0.2),
            new RectD(0.5, 0.8, 0.4, 0.1),
            raw,
        ];

        var result = CalibrationGeometry.SnapBand(raw, 2, DragPart.Body, bands, FullFrame, 12);

        AssertRect(new RectD(0.3, 0.4, 0.2, 0.2), result);
    }

    [Fact]
    public void PublicOperations_RejectNonFiniteInputs()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => CalibrationGeometry.HitTest(
            new PointD(double.NaN, 0),
            [new RectD(0, 0, 10, 10)],
            8));
        Assert.Throws<ArgumentOutOfRangeException>(() => CalibrationGeometry.DragBand(
            new RectD(0, 0, 0.5, 0.5),
            DragPart.Body,
            new PointD(double.PositiveInfinity, 0),
            FullFrame,
            20));
        Assert.Throws<ArgumentOutOfRangeException>(() => CalibrationGeometry.SnapBand(
            new RectD(double.NaN, 0, 0.5, 0.5),
            0,
            DragPart.Body,
            [new RectD(0, 0, 0.5, 0.5)],
            FullFrame,
            12));
    }

    private static void AssertRect(RectD expected, RectD actual)
    {
        Assert.Equal(expected.X, actual.X, 10);
        Assert.Equal(expected.Y, actual.Y, 10);
        Assert.Equal(expected.Width, actual.Width, 10);
        Assert.Equal(expected.Height, actual.Height, 10);
    }
}
