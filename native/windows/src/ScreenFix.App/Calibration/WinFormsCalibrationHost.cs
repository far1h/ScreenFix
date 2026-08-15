using ScreenFix.App.Runtime;
using ScreenFix.Core.Calibration;

namespace ScreenFix.App.Calibration;

internal sealed class WinFormsCalibrationHost(Action? dpiChanged = null) : ICalibrationHost
{
    private CalibrationForm? editor;

    public bool IsEditing => editor is not null;

    public RuntimeOperationResult Start(
        CalibrationStartRequest request,
        CalibrationHostCallbacks callbacks)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(callbacks);

        CalibrationForm? candidate = null;
        try
        {
            var bounds = ToRectangle(request.Display.FullBounds);
            var dpi = DpiProbeWindow.ReadDpi(bounds);
            var logicalWidth = bounds.Width * 96d / dpi;
            var logicalHeight = bounds.Height * 96d / dpi;
            var layoutResult = CalibrationLayout.TryCreate(logicalWidth, logicalHeight);
            if (!layoutResult.IsSuccess)
            {
                return RuntimeOperationResult.Failure(layoutResult.Error!);
            }

            var routedCallbacks = dpiChanged is null
                ? callbacks
                : callbacks with { DpiChanged = _ => dpiChanged() };
            candidate = new CalibrationForm(
                bounds,
                dpi,
                request.Generation,
                request.Bands,
                layoutResult.Value!,
                routedCallbacks);
            candidate.PrepareAndShow();
        }
        catch (Exception error)
        {
            candidate?.Dispose();
            return RuntimeOperationResult.Failure(error.Message);
        }

        var retired = editor;
        editor = candidate;
        retired?.Close();
        retired?.Dispose();
        return RuntimeOperationResult.Success();
    }

    public void Stop()
    {
        editor?.Dispose();
        editor = null;
    }

    private static Rectangle ToRectangle(ScreenFix.Core.Geometry.RectD bounds)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0 ||
            bounds.X != Math.Truncate(bounds.X) ||
            bounds.Y != Math.Truncate(bounds.Y) ||
            bounds.Width != Math.Truncate(bounds.Width) ||
            bounds.Height != Math.Truncate(bounds.Height))
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }

        return new Rectangle(
            checked((int)bounds.X),
            checked((int)bounds.Y),
            checked((int)bounds.Width),
            checked((int)bounds.Height));
    }
}
