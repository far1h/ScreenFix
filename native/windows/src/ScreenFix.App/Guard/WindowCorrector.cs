using ScreenFix.App.Runtime;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.App.Guard;

public static class WindowCorrectionFlags
{
    public const uint NoZOrder = 0x0004;
    public const uint NoActivate = 0x0010;
    public const uint NoOwnerZOrder = 0x0200;
    public const uint AsyncWindowPosition = 0x4000;
}

public static class WindowPlacementFlags
{
    public const uint AsyncWindowPlacement = 0x0004;
}

public static class WindowShowCommand
{
    public const uint ShowNoActivate = 4;
}

public readonly record struct NativeWindowFrame(
    int X,
    int Y,
    int Width,
    int Height);

public readonly record struct NativeWindowRectangle(
    int Left,
    int Top,
    int Right,
    int Bottom);

public readonly record struct NativeWindowPoint(int X, int Y);

public readonly record struct WindowPlacementData(
    uint Flags,
    uint ShowCommand,
    NativeWindowPoint MinimizedPosition,
    NativeWindowPoint MaximizedPosition,
    NativeWindowRectangle NormalPosition);

public interface IWindowNativeWriter
{
    bool IsCurrent(WindowIdentity window);

    bool TryGetPlacement(
        WindowIdentity window,
        out WindowPlacementData placement);

    bool TrySetPlacement(
        WindowIdentity window,
        WindowPlacementData placement);

    bool TrySetFrame(
        WindowIdentity window,
        NativeWindowFrame frame,
        uint flags);
}

public interface IWindowCorrector : IDisposable
{
    void Start(long generation);

    void Correct(
        long generation,
        WindowIdentity window,
        SelectedMonitor selectedMonitor,
        IReadOnlyList<RectD> maskBands);

    void Forget(WindowIdentity window);

    void Stop();
}

public sealed class WindowCorrector : IWindowCorrector
{
    private static readonly TimeSpan[] VerificationDeadlines =
    [
        TimeSpan.FromMilliseconds(50),
        TimeSpan.FromMilliseconds(150),
        TimeSpan.FromMilliseconds(300),
        TimeSpan.FromMilliseconds(500),
    ];

    private const uint WriteFlags =
        WindowCorrectionFlags.NoActivate |
        WindowCorrectionFlags.NoZOrder |
        WindowCorrectionFlags.NoOwnerZOrder |
        WindowCorrectionFlags.AsyncWindowPosition;

    private readonly IWindowInspector inspector;
    private readonly IWindowNativeWriter writer;
    private readonly IClock clock;
    private readonly GuardMemory memory;
    private readonly IUiDelay delay;
    private readonly Dictionary<long, PendingCorrection> pending = [];
    private bool active;
    private long generation;

    public WindowCorrector(
        IWindowInspector inspector,
        IWindowNativeWriter writer,
        IClock clock,
        GuardMemory memory,
        IUiDelay delay)
    {
        this.inspector = inspector;
        this.writer = writer;
        this.clock = clock;
        this.memory = memory;
        this.delay = delay;
    }

    public void Start(long generation)
    {
        CancelPending();
        this.generation = generation;
        active = true;
        memory.Clear();
    }

