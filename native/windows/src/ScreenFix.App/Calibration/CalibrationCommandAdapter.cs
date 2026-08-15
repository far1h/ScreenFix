using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Calibration;

public sealed class CalibrationCommandAdapter(
    CalibrationSession session,
    Action releaseCapture)
{
    public void Save(Action<IReadOnlyList<RectD>> callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        session.Save();
        releaseCapture();
        callback(session.WorkingBands.ToArray());
    }

    public void Cancel(Action callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        session.Cancel();
        releaseCapture();
        callback();
    }
}
