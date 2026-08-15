using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.App.Guard;

[Flags]
public enum NativeWindowStyle : long
{
    None = 0,
    ThickFrame = 0x00040000,
    Caption = 0x00C00000,
    Popup = 0x80000000,
}

[Flags]
public enum NativeWindowExtendedStyle : long
{
    None = 0,
    ToolWindow = 0x00000080,
}

public readonly record struct WindowStyleData(long Style, long ExtendedStyle);

public readonly record struct SelectedMonitor(
    nint Handle,
    RectD FullBounds,
    RectD WorkArea);

public readonly record struct WindowFrameOffsets(
    double Left,
    double Top,
    double Right,
    double Bottom);

public sealed record WindowInspection(
    WindowFacts Facts,
    bool IsZoomed,
    RectD OuterFrame,
    WindowFrameOffsets FrameOffsets);

public interface IWindowInspector
{
    WindowInspection? TryInspect(nint window, SelectedMonitor selectedMonitor);
}

public interface IWindowNativeQuery
{
    bool IsWindow(nint window);

    bool IsWindowVisible(nint window);

    bool IsIconic(nint window);

    bool IsZoomed(nint window);

    bool TryGetStyles(nint window, out WindowStyleData styles);

    bool TryGetProcessId(nint window, out uint processId);

    bool TryGetRoot(nint window, out nint root);

    bool TryGetOwner(nint window, out nint owner);

    nint GetShellWindow();

    nint GetDesktopWindow();

    bool TryGetClassName(nint window, out string className);

    bool TryGetOuterFrame(nint window, out RectD frame);

    bool TryGetExtendedFrame(nint window, out RectD frame);

    nint MonitorFromFrame(RectD frame);
}