    public void Correct(
        long generation,
        WindowIdentity window,
        SelectedMonitor selectedMonitor,
        IReadOnlyList<RectD> maskBands)
    {
        ArgumentNullException.ThrowIfNull(maskBands);
        if (!active || generation != this.generation)
        {
            return;
        }

        WindowInspection? inspection;
        try
        {
            inspection = inspector.TryInspect(window, selectedMonitor);
        }
        catch
        {
            var key = window.Key;
            if (!pending.ContainsKey(key))
            {
                memory.RecordRefusal(key, clock.UtcNow);
            }

            return;
        }
        if (inspection is null)
        {
            bool exists;
            try
            {
                exists = writer.IsCurrent(window);
            }
            catch
            {
                return;
            }

            if (!exists)
            {
                CancelPending(window.Key);
                memory.Forget(window.Key);
            }

            return;
        }

        var facts = inspection.Facts;
        if (pending.TryGetValue(facts.Key, out var existing))
        {
            if (Near(facts.VisibleFrame, existing.VisibleTarget))
            {
                CompleteSuccess(existing);
            }

            return;
        }

        if (memory.ShouldSuppressRecent(facts.Key, facts.VisibleFrame, clock.UtcNow) ||
            memory.IsRefused(facts.Key, clock.UtcNow) ||
            !WindowEligibility.IsEligible(facts, maskBands))
        {
            return;
        }

        var corrected = GuardGeometry.CorrectedFrame(
            facts.VisibleFrame,
            selectedMonitor.WorkArea,
            maskBands);
        if (corrected is null ||
            !TryBuildOuterFrame(corrected.Value, inspection.FrameOffsets, out var frame))
        {
            return;
        }

        try
        {
            if (inspection.IsZoomed &&
                !TryRestoreWithoutActivation(window))
            {
                memory.RecordRefusal(facts.Key, clock.UtcNow);
                return;
            }

            if (!writer.TrySetFrame(window, frame, WriteFlags))
            {
                memory.RecordRefusal(facts.Key, clock.UtcNow);
                return;
            }

            BeginVerification(
                generation,
                window,
                facts.Key,
                corrected.Value,
                selectedMonitor);
        }
        catch
        {
            memory.RecordRefusal(facts.Key, clock.UtcNow);
        }
    }

    public void Stop()
    {
        active = false;
        generation++;
        CancelPending();
        memory.Clear();
    }

    public void Dispose() => Stop();

    public void Forget(WindowIdentity window)
    {
        CancelPending(window.Key);
        memory.Forget(window.Key);
    }

    private bool TryRestoreWithoutActivation(WindowIdentity window)
    {
        if (!writer.TryGetPlacement(window, out var placement))
        {
            return false;
        }

        var restored = placement with
        {
            Flags = placement.Flags | WindowPlacementFlags.AsyncWindowPlacement,
            ShowCommand = WindowShowCommand.ShowNoActivate,
        };
        return writer.TrySetPlacement(window, restored);
    }

    private void BeginVerification(
        long generation,
        WindowIdentity window,
        long key,
        RectD visibleTarget,
        SelectedMonitor selectedMonitor)
    {
        var correction = new PendingCorrection(
            generation,
            window,
            key,
            visibleTarget,
            selectedMonitor,
            clock.UtcNow);
        pending[key] = correction;
        try
        {
            ScheduleVerification(correction);
        }
        catch
        {
            if (pending.TryGetValue(key, out var current) &&
                ReferenceEquals(current, correction))
            {
                pending.Remove(key);
            }

            throw;
        }
    }

    private void ScheduleVerification(PendingCorrection correction)
    {
        var deadline = correction.StartedAt +
            VerificationDeadlines[correction.DeadlineIndex];
        var wait = deadline - clock.UtcNow;
        if (wait < TimeSpan.Zero)
        {
            wait = TimeSpan.Zero;
        }

        correction.Cancellation = delay.Schedule(
            wait,
            () => Verify(correction));
    }

    private void Verify(PendingCorrection correction)
    {
        if (!IsCurrent(correction))
        {
            return;
        }

        correction.Cancellation?.Dispose();
        correction.Cancellation = null;
        WindowInspection? inspection;
        try
        {
            inspection = inspector.TryInspect(
                correction.Window,
                correction.SelectedMonitor);
        }
        catch
        {
            inspection = null;
        }

        if (inspection is null)
        {
            bool exists;
            try
            {
                exists = writer.IsCurrent(correction.Window);
            }
            catch
            {
                ContinueOrRefuse(correction);
                return;
            }

            if (!exists)
            {
                pending.Remove(correction.Key);
                memory.Forget(correction.Key);
                return;
            }

            ContinueOrRefuse(correction);
            return;
        }

        if (Near(inspection.Facts.VisibleFrame, correction.VisibleTarget))
        {
            CompleteSuccess(correction);
            return;
        }

        ContinueOrRefuse(correction);
    }

