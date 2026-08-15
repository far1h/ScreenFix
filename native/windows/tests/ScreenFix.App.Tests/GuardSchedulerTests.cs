using ScreenFix.App.Guard;

namespace ScreenFix.App.Tests;

public sealed class GuardSchedulerTests
{
    [Fact]
    public void Signal_SchedulesCorrectionAfter150Milliseconds()
    {
        var delay = new FakeUiDelay();
        var scheduler = new GuardScheduler(delay);
        var corrected = new List<long>();
        scheduler.Start(generation: 7);

        scheduler.Signal(17, corrected.Add);

        var scheduled = Assert.Single(delay.Work);
        Assert.Equal(TimeSpan.FromMilliseconds(150), scheduled.Delay);
        scheduled.Fire();
        Assert.Equal([17], corrected);
    }

    [Fact]
    public void Signal_ReplacesOnlyPendingWorkForSameKey()
    {
        var delay = new FakeUiDelay();
        var scheduler = new GuardScheduler(delay);
        var corrected = new List<long>();
        scheduler.Start(generation: 7);

        scheduler.Signal(17, corrected.Add);
        scheduler.Signal(17, corrected.Add);

        Assert.True(delay.Work[0].IsDisposed);
        Assert.False(delay.Work[1].IsDisposed);
        delay.Work[0].Fire();
        delay.Work[1].Fire();
        Assert.Equal([17], corrected);
    }

    [Fact]
    public void Signal_KeepsDifferentWindowKeysIndependent()
    {
        var delay = new FakeUiDelay();
        var scheduler = new GuardScheduler(delay);
        var corrected = new List<long>();
        scheduler.Start(generation: 7);

        scheduler.Signal(17, corrected.Add);
        scheduler.Signal(23, corrected.Add);

        Assert.All(delay.Work, work => Assert.False(work.IsDisposed));
        delay.Work[1].Fire();
        delay.Work[0].Fire();
        Assert.Equal([23, 17], corrected);
    }

    [Fact]
    public void Stop_CancelsAllPendingWorkAndMakesLateCallbacksInert()
    {
        var delay = new FakeUiDelay();
        var scheduler = new GuardScheduler(delay);
        var corrected = new List<long>();
        scheduler.Start(generation: 7);
        scheduler.Signal(17, corrected.Add);
        scheduler.Signal(23, corrected.Add);

        scheduler.Stop();

        Assert.All(delay.Work, work => Assert.True(work.IsDisposed));
        foreach (var work in delay.Work)
        {
            work.Fire();
        }

        Assert.Empty(corrected);
    }

    [Fact]
    public void Start_NewGenerationCancelsStaleSessionWork()
    {
        var delay = new FakeUiDelay();
        var scheduler = new GuardScheduler(delay);
        var corrected = new List<long>();
        scheduler.Start(generation: 7);
        scheduler.Signal(17, corrected.Add);

        scheduler.Start(generation: 8);

        Assert.True(delay.Work[0].IsDisposed);
        delay.Work[0].Fire();
        Assert.Empty(corrected);
    }

    private sealed class FakeUiDelay : IUiDelay
    {
        public List<ScheduledWork> Work { get; } = [];

        public IDisposable Schedule(TimeSpan delay, Action callback)
        {
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
}
