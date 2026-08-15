using ScreenFix.App.Displays;
using ScreenFix.App.Notifications;
using ScreenFix.App.Overlays;
using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Runtime;

internal sealed class RuntimeConfigStore(string path) : IRuntimeConfigStore
{
    private readonly JsonConfigStore store = new(path);

    public ConfigLoadResult Load() => store.Load();

    public void Save(ScreenFixConfig value) => store.Save(value);
}

internal sealed class RuntimeDisplayTopology : IDisplayTopology
{
    private readonly WindowsDisplayTopology topology = new();
    private IReadOnlyList<WindowsDisplay> snapshot = [];

    public IReadOnlyList<ConnectedDisplay> Enumerate()
    {
        snapshot = topology.Enumerate();
        return snapshot.Select(display => display.Descriptor).ToArray();
    }

    public bool TryGetMonitorHandle(
        ConnectedDisplay display,
        out nint monitorHandle)
    {
        var match = snapshot.SingleOrDefault(candidate => candidate.Descriptor == display);
        monitorHandle = match?.MonitorHandle ?? 0;
        return match is not null && monitorHandle != 0;
    }
}

internal sealed class RuntimeMaskOverlayHost(MaskOverlaySet overlays) : IMaskOverlayHost
{
    public RuntimeOperationResult Replace(IReadOnlyList<RectD> frames)
    {
        var result = overlays.Replace(frames);
        return new RuntimeOperationResult(result.IsSuccess, result.Error);
    }

    public void Clear() => overlays.Clear();
}

internal sealed class WinFormsUiBridge : Control, IUiThread, IUiDispatcher
{
    private readonly int threadId = Environment.CurrentManagedThreadId;

    public WinFormsUiBridge()
    {
        _ = Handle;
    }

    public void VerifyAccess()
    {
        if (Environment.CurrentManagedThreadId != threadId)
        {
            throw new InvalidOperationException("ScreenFix state must run on its WinForms UI thread");
        }
    }

    public void Post(Action action)
    {
        ArgumentNullException.ThrowIfNull(action);
        if (!IsDisposed && IsHandleCreated)
        {
            BeginInvoke(action);
        }
    }
}

internal sealed class NotifyIconNoticeSink(NotifyIcon icon) : INoticeSink
{
    public void Show(string message)
    {
        icon.BalloonTipIcon = ToolTipIcon.Warning;
        icon.BalloonTipTitle = "ScreenFix";
        icon.BalloonTipText = message;
        icon.ShowBalloonTip(5_000);
    }
}

internal sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}
