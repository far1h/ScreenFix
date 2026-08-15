using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;

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
