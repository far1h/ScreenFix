using ScreenFix.App.Guard;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Tests;

public sealed class WindowGuardTests
{
    [Fact]
    public void Start_InstallsHooksBeforeSchedulingSeededWindows()
    {
        var order = new List<string>();
        var source = new FakeEventSource(order)
        {
            StartSignals =
            [
                new WinEventSignal(1, WinEventId.Seed, new nint(17), 0, 0),
                new WinEventSignal(1, WinEventId.Seed, new nint(23), 0, 0),
            ],
        };
        var scheduler = new FakeScheduler(order);
        var corrector = new FakeCorrector(order);
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            scheduler,
            corrector);

        var result = guard.Start(Selected(), Masks());

        Assert.True(result.IsSuccess);
        Assert.Equal(
            ["hook-start", "corrector-start", "scheduler-start", "signal-17", "signal-23"],
            order);
    }

    [Fact]
    public void Start_IdenticalRunningConfigurationIsIdempotent()
    {
        var order = new List<string>();
        var factory = new FakeEventSourceFactory(new FakeEventSource(order));
        using var guard = new WindowGuard(
            factory,
            new FakeScheduler(order),
            new FakeCorrector(order));

        var first = guard.Start(Selected(), Masks());
        var second = guard.Start(Selected(), Masks());

        Assert.True(first.IsSuccess);
        Assert.True(second.IsSuccess);
        Assert.Equal(1, factory.CreateCount);
        Assert.Equal(1, order.Count(item => item == "hook-start"));
        Assert.Equal(1, order.Count(item => item == "scheduler-start"));
        Assert.Equal(1, order.Count(item => item == "corrector-start"));
    }

    [Fact]
    public void Start_ChangedConfigurationStartsCandidateBeforeRetiringOldHooks()
    {
        var order = new List<string>();
        var factory = new FakeEventSourceFactory(
            new FakeEventSource(order, "old"),
            new FakeEventSource(order, "new"));
        using var guard = new WindowGuard(
            factory,
            new FakeScheduler(order),
            new FakeCorrector(order));
        Assert.True(guard.Start(Selected(), Masks()).IsSuccess);
        order.Clear();

        var result = guard.Start(
            Selected(),
            [new RectD(300, 0, 300, 800)]);

        Assert.True(result.IsSuccess);
        Assert.True(order.IndexOf("hook-start-new") < order.IndexOf("hook-stop-old"));
    }

    [Fact]
    public void Start_FailedCandidatePreservesOldHooksButPausesUntilRetry()
    {
        var order = new List<string>();
        var oldSource = new FakeEventSource(order, "old");
        var failedSource = new FakeEventSource(order, "failed")
        {
            StartResult = RuntimeOperationResult.Failure("registration failed"),
        };
        var replacement = new FakeEventSource(order, "replacement");
        var scheduler = new FakeScheduler(order);
        var factory = new FakeEventSourceFactory(
            oldSource,
            failedSource,
            replacement);
        using var guard = new WindowGuard(
            factory,
            scheduler,
            new FakeCorrector(order));
        Assert.True(guard.Start(Selected(), Masks()).IsSuccess);
        var changedMasks = new[] { new RectD(300, 0, 300, 800) };

        var failed = guard.Start(Selected(), changedMasks);
        oldSource.Raise(WinEventId.SystemForeground, new nint(17));

        Assert.False(failed.IsSuccess);
        Assert.Equal(0, oldSource.StopCount);
        Assert.Equal(1, failedSource.StopCount);
        Assert.Empty(scheduler.SignalKeys);
        var retried = guard.Start(Selected(), changedMasks);
        replacement.Raise(WinEventId.SystemForeground, new nint(23));
        Assert.True(retried.IsSuccess);
        Assert.Equal(1, oldSource.StopCount);
        Assert.Equal([23L], scheduler.SignalKeys);
    }

    [Fact]
    public void Stop_InvalidatesAndCancelsBeforeUnhookingAndIsIdempotent()
    {
        var order = new List<string>();
        var source = new FakeEventSource(order) { RaiseDuringStop = true };
        var scheduler = new FakeScheduler(order);
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            scheduler,
            new FakeCorrector(order));
        Assert.True(guard.Start(Selected(), Masks()).IsSuccess);
        order.Clear();

        guard.Stop();
        guard.Stop();

        Assert.Equal(["scheduler-stop", "corrector-stop", "hook-stop"], order);
        Assert.Empty(scheduler.SignalKeys);
        Assert.Equal(1, source.StopCount);
    }

    [Theory]
    [InlineData(0, 0, 0)]
    [InlineData(17, 1, 0)]
    [InlineData(17, 0, 1)]
    public void Signal_NullHandleAndNonWindowObjectsAreIgnored(
        long window,
        int objectId,
        int childId)
    {
        var order = new List<string>();
        var source = new FakeEventSource(order);
        var scheduler = new FakeScheduler(order);
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            scheduler,
            new FakeCorrector(order));
        Assert.True(guard.Start(Selected(), Masks()).IsSuccess);

        source.Raise(
            objectId == 0 && childId == 0
                ? WinEventId.SystemForeground
                : WinEventId.ObjectLocationChange,
            new nint(window),
            objectId,
            childId);

        Assert.Empty(scheduler.SignalKeys);
    }

    [Fact]
    public void CorrectionExceptionIsContainedAndOtherWindowKeysContinue()
    {
        var order = new List<string>();
        var source = new FakeEventSource(order);
        var scheduler = new FakeScheduler(order);
        var corrector = new FakeCorrector(order);
        corrector.ThrowWindows.Add(new nint(17));
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            scheduler,
            corrector);
        Assert.True(guard.Start(Selected(), Masks()).IsSuccess);
        source.Raise(WinEventId.SystemForeground, new nint(17));
        source.Raise(WinEventId.SystemForeground, new nint(23));

        var firstError = Record.Exception(() => scheduler.Run(17));
        var secondError = Record.Exception(() => scheduler.Run(23));

        Assert.Null(firstError);
        Assert.Null(secondError);
        Assert.Equal([new nint(17), new nint(23)], corrector.Attempts);
    }

    [Fact]
    public void Start_HookAndCleanupExceptionsReturnTypedFailure()
    {
        var source = new FakeEventSource([])
        {
            ThrowOnStart = true,
            ThrowOnStop = true,
        };
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            new FakeScheduler([]),
            new FakeCorrector([]));

        RuntimeOperationResult result = default;
        var error = Record.Exception(() =>
            result = guard.Start(Selected(), Masks()));

        Assert.Null(error);
        Assert.False(result.IsSuccess);
    }

    [Fact]
    public void SchedulerSignalExceptionDoesNotFailStartupOrOtherSeeds()
    {
        var source = new FakeEventSource([])
        {
            StartSignals =
            [
                new WinEventSignal(1, WinEventId.Seed, new nint(17), 0, 0),
                new WinEventSignal(1, WinEventId.Seed, new nint(23), 0, 0),
            ],
        };
        var scheduler = new FakeScheduler([]);
        scheduler.ThrowSignalKeys.Add(17);
        using var guard = new WindowGuard(
            new FakeEventSourceFactory(source),
            scheduler,
            new FakeCorrector([]));

        RuntimeOperationResult result = default;
        var error = Record.Exception(() =>
            result = guard.Start(Selected(), Masks()));

        Assert.Null(error);
        Assert.True(result.IsSuccess);
        Assert.Equal([17L, 23L], scheduler.SignalAttempts);
        Assert.Equal([23L], scheduler.SignalKeys);
    }

    private static SelectedMonitor Selected() => new(
        new nint(77),
        new RectD(0, 0, 1000, 800),
        new RectD(0, 0, 1000, 760));

    private static IReadOnlyList<RectD> Masks() =>
        [new RectD(400, 0, 200, 800)];

    private sealed class FakeEventSourceFactory(
        params FakeEventSource[] sources) : IWinEventSourceFactory
    {
        private readonly Queue<FakeEventSource> remaining = new(sources);

        public int CreateCount { get; private set; }

        public IWinEventSource Create()
        {
            CreateCount++;
            return remaining.Dequeue();
        }
    }

    private sealed class FakeEventSource(
        List<string> order,
        string name = "") : IWinEventSource
    {
        private Action<WinEventSignal>? callback;
        private long generation;

        public IReadOnlyList<WinEventSignal> StartSignals { get; set; } = [];

        public RuntimeOperationResult StartResult { get; set; } =
            RuntimeOperationResult.Success();

        public int StopCount { get; private set; }

        public bool RaiseDuringStop { get; set; }

        public bool ThrowOnStart { get; set; }

        public bool ThrowOnStop { get; set; }

        public RuntimeOperationResult Start(
            long generation,
            Action<WinEventSignal> signal)
        {
            if (ThrowOnStart)
            {
                throw new InvalidOperationException("hook start failed");
            }

            this.generation = generation;
            callback = signal;
            order.Add(name.Length == 0 ? "hook-start" : $"hook-start-{name}");
            foreach (var item in StartSignals)
            {
                signal(item with { Generation = generation });
            }

            return StartResult;
        }

        public void Stop()
        {
            if (ThrowOnStop)
            {
                throw new InvalidOperationException("hook stop failed");
            }

            if (RaiseDuringStop)
            {
                Raise(WinEventId.SystemForeground, new nint(17));
            }

            StopCount++;
            order.Add(name.Length == 0 ? "hook-stop" : $"hook-stop-{name}");
        }

        public void Dispose() => Stop();

        public void Raise(
            uint eventType,
            nint window,
            int objectId = 0,
            int childId = 0) =>
            callback?.Invoke(new WinEventSignal(
                generation,
                eventType,
                window,
                objectId,
                childId));
    }

    private sealed class FakeScheduler(List<string> order) : IGuardScheduler
    {
        private readonly Dictionary<long, Action<long>> corrections = [];

        public List<long> SignalKeys { get; } = [];

        public List<long> SignalAttempts { get; } = [];

        public HashSet<long> ThrowSignalKeys { get; } = [];

        public void Start(long generation) => order.Add("scheduler-start");

        public void Signal(long key, Action<long> correction)
        {
            SignalAttempts.Add(key);
            if (ThrowSignalKeys.Contains(key))
            {
                throw new InvalidOperationException("scheduling failed");
            }

            SignalKeys.Add(key);
            corrections[key] = correction;
            order.Add($"signal-{key}");
        }

        public void Run(long key) => corrections[key](key);

        public void Stop() => order.Add("scheduler-stop");

        public void Dispose() => Stop();
    }

    private sealed class FakeCorrector(List<string> order) : IWindowCorrector
    {
        public HashSet<nint> ThrowWindows { get; } = [];

        public List<nint> Attempts { get; } = [];

        public void Start(long generation) => order.Add("corrector-start");

        public void Correct(
            long generation,
            nint window,
            SelectedMonitor selectedMonitor,
            IReadOnlyList<RectD> maskBands)
        {
            Attempts.Add(window);
            order.Add($"correct-{window}");
            if (ThrowWindows.Contains(window))
            {
                throw new InvalidOperationException("correction failed");
            }
        }

        public void Stop() => order.Add("corrector-stop");

        public void Dispose() => Stop();
    }
}
