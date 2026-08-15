using ScreenFix.Core.Displays;
using ScreenFix.Core.Configuration;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Menu;

namespace ScreenFix.App.Runtime;

public readonly record struct RuntimeOperationResult(bool IsSuccess, string? Error)
{
    public static RuntimeOperationResult Success() => new(true, null);

    public static RuntimeOperationResult Failure(string error) => new(false, error);
}

public sealed record CalibrationStartRequest(
    long Generation,
    ConnectedDisplay Display,
    IReadOnlyList<RectD> Bands);

public sealed record CalibrationHostCallbacks(
    Action<long, IReadOnlyList<RectD>> Save,
    Action<long> Cancel,
    Action<long> DpiChanged);

public interface ICalibrationHost
{
    bool IsEditing { get; }

    RuntimeOperationResult Start(
        CalibrationStartRequest request,
        CalibrationHostCallbacks callbacks);

    void Stop();
}

public interface IRuntimeConfigStore
{
    ConfigLoadResult Load();

    void Save(ScreenFixConfig value);
}

public interface IDisplayTopology
{
    IReadOnlyList<ConnectedDisplay> Enumerate();

    bool TryGetMonitorHandle(ConnectedDisplay display, out nint monitorHandle)
    {
        monitorHandle = 0;
        return false;
    }
}

public interface IMaskOverlayHost
{
    RuntimeOperationResult Replace(IReadOnlyList<RectD> frames);

    void Clear();
}

public interface IMonitorPickerHost
{
    RuntimeOperationResult Start(
        long generation,
        IReadOnlyList<ConnectedDisplay> displays,
        Action<long, ConnectedDisplay> selected,
        Action<long> cancelled);

    void Stop();
}

public interface IMenuHost
{
    void Refresh(IReadOnlyList<MenuRow> rows);
}

public interface IUiThread
{
    void VerifyAccess();
}

public interface INoticeSink
{
    void Show(string message);
}

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}
