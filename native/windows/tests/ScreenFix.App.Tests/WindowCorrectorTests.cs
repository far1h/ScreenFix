using ScreenFix.App.Guard;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.App.Tests;

public sealed class WindowCorrectorTests
{
    [Fact]
    public void Normal_CorrectsVisibleFrameAndWritesRoundedOuterFrameWithoutActivation()
    {
        var visible = new RectD(450, 100, 100, 100);
        var inspector = new FakeInspector(Inspection(
            visible,
            new RectD(439.5, 79.5, 120, 140),
            new WindowFrameOffsets(10.5, 20.5, 9.5, 19.5)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);

        corrector.Correct(
            generation: 7,
            new nint(17),
            Selected(),
            [new RectD(400, 0, 200, 800)]);

        var write = Assert.Single(writer.FrameWrites);
        Assert.Equal(new nint(17), write.Window);
        Assert.Equal(new NativeWindowFrame(290, 80, 120, 140), write.Frame);
        Assert.Equal(WindowCorrectionFlags.NoActivate |
            WindowCorrectionFlags.NoZOrder |
            WindowCorrectionFlags.NoOwnerZOrder |
            WindowCorrectionFlags.AsyncWindowPosition,
            write.Flags);
    }

    [Fact]
    public void NeverApplies_VerifiesAtAbsoluteDeadlinesAndRefusesAt500Milliseconds()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Equal(TimeSpan.FromMilliseconds(50), delay.Work[0].Delay);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);
        delay.Work[0].Fire();
        Assert.Equal(TimeSpan.FromMilliseconds(100), delay.Work[1].Delay);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(150);
        delay.Work[1].Fire();
        Assert.Equal(TimeSpan.FromMilliseconds(150), delay.Work[2].Delay);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(300);
        delay.Work[2].Fire();
        Assert.Equal(TimeSpan.FromMilliseconds(200), delay.Work[3].Delay);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(500);
        delay.Work[3].Fire();

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Single(writer.FrameWrites);
        Assert.Equal(4, delay.Work.Count);
    }

    [Fact]
    public void VerificationFailureForExistingWindowRemainsPending()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter { WindowExists = true };
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.Inspection = null;

        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);
        delay.Work[0].Fire();

        Assert.Equal(2, delay.Work.Count);
        Assert.Equal(TimeSpan.FromMilliseconds(100), delay.Work[1].Delay);
    }

    [Fact]
    public void Maximized_RestoresWithoutActivationBeforeScreenCoordinateWrite()
    {
        var placement = new WindowPlacementData(
            Flags: 2,
            ShowCommand: 3,
            new NativeWindowPoint(-1, -2),
            new NativeWindowPoint(3, 4),
            new NativeWindowRectangle(10, 20, 410, 320),
            new NativeWindowRectangle(0, 0, 1920, 1080));
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            zoomed: true));
        var writer = new FakeWriter { Placement = placement };
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        var placementWrite = Assert.Single(writer.PlacementWrites);
        Assert.Equal(placement with
        {
            Flags = placement.Flags | WindowPlacementFlags.AsyncWindowPlacement,
            ShowCommand = WindowShowCommand.ShowNoActivate,
        }, placementWrite.Placement);
        Assert.Equal(["get-placement", "set-placement", "set-frame"], writer.CallOrder);
        Assert.Single(writer.FrameWrites);
    }

    [Fact]
    public void VerificationScheduleFailureDoesNotLeaveWindowPermanentlyPending()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay { ThrowOnSchedule = true };
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);

        var error = Record.Exception(() => corrector.Correct(
            7,
            new nint(17),
            Selected(),
            [new RectD(400, 0, 200, 800)]));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddSeconds(1);
        delay.ThrowOnSchedule = false;
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Null(error);
        Assert.Equal(2, writer.FrameWrites.Count);
    }

    [Fact]
    public void LateVerificationSkipsElapsedDeadlines()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            new FakeWriter(),
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(300);
        delay.Work[0].Fire();

        Assert.Equal(2, delay.Work.Count);
        Assert.Equal(TimeSpan.FromMilliseconds(200), delay.Work[1].Delay);
    }

    [Fact]
    public void FollowUpScheduleFailureIsContainedAndRefusesTemporarily()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);
        delay.ThrowOnSchedule = true;

        var error = Record.Exception(delay.Work[0].Fire);

        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(1_050);
        delay.ThrowOnSchedule = false;
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Null(error);
        Assert.Equal(2, writer.FrameWrites.Count);
    }

    [Fact]
    public void InspectionExceptionIsContainedToOneWindow()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)))
        {
            ThrowOnInspect = true,
        };
        var writer = new FakeWriter();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);

        var error = Record.Exception(() => corrector.Correct(
            7,
            new nint(17),
            Selected(),
            [new RectD(400, 0, 200, 800)]));
        inspector.ThrowOnInspect = false;
        inspector.Inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            key: 23);
        corrector.Correct(7, new nint(23), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Null(error);
        Assert.Single(writer.FrameWrites);
        Assert.Equal(new nint(23), writer.FrameWrites[0].Window);
    }

    [Fact]
    public void VerificationInspectionExceptionForExistingWindowRemainsPending()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            new FakeWriter { WindowExists = true },
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.ThrowOnInspect = true;
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);

        var error = Record.Exception(delay.Work[0].Fire);

        Assert.Null(error);
        Assert.Equal(2, delay.Work.Count);
        Assert.Equal(TimeSpan.FromMilliseconds(100), delay.Work[1].Delay);
    }

    [Fact]
    public void GeometryWithoutSafeCandidateDoesNotWrite()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(100, 100, 500, 400),
            new RectD(90, 90, 520, 420),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(0, 0, 1000, 800)]);

        Assert.Empty(writer.FrameWrites);
        Assert.Empty(delay.Work);
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void Maximized_PlacementFailureRefusesAndSkipsFrameWrite(
        bool getSucceeds,
        bool setSucceeds)
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            zoomed: true));
        var writer = new FakeWriter
        {
            GetPlacementSucceeds = getSucceeds,
            SetPlacementSucceeds = setSucceeds,
        };
        var clock = new FakeClock();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(999);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Empty(writer.FrameWrites);
        Assert.Equal(1, writer.CallOrder.Count(call => call == "get-placement"));
        Assert.Equal(getSucceeds ? 1 : 0,
            writer.CallOrder.Count(call => call == "set-placement"));
    }

    [Fact]
    public void AppliesAt150MillisecondsAndSuppressesFromVerificationTime()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);
        delay.Work[0].Fire();
        inspector.Inspection = Inspection(
            new RectD(300, 100, 100, 100),
            new RectD(290, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(150);

        delay.Work[1].Fire();

        inspector.Inspection = Inspection(
            new RectD(300, 100, 101, 100),
            new RectD(290, 90, 121, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(399);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Single(writer.FrameWrites);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(400);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Equal(2, writer.FrameWrites.Count);
    }

    [Fact]
    public void PendingSignalNeverDuplicatesWriteAndCanCompleteEarly()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Single(writer.FrameWrites);
        Assert.Single(delay.Work);
        inspector.Inspection = Inspection(
            new RectD(300, 100, 100, 100),
            new RectD(290, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.True(delay.Work[0].IsDisposed);
        delay.Work[0].Fire();
        Assert.Single(writer.FrameWrites);
        Assert.Single(delay.Work);
    }

    [Fact]
    public void ReplacedGenerationRejectsLateTimerForSameWindow()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        corrector.Start(generation: 8);
        corrector.Correct(8, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        delay.Work[0].Fire();

        Assert.Equal(2, writer.FrameWrites.Count);
        Assert.False(delay.Work[1].IsDisposed);
        Assert.Equal(2, delay.Work.Count);
    }

    [Fact]
    public void ApplicationAt500MillisecondsSucceedsInsteadOfRefusing()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        foreach (var deadline in new[] { 50, 150, 300 })
        {
            clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(deadline);
            delay.Work[^1].Fire();
        }

        inspector.Inspection = Inspection(
            new RectD(300, 100, 100, 100),
            new RectD(290, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(500);
        delay.Work[^1].Fire();

        inspector.Inspection = Inspection(
            new RectD(300, 100, 101, 100),
            new RectD(290, 90, 121, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Single(writer.FrameWrites);
    }

    [Fact]
    public void DisappearedWindowIsForgottenWithoutRefusal()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.Inspection = null;
        writer.WindowExists = false;
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(50);
        delay.Work[0].Fire();

        inspector.Inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        writer.WindowExists = true;
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Equal(2, writer.FrameWrites.Count);
        Assert.Equal(2, delay.Work.Count);
    }

    [Fact]
    public void NativeRefusalIsIsolatedAndExpiresAtExactlyOneSecond()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter { FrameWriteSucceeds = false };
        var clock = new FakeClock();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        inspector.Inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            key: 23);
        writer.FrameWriteSucceeds = true;
        corrector.Correct(7, new nint(23), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.Inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(999);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        Assert.Equal(2, writer.FrameWrites.Count);
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddSeconds(1);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Equal(3, writer.FrameWrites.Count);
        Assert.Equal(new nint(23), writer.FrameWrites[1].Window);
        Assert.Equal(new nint(17), writer.FrameWrites[2].Window);
    }

    [Fact]
    public void PendingInspectionExceptionDoesNotCreateRefusalAfterSuccess()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var clock = new FakeClock();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            clock,
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.ThrowOnInspect = true;
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(10);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.ThrowOnInspect = false;
        inspector.Inspection = Inspection(
            new RectD(300, 100, 100, 100),
            new RectD(290, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(20);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.Inspection = Inspection(
            new RectD(300, 100, 101, 100),
            new RectD(290, 90, 121, 120),
            new WindowFrameOffsets(10, 10, 10, 10));
        clock.UtcNow = DateTimeOffset.UnixEpoch.AddMilliseconds(270);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Equal(2, writer.FrameWrites.Count);
    }

    [Fact]
    public void PendingNullInspectionForExistingWindowKeepsVerificationAlive()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter { WindowExists = true };
        var delay = new FakeDelay();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);
        inspector.Inspection = null;

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.False(delay.Work[0].IsDisposed);
        Assert.Single(writer.FrameWrites);
    }

    [Fact]
    public void Normal_RoundsNegativeOuterEdgesAwayFromZero()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(-550, 100, 100, 100),
            new RectD(-560.5, 79.5, 120, 140),
            new WindowFrameOffsets(10.5, 20.5, 9.5, 19.5)));
        var writer = new FakeWriter();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);
        var selected = new SelectedMonitor(
            new nint(77),
            new RectD(-1000, 0, 1000, 800),
            new RectD(-1000, 0, 1000, 800));

        corrector.Correct(7, new nint(17), selected,
            [new RectD(-600, 0, 200, 800)]);

        Assert.Equal(
            new NativeWindowFrame(-711, 80, 120, 140),
            Assert.Single(writer.FrameWrites).Frame);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void IneligibleStateNeverRestoresOrWrites(
        bool minimized,
        bool borderlessFullScreen)
    {
        var inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            zoomed: true);
        var inspector = new FakeInspector(inspection with
        {
            Facts = inspection.Facts with
            {
                IsMinimized = minimized,
                IsBorderlessFullScreen = borderlessFullScreen,
            },
        });
        var writer = new FakeWriter();
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);

        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Empty(writer.CallOrder);
    }

    [Fact]
    public void StopCancelsVerificationAndMakesLateCallbacksInert()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter();
        var delay = new FakeDelay();
        var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            delay);
        corrector.Start(generation: 7);
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        corrector.Stop();
        corrector.Stop();
        delay.Work[0].Fire();
        corrector.Correct(7, new nint(17), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.True(delay.Work[0].IsDisposed);
        Assert.Single(writer.FrameWrites);
        Assert.Single(delay.Work);
    }

    [Fact]
    public void WindowDestroyedDuringFrameWriteIsContained()
    {
        var inspector = new FakeInspector(Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10)));
        var writer = new FakeWriter { ThrowOnFrameWrite = true };
        using var corrector = new WindowCorrector(
            inspector,
            writer,
            new FakeClock(),
            new GuardMemory(),
            new FakeDelay());
        corrector.Start(generation: 7);

        var error = Record.Exception(() => corrector.Correct(
            7,
            new nint(17),
            Selected(),
            [new RectD(400, 0, 200, 800)]));
        inspector.Inspection = Inspection(
            new RectD(450, 100, 100, 100),
            new RectD(440, 90, 120, 120),
            new WindowFrameOffsets(10, 10, 10, 10),
            key: 23);
        writer.ThrowOnFrameWrite = false;
        corrector.Correct(7, new nint(23), Selected(),
            [new RectD(400, 0, 200, 800)]);

        Assert.Null(error);
        Assert.Single(writer.FrameWrites);
        Assert.Equal(new nint(23), writer.FrameWrites[0].Window);
    }

    private static WindowInspection Inspection(
        RectD visible,
        RectD outer,
        WindowFrameOffsets offsets,
        bool zoomed = false,
        long key = 17) => new(
            new WindowFacts(
                key,
                visible,
                IsVisible: true,
                IsMinimized: false,
                IsRootTopLevel: true,
                IsOwned: false,
                IsScreenFixOwned: false,
                IsPlatformOwned: false,
                IsToolOrMenu: false,
                IsMovable: true,
                IsBorderlessFullScreen: false,
                IsOnSelectedDisplay: true),
            zoomed,
            outer,
            offsets);

    private static SelectedMonitor Selected() => new(
        new nint(77),
        new RectD(0, 0, 1000, 800),
        new RectD(0, 0, 1000, 800));

    private sealed class FakeInspector(WindowInspection? inspection) : IWindowInspector
    {
        public WindowInspection? Inspection { get; set; } = inspection;

        public bool ThrowOnInspect { get; set; }

        public WindowInspection? TryInspect(nint window, SelectedMonitor selectedMonitor)
        {
            if (ThrowOnInspect)
            {
                throw new InvalidOperationException("inspection failed");
            }

            return Inspection;
        }
    }

    private sealed class FakeWriter : IWindowNativeWriter
    {
        public List<FrameWrite> FrameWrites { get; } = [];

        public bool WindowExists { get; set; } = true;

        public WindowPlacementData Placement { get; set; }

        public bool GetPlacementSucceeds { get; set; } = true;

        public bool SetPlacementSucceeds { get; set; } = true;

        public bool FrameWriteSucceeds { get; set; } = true;

        public bool ThrowOnFrameWrite { get; set; }

        public List<PlacementWrite> PlacementWrites { get; } = [];

        public List<string> CallOrder { get; } = [];

        public bool IsWindow(nint window) => WindowExists;

        public bool TryGetPlacement(nint window, out WindowPlacementData placement)
        {
            CallOrder.Add("get-placement");
            placement = Placement;
            return GetPlacementSucceeds;
        }

        public bool TrySetPlacement(nint window, WindowPlacementData placement)
        {
            CallOrder.Add("set-placement");
            PlacementWrites.Add(new PlacementWrite(window, placement));
            return SetPlacementSucceeds;
        }

        public bool TrySetFrame(nint window, NativeWindowFrame frame, uint flags)
        {
            if (ThrowOnFrameWrite)
            {
                throw new InvalidOperationException("window disappeared");
            }

            CallOrder.Add("set-frame");
            FrameWrites.Add(new FrameWrite(window, frame, flags));
            return FrameWriteSucceeds;
        }
    }

    private sealed class FakeClock : IClock
    {
        public DateTimeOffset UtcNow { get; set; } = DateTimeOffset.UnixEpoch;
    }

    private sealed class FakeDelay : IUiDelay
    {
        public List<ScheduledWork> Work { get; } = [];

        public bool ThrowOnSchedule { get; set; }

        public IDisposable Schedule(TimeSpan delay, Action callback)
        {
            if (ThrowOnSchedule)
            {
                throw new InvalidOperationException("schedule failed");
            }

            var work = new ScheduledWork(delay, callback);
            Work.Add(work);
            return work;
        }
    }

    private sealed class ScheduledWork(TimeSpan delay, Action callback) : IDisposable
    {
        public TimeSpan Delay { get; } = delay;

        public bool IsDisposed { get; private set; }

        public void Dispose() => IsDisposed = true;

        public void Fire() => callback();
    }

    private sealed record FrameWrite(
        nint Window,
        NativeWindowFrame Frame,
        uint Flags);

    private sealed record PlacementWrite(
        nint Window,
        WindowPlacementData Placement);
}
