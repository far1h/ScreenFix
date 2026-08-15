using System.Runtime.InteropServices;
using ScreenFix.App.Guard;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Interop;

internal sealed partial class WindowNative : IWindowNativeQuery
{
    private const uint AncestorRoot = 2;
    private const uint OwnerWindow = 4;
    private const int WindowStyleIndex = -16;
    private const int WindowExtendedStyleIndex = -20;
    private const uint MonitorDefaultToNull = 0;

    bool IWindowNativeQuery.IsWindow(nint window) => IsWindow(window);

    bool IWindowNativeQuery.IsWindowVisible(nint window) => IsWindowVisible(window);

    bool IWindowNativeQuery.IsIconic(nint window) => IsIconic(window);

    bool IWindowNativeQuery.IsZoomed(nint window) => IsZoomed(window);

    public bool TryGetStyles(nint window, out WindowStyleData styles)
    {
        if (!TryGetWindowLong(window, WindowStyleIndex, out var style) ||
            !TryGetWindowLong(window, WindowExtendedStyleIndex, out var extendedStyle))
        {
            styles = default;
            return false;
        }

        styles = new WindowStyleData(style.ToInt64(), extendedStyle.ToInt64());
        return true;
    }

    public bool TryGetProcessId(nint window, out uint processId) =>
        GetWindowThreadProcessId(window, out processId) != 0;

    public bool TryGetRoot(nint window, out nint root)
    {
        Marshal.SetLastPInvokeError(0);
        root = GetAncestor(window, AncestorRoot);
        return root != 0;
    }

    public nint GetOwner(nint window) => GetWindow(window, OwnerWindow);

    nint IWindowNativeQuery.GetShellWindow() => GetShellWindow();

    nint IWindowNativeQuery.GetDesktopWindow() => GetDesktopWindow();

    public bool TryGetClassName(nint window, out string className)
    {
        var buffer = new char[256];
        var length = GetClassName(window, buffer, buffer.Length);
        if (length <= 0)
        {
            className = string.Empty;
            return false;
        }

        className = new string(buffer, 0, length);
        return true;
    }

    public bool TryGetOuterFrame(nint window, out RectD frame)
    {
        if (User32.GetWindowRect(window, out var rectangle) == 0)
        {
            frame = default;
            return false;
        }

        frame = ToRectD(rectangle);
        return true;
    }

    public bool TryGetExtendedFrame(nint window, out RectD frame)
    {
        if (!DwmApi.TryGetExtendedFrame(window, out var rectangle))
        {
            frame = default;
            return false;
        }

        frame = ToRectD(rectangle);
        return true;
    }

    public nint MonitorFromFrame(RectD frame)
    {
        if (!TryToNativeRect(frame, out var rectangle))
        {
            return 0;
        }

        return MonitorFromRect(in rectangle, MonitorDefaultToNull);
    }

    private static bool TryGetWindowLong(nint window, int index, out nint value)
    {
        Marshal.SetLastPInvokeError(0);
        value = GetWindowLongPtr(window, index);
        return value != 0 || Marshal.GetLastPInvokeError() == 0;
    }

    private static RectD ToRectD(NativeRect rectangle) => new(
        rectangle.Left,
        rectangle.Top,
        rectangle.Right - rectangle.Left,
        rectangle.Bottom - rectangle.Top);

    private static bool TryToNativeRect(RectD frame, out NativeRect rectangle)
    {
        try
        {
            if (!double.IsFinite(frame.X) ||
                !double.IsFinite(frame.Y) ||
                !double.IsFinite(frame.Right) ||
                !double.IsFinite(frame.Bottom) ||
                frame.X != Math.Truncate(frame.X) ||
                frame.Y != Math.Truncate(frame.Y) ||
                frame.Right != Math.Truncate(frame.Right) ||
                frame.Bottom != Math.Truncate(frame.Bottom))
            {
                rectangle = default;
                return false;
            }

            rectangle = new NativeRect
            {
                Left = checked((int)frame.X),
                Top = checked((int)frame.Y),
                Right = checked((int)frame.Right),
                Bottom = checked((int)frame.Bottom),
            };
            return true;
        }
        catch (OverflowException)
        {
            rectangle = default;
            return false;
        }
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindow(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindowVisible(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsIconic(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsZoomed(nint window);

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial nint GetAncestor(nint window, uint flags);

    [LibraryImport("user32.dll")]
    private static partial nint GetWindow(nint window, uint command);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static partial nint GetWindowLongPtr(nint window, int index);

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial uint GetWindowThreadProcessId(nint window, out uint processId);

#pragma warning disable SYSLIB1054
    [DllImport("user32.dll", EntryPoint = "GetClassNameW", SetLastError = true)]
    private static extern int GetClassName(
        nint window,
        [Out] char[] className,
        int maxCount);
#pragma warning restore SYSLIB1054

    [LibraryImport("user32.dll")]
    private static partial nint GetShellWindow();

    [LibraryImport("user32.dll")]
    private static partial nint GetDesktopWindow();

    [LibraryImport("user32.dll")]
    private static partial nint MonitorFromRect(
        in NativeRect rectangle,
        uint flags);
}