    private void ContinueOrRefuse(PendingCorrection correction)
    {
        var nextIndex = correction.DeadlineIndex + 1;
        while (nextIndex < VerificationDeadlines.Length &&
               correction.StartedAt + VerificationDeadlines[nextIndex] <= clock.UtcNow)
        {
            nextIndex++;
        }

        if (nextIndex == VerificationDeadlines.Length)
        {
            pending.Remove(correction.Key);
            memory.RecordRefusal(correction.Key, clock.UtcNow);
            return;
        }

        correction.DeadlineIndex = nextIndex;
        try
        {
            ScheduleVerification(correction);
        }
        catch
        {
            pending.Remove(correction.Key);
            memory.RecordRefusal(correction.Key, clock.UtcNow);
        }
    }

    private void CompleteSuccess(PendingCorrection correction)
    {
        correction.Cancellation?.Dispose();
        pending.Remove(correction.Key);
        memory.RecordSuccess(
            correction.Key,
            correction.VisibleTarget,
            clock.UtcNow);
    }

    private bool IsCurrent(PendingCorrection correction) =>
        active &&
        correction.Generation == generation &&
        pending.TryGetValue(correction.Key, out var current) &&
        ReferenceEquals(current, correction);

    private void CancelPending(long key)
    {
        if (pending.Remove(key, out var correction))
        {
            correction.Cancellation?.Dispose();
        }
    }

    private void CancelPending()
    {
        foreach (var correction in pending.Values)
        {
            correction.Cancellation?.Dispose();
        }

        pending.Clear();
    }

    private static bool Near(RectD first, RectD second) =>
        Math.Abs(first.X - second.X) <= 1 &&
        Math.Abs(first.Y - second.Y) <= 1 &&
        Math.Abs(first.Right - second.Right) <= 1 &&
        Math.Abs(first.Bottom - second.Bottom) <= 1;

    private static bool TryBuildOuterFrame(
        RectD visibleTarget,
        WindowFrameOffsets offsets,
        out NativeWindowFrame frame)
    {
        try
        {
            var left = checked((int)Math.Round(
                visibleTarget.X - offsets.Left,
                MidpointRounding.AwayFromZero));
            var top = checked((int)Math.Round(
                visibleTarget.Y - offsets.Top,
                MidpointRounding.AwayFromZero));
            var right = checked((int)Math.Round(
                visibleTarget.Right + offsets.Right,
                MidpointRounding.AwayFromZero));
            var bottom = checked((int)Math.Round(
                visibleTarget.Bottom + offsets.Bottom,
                MidpointRounding.AwayFromZero));
            var width = checked(right - left);
            var height = checked(bottom - top);
            if (width <= 0 || height <= 0)
            {
                frame = default;
                return false;
            }

            frame = new NativeWindowFrame(left, top, width, height);
            return true;
        }
        catch (OverflowException)
        {
            frame = default;
            return false;
        }
    }

    private sealed class PendingCorrection(
        long generation,
        WindowIdentity window,
        long key,
        RectD visibleTarget,
        SelectedMonitor selectedMonitor,
        DateTimeOffset startedAt)
    {
        public long Generation { get; } = generation;

        public WindowIdentity Window { get; } = window;

        public long Key { get; } = key;

        public RectD VisibleTarget { get; } = visibleTarget;

        public SelectedMonitor SelectedMonitor { get; } = selectedMonitor;

        public DateTimeOffset StartedAt { get; } = startedAt;

        public int DeadlineIndex { get; set; }

        public IDisposable? Cancellation { get; set; }
    }
}
