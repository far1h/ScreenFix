using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Displays;

public sealed record MonitorRecord(
    string GdiDeviceName,
    string FallbackName,
    RectD FullBounds,
    RectD WorkArea);

public sealed record ActivePathRecord(
    string GdiDeviceName,
    string? TargetDevicePath,
    string? FriendlyName);

public static class DisplayTopologyBuilder
{
    public static IReadOnlyList<ConnectedDisplay> Build(
        IReadOnlyList<MonitorRecord> monitors,
        IReadOnlyList<ActivePathRecord> activePaths)
    {
        ArgumentNullException.ThrowIfNull(monitors);
        ArgumentNullException.ThrowIfNull(activePaths);

        return monitors
            .Where(monitor => IsValidFrame(monitor.FullBounds))
            .OrderBy(monitor => monitor.FullBounds.X)
            .ThenBy(monitor => monitor.FullBounds.Y)
            .ThenBy(monitor => monitor.GdiDeviceName, StringComparer.Ordinal)
            .Select(monitor =>
        {
            var paths = activePaths.Where(path =>
                StringComparer.OrdinalIgnoreCase.Equals(
                    path.GdiDeviceName,
                    monitor.GdiDeviceName)).ToArray();
            var path = paths.Length == 1 ? paths[0] : null;
            var hasTargetFriendlyName = !string.IsNullOrWhiteSpace(path?.FriendlyName);
            var hasFallbackName = !string.IsNullOrWhiteSpace(monitor.FallbackName);
            var name = hasTargetFriendlyName
                ? path!.FriendlyName!
                : hasFallbackName
                    ? monitor.FallbackName
                    : monitor.GdiDeviceName;

            return new ConnectedDisplay(
                path?.TargetDevicePath,
                name,
                checked((int)monitor.FullBounds.Width),
                checked((int)monitor.FullBounds.Height),
                monitor.FullBounds,
                monitor.WorkArea,
                hasTargetFriendlyName || hasFallbackName);
        }).ToArray();
    }

    private static bool IsValidFrame(RectD frame) =>
        IsFinite(frame.X) &&
        IsFinite(frame.Y) &&
        IsFinite(frame.Width) &&
        IsFinite(frame.Height) &&
        frame.Width > 0 &&
        frame.Height > 0 &&
        frame.Width <= int.MaxValue &&
        frame.Height <= int.MaxValue &&
        frame.Width == Math.Truncate(frame.Width) &&
        frame.Height == Math.Truncate(frame.Height);

    private static bool IsFinite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
}
