using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.App.Guard;

public sealed class WindowsWindowInspector(
    IWindowNativeQuery query,
    uint screenFixProcessId) : IWindowInspector
{
    public WindowInspection? TryInspect(
        nint window,
        SelectedMonitor selectedMonitor)
    {
        if (window == 0 || !query.IsWindow(window) ||
            !query.TryGetStyles(window, out var styles) ||
            !query.TryGetProcessId(window, out var processId) ||
            !query.TryGetRoot(window, out var root) ||
            !query.TryGetOwner(window, out var owner) ||
            !query.TryGetClassName(window, out var className) ||
            !query.TryGetOuterFrame(window, out var outerFrame) ||
            !IsValid(outerFrame))
        {
            return null;
        }

        var visibleFrame = query.TryGetExtendedFrame(window, out var extendedFrame) &&
            IsValid(extendedFrame)
            ? extendedFrame
            : outerFrame;
        var ordinaryStyle = HasStyle(styles.Style, NativeWindowStyle.Caption) ||
            HasStyle(styles.Style, NativeWindowStyle.ThickFrame);
        var popupOnly = HasStyle(styles.Style, NativeWindowStyle.Popup) &&
            !ordinaryStyle;
        var toolOrMenu = HasExtendedStyle(
                styles.ExtendedStyle,
                NativeWindowExtendedStyle.ToolWindow) ||
            StringComparer.Ordinal.Equals(className, "#32768") ||
            popupOnly;
        var shellWindow = query.GetShellWindow();
        var desktopWindow = query.GetDesktopWindow();
        var frameOffsets = new WindowFrameOffsets(
            visibleFrame.X - outerFrame.X,
            visibleFrame.Y - outerFrame.Y,
            outerFrame.Right - visibleFrame.Right,
            outerFrame.Bottom - visibleFrame.Bottom);
        var facts = new WindowFacts(
            window.ToInt64(),
            visibleFrame,
            query.IsWindowVisible(window),
            query.IsIconic(window),
            root == window,
            owner != 0,
            processId == screenFixProcessId,
            window == shellWindow || window == desktopWindow,
            toolOrMenu,
            ordinaryStyle,
            !ordinaryStyle && Near(visibleFrame, selectedMonitor.FullBounds),
            query.MonitorFromFrame(visibleFrame) == selectedMonitor.Handle);
        return new WindowInspection(
            facts,
            query.IsZoomed(window),
            outerFrame,
            frameOffsets);
    }

    private static bool HasStyle(long value, NativeWindowStyle style) =>
        (value & (long)style) == (long)style;

    private static bool HasExtendedStyle(
        long value,
        NativeWindowExtendedStyle style) =>
        (value & (long)style) == (long)style;

    private static bool Near(RectD first, RectD second) =>
        Math.Abs(first.X - second.X) <= 1 &&
        Math.Abs(first.Y - second.Y) <= 1 &&
        Math.Abs(first.Right - second.Right) <= 1 &&
        Math.Abs(first.Bottom - second.Bottom) <= 1;

    private static bool IsValid(RectD frame) =>
        double.IsFinite(frame.X) &&
        double.IsFinite(frame.Y) &&
        double.IsFinite(frame.Width) &&
        double.IsFinite(frame.Height) &&
        double.IsFinite(frame.Right) &&
        double.IsFinite(frame.Bottom) &&
        frame.Width > 0 &&
        frame.Height > 0;
}
