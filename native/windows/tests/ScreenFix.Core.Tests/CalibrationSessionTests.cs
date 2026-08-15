using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class CalibrationSessionTests
{
    private static readonly RectD FullFrame = new(0, 0, 1000, 800);

    [Fact]
    public void HeldBodyDrag_UsesFourPointThresholdAndIncrementalRawDeltas()
    {
        var session = new CalibrationSession(Bands(), FullFrame);

        Assert.Equal(
            CalibrationAction.AcquireCapture,
            session.PointerDown(new PointD(300, 240), primaryButton: true));
        Assert.Equal(GesturePhase.Pressed, session.Phase);

        Assert.Equal(
            CalibrationAction.None,
            session.PointerMove(new PointD(303, 240), primaryButtonDown: true));
        Assert.Equal(Bands()[0], session.WorkingBands[0]);

        Assert.Equal(
            CalibrationAction.Render,
            session.PointerMove(new PointD(304, 240), primaryButtonDown: true));
        AssertRect(new RectD(0.204, 0.2, 0.2, 0.2), session.WorkingBands[0]);

        Assert.Equal(
            CalibrationAction.Render,
            session.PointerMove(new PointD(310, 240), primaryButtonDown: true));
        AssertRect(new RectD(0.21, 0.2, 0.2, 0.2), session.WorkingBands[0]);

        Assert.Equal(
            CalibrationAction.ReleaseCapture,
            session.PointerUp(new PointD(310, 240), primaryButton: true));
        Assert.Equal(GesturePhase.Idle, session.Phase);
    }

    [Fact]
    public void TapMoveTap_MovesWithoutPressedButtonAndNextTapOnlyDropsLatch()
    {
        var session = new CalibrationSession(Bands(), FullFrame);

        Assert.Equal(
            CalibrationAction.AcquireCapture,
            session.PointerDown(new PointD(300, 240), primaryButton: true));
        Assert.Equal(
            CalibrationAction.KeepCapture,
            session.PointerUp(new PointD(300, 240), primaryButton: true));
        Assert.Equal(GesturePhase.Latched, session.Phase);

        Assert.Equal(
            CalibrationAction.Render,
            session.PointerMove(new PointD(310, 240), primaryButtonDown: false));
        AssertRect(new RectD(0.21, 0.2, 0.2, 0.2), session.WorkingBands[0]);

        var untouchedThird = session.WorkingBands[2];
        Assert.Equal(
            CalibrationAction.ReleaseCapture,
            session.PointerDown(new PointD(800, 560), primaryButton: true));
        Assert.Equal(GesturePhase.Idle, session.Phase);
        Assert.Equal(untouchedThird, session.WorkingBands[2]);
    }

    [Fact]
    public void SnappingUsesVisibleCandidateWhileRawBandReleasesWithoutStickyDrift()
    {
        var session = new CalibrationSession(Bands(), FullFrame);
        session.PointerDown(new PointD(300, 240), primaryButton: true);

        session.PointerMove(new PointD(105, 240), primaryButtonDown: true);

        AssertRect(new RectD(0, 0.2, 0.2, 0.2), session.WorkingBands[0]);

        session.PointerMove(new PointD(125, 240), primaryButtonDown: true);

        AssertRect(new RectD(0.025, 0.2, 0.2, 0.2), session.WorkingBands[0]);
    }

    [Fact]
    public void PeerSnapping_ReleasesFromRawPositionBeyondTwelvePoints()
    {
        RectD[] bands =
        [
            new RectD(0.2, 0.2, 0.2, 0.2),
            new RectD(0.5, 0.5, 0.2, 0.2),
            new RectD(0.75, 0.75, 0.15, 0.15),
        ];
        var session = new CalibrationSession(bands, FullFrame);
        session.PointerDown(new PointD(300, 240), primaryButton: true);

        session.PointerMove(new PointD(395, 240), primaryButtonDown: true);

        AssertRect(new RectD(0.3, 0.2, 0.2, 0.2), session.WorkingBands[0]);

        session.PointerMove(new PointD(415, 240), primaryButtonDown: true);

        AssertRect(new RectD(0.315, 0.2, 0.2, 0.2), session.WorkingBands[0]);
    }

    [Theory]
    [InlineData(DragPart.Body, false)]
    [InlineData(DragPart.Left, false)]
    [InlineData(DragPart.Right, false)]
    [InlineData(DragPart.Top, false)]
    [InlineData(DragPart.Bottom, false)]
    [InlineData(DragPart.Body, true)]
    [InlineData(DragPart.Left, true)]
    [InlineData(DragPart.Right, true)]
    [InlineData(DragPart.Top, true)]
    [InlineData(DragPart.Bottom, true)]
    public void HeldAndLatchedGestures_MoveBodyAndEveryResizeEdge(
        DragPart part,
        bool latched)
    {
        var session = new CalibrationSession(Bands(), FullFrame);
        var start = part switch
        {
            DragPart.Body => new PointD(300, 240),
            DragPart.Left => new PointD(200, 240),
            DragPart.Right => new PointD(400, 240),
            DragPart.Top => new PointD(300, 160),
            DragPart.Bottom => new PointD(300, 320),
            _ => throw new ArgumentOutOfRangeException(nameof(part)),
        };
        var end = part is DragPart.Top or DragPart.Bottom
            ? new PointD(start.X, start.Y + 20)
            : new PointD(start.X + 20, start.Y);
        session.PointerDown(start, primaryButton: true);
        if (latched)
        {
            session.PointerUp(start, primaryButton: true);
        }

        session.PointerMove(end, primaryButtonDown: !latched);

        var expected = part switch
        {
            DragPart.Body => new RectD(0.22, 0.2, 0.2, 0.2),
            DragPart.Left => new RectD(0.22, 0.2, 0.18, 0.2),
            DragPart.Right => new RectD(0.2, 0.2, 0.22, 0.2),
            DragPart.Top => new RectD(0.2, 0.225, 0.2, 0.175),
            DragPart.Bottom => new RectD(0.2, 0.2, 0.2, 0.225),
            _ => throw new ArgumentOutOfRangeException(nameof(part)),
        };
        AssertRect(expected, session.WorkingBands[0]);
    }

    [Theory]
    [InlineData(true, CalibrationAction.Save)]
    [InlineData(false, CalibrationAction.Cancel)]
    public void SaveAndCancel_FireImmediatelyWhileLatched(
        bool save,
        CalibrationAction expected)
    {
        var session = new CalibrationSession(Bands(), FullFrame);
        session.PointerDown(new PointD(300, 240), primaryButton: true);
        session.PointerUp(new PointD(300, 240), primaryButton: true);

        var result = save ? session.Save() : session.Cancel();

        Assert.Equal(expected, result);
        Assert.Equal(GesturePhase.Idle, session.Phase);
    }

    [Fact]
    public void CaptureLoss_ClearsOnlyGestureAndKeepsWorkingCopy()
    {
        var session = new CalibrationSession(Bands(), FullFrame);
        session.PointerDown(new PointD(300, 240), primaryButton: true);
        session.PointerMove(new PointD(320, 240), primaryButtonDown: true);
        var edited = session.WorkingBands[0];

        Assert.Equal(CalibrationAction.None, session.CaptureLost());

        Assert.Equal(GesturePhase.Idle, session.Phase);
        Assert.Equal(edited, session.WorkingBands[0]);
    }

    [Fact]
    public void NonPrimaryButtons_NeverStartOrFinishGesture()
    {
        var session = new CalibrationSession(Bands(), FullFrame);

        Assert.Equal(
            CalibrationAction.None,
            session.PointerDown(new PointD(300, 240), primaryButton: false));
        Assert.Equal(GesturePhase.Idle, session.Phase);

        session.PointerDown(new PointD(300, 240), primaryButton: true);
        Assert.Equal(
            CalibrationAction.None,
            session.PointerUp(new PointD(300, 240), primaryButton: false));
        Assert.Equal(GesturePhase.Pressed, session.Phase);
    }

    [Fact]
    public void HitPriority_SelectsLaterOverlappingBand()
    {
        RectD[] bands =
        [
            new RectD(0.2, 0.2, 0.3, 0.3),
            new RectD(0.25, 0.25, 0.3, 0.3),
            new RectD(0.7, 0.7, 0.2, 0.2),
        ];
        var session = new CalibrationSession(bands, FullFrame);

        session.PointerDown(new PointD(350, 300), primaryButton: true);
        session.PointerMove(new PointD(370, 300), primaryButtonDown: true);

        Assert.Equal(bands[0], session.WorkingBands[0]);
        AssertRect(new RectD(0.27, 0.25, 0.3, 0.3), session.WorkingBands[1]);
    }

    [Fact]
    public void FailedMoveCalculation_LeavesGestureAndWorkingBandAtomic()
    {
        var session = new CalibrationSession(Bands(), FullFrame);
        session.PointerDown(new PointD(300, 240), primaryButton: true);
        var before = session.WorkingBands[0];

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            session.PointerMove(new PointD(double.NaN, 240), primaryButtonDown: true));

        Assert.Equal(GesturePhase.Pressed, session.Phase);
        Assert.Equal(before, session.WorkingBands[0]);
        session.PointerMove(new PointD(310, 240), primaryButtonDown: true);
        AssertRect(new RectD(0.21, 0.2, 0.2, 0.2), session.WorkingBands[0]);
    }

    private static RectD[] Bands() =>
    [
        new RectD(0.2, 0.2, 0.2, 0.2),
        new RectD(0.6, 0.45, 0.2, 0.15),
        new RectD(0.7, 0.7, 0.2, 0.15),
    ];

    private static void AssertRect(RectD expected, RectD actual)
    {
        Assert.Equal(expected.X, actual.X, 10);
        Assert.Equal(expected.Y, actual.Y, 10);
        Assert.Equal(expected.Width, actual.Width, 10);
        Assert.Equal(expected.Height, actual.Height, 10);
    }
}
