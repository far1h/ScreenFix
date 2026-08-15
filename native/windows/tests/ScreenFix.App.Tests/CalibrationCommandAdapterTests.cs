using ScreenFix.App.Calibration;
using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Tests;

public sealed class CalibrationCommandAdapterTests
{
    [Fact]
    public void Save_WhenCallbackKeepsEditorOpen_ReleasesLatchedCaptureAndPreservesWorkingCopy()
    {
        var session = CreateLatchedSession();
        var edited = session.WorkingBands.ToArray();
        var captured = true;
        var callbackObservedRelease = false;
        var adapter = new CalibrationCommandAdapter(session, () => captured = false);

        adapter.Save(bands =>
        {
            callbackObservedRelease = !captured;
            Assert.Equal(edited, bands);
        });

        Assert.False(captured);
        Assert.True(callbackObservedRelease);
        Assert.Equal(GesturePhase.Idle, session.Phase);
        Assert.Equal(edited, session.WorkingBands);
    }

    [Fact]
    public void Cancel_ReleasesLatchedCaptureBeforeCallback()
    {
        var session = CreateLatchedSession();
        var captured = true;
        var callbackObservedRelease = false;
        var adapter = new CalibrationCommandAdapter(session, () => captured = false);

        adapter.Cancel(() => callbackObservedRelease = !captured);

        Assert.False(captured);
        Assert.True(callbackObservedRelease);
        Assert.Equal(GesturePhase.Idle, session.Phase);
    }

    private static CalibrationSession CreateLatchedSession()
    {
        var session = new CalibrationSession(
            [
                new RectD(0.2, 0.2, 0.2, 0.2),
                new RectD(0.6, 0.45, 0.2, 0.15),
                new RectD(0.7, 0.7, 0.2, 0.15),
            ],
            new RectD(0, 0, 1000, 800));
        session.PointerDown(new PointD(300, 240), primaryButton: true);
        session.PointerUp(new PointD(300, 240), primaryButton: true);
        session.PointerMove(new PointD(320, 240), primaryButtonDown: false);
        return session;
    }
}
