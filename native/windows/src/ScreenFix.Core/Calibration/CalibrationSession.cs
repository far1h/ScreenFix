using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Calibration;

public enum CalibrationAction
{
    None,
    AcquireCapture,
    KeepCapture,
    ReleaseCapture,
    Render,
    Save,
    Cancel,
}

public enum GesturePhase
{
    Idle,
    Pressed,
    Latched,
}

public sealed class CalibrationSession
{
    private const double MovementThreshold = 4;
    private const double HandleSize = 8;
    private const double SnapThreshold = 12;
    private const double MinimumSize = 20;

    private readonly RectD fullFrame;
    private readonly RectD[] workingBands;
    private readonly IReadOnlyList<RectD> readOnlyWorkingBands;
    private int activeIndex = -1;
    private DragPart activePart;
    private PointD pressPoint;
    private PointD lastPoint;
    private RectD rawBand;
    private bool moved;

    public CalibrationSession(IReadOnlyList<RectD> bands, RectD fullFrame)
    {
        ArgumentNullException.ThrowIfNull(bands);
        if (bands.Count != 3)
        {
            throw new ArgumentException("exactly three bands are required", nameof(bands));
        }

        this.fullFrame = fullFrame;
        workingBands = bands.ToArray();
        readOnlyWorkingBands = Array.AsReadOnly(workingBands);
        _ = CalibrationGeometry.HitTest(
            new PointD(fullFrame.X, fullFrame.Y),
            workingBands.Select(band => band.ToAbsolute(fullFrame)).ToArray(),
            HandleSize);
    }

    public GesturePhase Phase { get; private set; }

    public IReadOnlyList<RectD> WorkingBands => readOnlyWorkingBands;

    public CalibrationAction PointerDown(PointD point, bool primaryButton)
    {
        if (!primaryButton)
        {
            return CalibrationAction.None;
        }

        if (Phase == GesturePhase.Latched)
        {
            EndGesture();
            return CalibrationAction.ReleaseCapture;
        }

        if (Phase != GesturePhase.Idle)
        {
            return CalibrationAction.KeepCapture;
        }

        var localBands = workingBands.Select(band => band.ToAbsolute(fullFrame)).ToArray();
        var hit = CalibrationGeometry.HitTest(point, localBands, HandleSize);
        if (hit is null)
        {
            return CalibrationAction.None;
        }

        activeIndex = hit.Value.Index;
        activePart = hit.Value.Part;
        pressPoint = point;
        lastPoint = point;
        rawBand = workingBands[activeIndex];
        moved = false;
        Phase = GesturePhase.Pressed;
        return CalibrationAction.AcquireCapture;
    }

    public CalibrationAction PointerMove(PointD point, bool primaryButtonDown)
    {
        if (Phase == GesturePhase.Idle ||
            (Phase == GesturePhase.Pressed && !primaryButtonDown))
        {
            return CalibrationAction.None;
        }

        if (!moved && Distance(pressPoint, point) < MovementThreshold)
        {
            return CalibrationAction.None;
        }

        var delta = new PointD(point.X - lastPoint.X, point.Y - lastPoint.Y);
        var nextRaw = CalibrationGeometry.DragBand(
            rawBand,
            activePart,
            delta,
            fullFrame,
            MinimumSize);
        var nextVisible = CalibrationGeometry.SnapBand(
            nextRaw,
            activeIndex,
            activePart,
            workingBands,
            fullFrame,
            SnapThreshold,
            MinimumSize);

        rawBand = nextRaw;
        workingBands[activeIndex] = nextVisible;
        lastPoint = point;
        moved = true;
        return CalibrationAction.Render;
    }

    public CalibrationAction PointerUp(PointD point, bool primaryButton)
    {
        _ = point;
        if (!primaryButton || Phase != GesturePhase.Pressed)
        {
            return CalibrationAction.None;
        }

        if (!moved)
        {
            Phase = GesturePhase.Latched;
            return CalibrationAction.KeepCapture;
        }

        EndGesture();
        return CalibrationAction.ReleaseCapture;
    }

    public CalibrationAction Save()
    {
        EndGesture();
        return CalibrationAction.Save;
    }

    public CalibrationAction Cancel()
    {
        EndGesture();
        return CalibrationAction.Cancel;
    }

    public CalibrationAction CaptureLost()
    {
        EndGesture();
        return CalibrationAction.None;
    }

    private static double Distance(PointD first, PointD second)
    {
        var x = second.X - first.X;
        var y = second.Y - first.Y;
        return Math.Sqrt((x * x) + (y * y));
    }

    private void EndGesture()
    {
        activeIndex = -1;
        moved = false;
        Phase = GesturePhase.Idle;
    }
}
