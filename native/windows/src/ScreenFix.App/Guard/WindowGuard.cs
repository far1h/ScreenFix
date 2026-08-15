using ScreenFix.App.Runtime;
using ScreenFix.App.Notifications;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Guard;

public interface IWinEventSourceFactory
{
    IWinEventSource Create();
}

public sealed class WinEventSourceFactory(
    IWinEventNativeApi native,
    IUiDispatcher dispatcher) : IWinEventSourceFactory
{
    public IWinEventSource Create() => new WinEventHookSet(native, dispatcher);
}

public interface IWindowGuard : IDisposable
{
    RuntimeOperationResult Start(
        SelectedMonitor selectedMonitor,
        IReadOnlyList<RectD> maskBands);

    void Pause();

    void Stop();
}

public sealed class WindowGuard(
    IWinEventSourceFactory sourceFactory,
    IGuardScheduler scheduler,
    IWindowCorrector corrector) : IWindowGuard
{
    private IWinEventSource? source;
    private SelectedMonitor? selectedMonitor;
    private RectD[] maskBands = [];
    private bool correctionEnabled;
    private bool disposed;
    private long generation;

    public RuntimeOperationResult Start(
        SelectedMonitor selectedMonitor,
        IReadOnlyList<RectD> maskBands)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(maskBands);
        if (correctionEnabled && IsSameConfiguration(selectedMonitor, maskBands))
        {
            return RuntimeOperationResult.Success();
        }

        PauseForReplacement();
        var candidateGeneration = ++generation;
        IWinEventSource candidate;
        try
        {
            candidate = sourceFactory.Create();
        }
        catch
        {
            return RuntimeOperationResult.Failure("Window event hook creation failed");
        }

        var queued = new List<WinEventSignal>();
        var committed = false;
        RuntimeOperationResult result;
        try
        {
            result = candidate.Start(candidateGeneration, signal =>
            {
                if (committed)
                {
                    HandleSignal(candidateGeneration, signal);
                }
                else
                {
                    queued.Add(signal);
                }
            });
        }
        catch
        {
            TryDispose(candidate);
            return RuntimeOperationResult.Failure("Window event hook registration failed");
        }

        if (!result.IsSuccess)
        {
            TryDispose(candidate);
            return result;
        }

        try
        {
            corrector.Start(candidateGeneration);
            scheduler.Start(candidateGeneration);
        }
        catch
        {
            TryStopCorrection();
            TryDispose(candidate);
            return RuntimeOperationResult.Failure("Window correction startup failed");
        }

        var retired = source;
        source = candidate;
        this.selectedMonitor = selectedMonitor;
        this.maskBands = maskBands.ToArray();
        correctionEnabled = true;
        committed = true;
        foreach (var signal in queued)
        {
            HandleSignal(candidateGeneration, signal);
        }

        TryDispose(retired);
        return RuntimeOperationResult.Success();
    }

    public void Pause()
    {
        if (disposed || !correctionEnabled)
        {
            return;
        }

        correctionEnabled = false;
        generation++;
        TryStopCorrection();
    }

    public void Stop()
    {
        if (source is null && selectedMonitor is null && !correctionEnabled)
        {
            return;
        }

        correctionEnabled = false;
        generation++;
        TryStopCorrection();
        var retired = source;
        source = null;
        selectedMonitor = null;
        maskBands = [];
        TryDispose(retired);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        Stop();
        disposed = true;
    }

    private void PauseForReplacement()
    {
        if (source is null && !correctionEnabled)
        {
            return;
        }

        correctionEnabled = false;
        generation++;
        TryStopCorrection();
    }

    private void HandleSignal(long signalGeneration, WinEventSignal signal)
    {
        if (!correctionEnabled ||
            signalGeneration != generation ||
            signal.Generation != signalGeneration ||
            signal.Window == 0 ||
            (IsObjectEvent(signal.EventType) &&
                (signal.ObjectId != 0 || signal.ChildId != 0)))
        {
            return;
        }

        var key = signal.Window.ToInt64();
        try
        {
            scheduler.Signal(
                key,
                _ => RunCorrection(signalGeneration, signal.Window));
        }
        catch
        {
        }
    }

    private void RunCorrection(long correctionGeneration, nint window)
    {
        if (!correctionEnabled ||
            correctionGeneration != generation ||
            selectedMonitor is not { } monitor)
        {
            return;
        }

        try
        {
            corrector.Correct(
                correctionGeneration,
                window,
                monitor,
                maskBands);
        }
        catch
        {
        }
    }

    private bool IsSameConfiguration(
        SelectedMonitor selectedMonitor,
        IReadOnlyList<RectD> maskBands) =>
        this.selectedMonitor == selectedMonitor &&
        this.maskBands.SequenceEqual(maskBands);

    private void TryStopCorrection()
    {
        try
        {
            scheduler.Stop();
        }
        catch
        {
        }

        try
        {
            corrector.Stop();
        }
        catch
        {
        }
    }

    private static void TryDispose(IWinEventSource? eventSource)
    {
        try
        {
            eventSource?.Dispose();
        }
        catch
        {
        }
    }

    private static bool IsObjectEvent(uint eventType) =>
        eventType >= WinEventId.ObjectCreate;
}
