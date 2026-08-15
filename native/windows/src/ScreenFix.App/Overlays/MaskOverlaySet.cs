using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Overlays;

public interface IMaskSurface : IDisposable
{
    void Prepare(RectD nativeBounds);

    void ShowNoActivate();

    bool IsReady { get; }
}

public interface IMaskSurfaceFactory
{
    IMaskSurface Create();
}

public readonly record struct MaskReplaceResult(bool IsSuccess, string? Error)
{
    public static MaskReplaceResult Success() => new(true, null);

    public static MaskReplaceResult Failure(string error) => new(false, error);
}

public sealed class MaskOverlaySet(IMaskSurfaceFactory factory) : IDisposable
{
    private IReadOnlyList<IMaskSurface> committed = [];
    private bool disposed;

    public MaskReplaceResult Replace(IReadOnlyList<RectD> nativeFrames)
    {
        ArgumentNullException.ThrowIfNull(nativeFrames);
        if (disposed)
        {
            return MaskReplaceResult.Failure("mask owner is stopped");
        }

        if (nativeFrames.Count != 3 || nativeFrames.Any(frame => !IsValidFrame(frame)))
        {
            return MaskReplaceResult.Failure("exactly three valid mask frames are required");
        }

        var candidates = new List<IMaskSurface>(3);
        try
        {
            foreach (var frame in nativeFrames)
            {
                var candidate = factory.Create();
                candidates.Add(candidate);
                candidate.Prepare(frame);
            }

            foreach (var candidate in candidates)
            {
                candidate.ShowNoActivate();
            }

            if (candidates.Any(candidate => !candidate.IsReady))
            {
                throw new InvalidOperationException("mask candidate is not ready");
            }
        }
        catch (Exception error)
        {
            DisposeAll(candidates);
            return MaskReplaceResult.Failure(error.Message);
        }

        var retired = committed;
        committed = candidates;
        DisposeAll(retired);
        return MaskReplaceResult.Success();
    }

    public void Clear()
    {
        var retired = committed;
        committed = [];
        DisposeAll(retired);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        Clear();
    }

    private static bool IsValidFrame(RectD frame) =>
        IsFinite(frame.X) &&
        IsFinite(frame.Y) &&
        IsFinite(frame.Width) &&
        IsFinite(frame.Height) &&
        frame.Width > 0 &&
        frame.Height > 0;

    private static bool IsFinite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);

    private static void DisposeAll(IEnumerable<IMaskSurface> surfaces)
    {
        foreach (var surface in surfaces)
        {
            try
            {
                surface.Dispose();
            }
            catch
            {
            }
        }
    }
}
