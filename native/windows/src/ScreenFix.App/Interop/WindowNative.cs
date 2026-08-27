using System.Runtime.InteropServices;
using ScreenFix.App.Guard;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Interop;

internal sealed partial class WindowNative :
    IWindowNativeQuery,
    IWindowNativeWriter,
    IWinEventNativeApi
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

    public bool TryGetThreadProcessId(
        nint window,
        out uint threadId,
        out uint processId)
    {
        threadId = GetWindowThreadProcessId(window, out processId);
        return threadId != 0;
    }

    public bool IsCurrent(WindowIdentity window) =>
        TryGetThreadProcessId(window.Handle, out var threadId, out var processId) &&
        threadId == window.ThreadId &&
        processId == window.ProcessId;

    public bool TryGetRoot(nint window, out nint root)
    {
        Marshal.SetLastPInvokeError(0);
        root = GetAncestor(window, AncestorRoot);
        return root != 0;
    }

    public bool TryGetOwner(nint window, out nint owner)
    {
        Marshal.SetLastPInvokeError(0);
        owner = GetWindow(window, OwnerWindow);
        return owner != 0 || Marshal.GetLastPInvokeError() == 0;
    }

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

    public bool TryGetPlacement(
        WindowIdentity window,
        out WindowPlacementData placement)
    {
        if (!IsCurrent(window))
        {
            placement = default;
            return false;
        }

        var native = new NativeWindowPlacement
        {
            Length = (uint)Marshal.SizeOf<NativeWindowPlacement>(),
        };
        if (GetWindowPlacementNative(window.Handle, ref native) == 0)
        {
            placement = default;
            return false;
        }

        placement = ToPlacementData(native);
        return true;
    }

    public bool TrySetPlacement(
        WindowIdentity window,
        WindowPlacementData placement)
    {
        if (!IsCurrent(window))
        {
            return false;
        }

        var native = ToNativePlacement(placement);
        return SetWindowPlacementNative(window.Handle, in native) != 0;
    }

    public bool TrySetFrame(
        WindowIdentity window,
        NativeWindowFrame frame,
        uint flags)
    {
        if (!IsCurrent(window))
        {
            return false;
        }

        return User32.SetWindowPos(
                window.Handle,
                insertAfter: 0,
                frame.X,
                frame.Y,
                frame.Width,
                frame.Height,
                flags) != 0;
    }

    public nint SetHook(
        uint eventMinimum,
        uint eventMaximum,
        NativeWinEventCallback callback,
        uint processId,
        uint threadId,
        uint flags) =>
        SetWinEventHook(
            eventMinimum,
            eventMaximum,
            module: 0,
            callback,
            processId,
            threadId,
            flags);

    public bool Unhook(nint hook) => UnhookWinEvent(hook);

    public bool TryEnumerateWindows(out IReadOnlyList<nint> windows)
    {
        var found = new List<nint>();
        EnumWindowsCallback callback = (window, state) =>
        {
            _ = state;
            found.Add(window);
            return true;
        };
        var succeeded = EnumWindows(callback, 0);
        GC.KeepAlive(callback);
        windows = succeeded ? found : [];
        return succeeded;
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

    private static WindowPlacementData ToPlacementData(
        NativeWindowPlacement placement) => new(
        placement.Flags,
        placement.ShowCommand,
        new NativeWindowPoint(
            placement.MinimizedPosition.X,
            placement.MinimizedPosition.Y),
        new NativeWindowPoint(
            placement.MaximizedPosition.X,
            placement.MaximizedPosition.Y),
        new NativeWindowRectangle(
            placement.NormalPosition.Left,
            placement.NormalPosition.Top,
            placement.NormalPosition.Right,
            placement.NormalPosition.Bottom));

    private static NativeWindowPlacement ToNativePlacement(
        WindowPlacementData placement) => new()
        {
            Length = (uint)Marshal.SizeOf<NativeWindowPlacement>(),
            Flags = placement.Flags,
            ShowCommand = placement.ShowCommand,
            MinimizedPosition = new NativePoint(
                placement.MinimizedPosition.X,
                placement.MinimizedPosition.Y),
            MaximizedPosition = new NativePoint(
                placement.MaximizedPosition.X,
                placement.MaximizedPosition.Y),
            NormalPosition = new NativeRect
            {
                Left = placement.NormalPosition.Left,
                Top = placement.NormalPosition.Top,
                Right = placement.NormalPosition.Right,
                Bottom = placement.NormalPosition.Bottom,
            },
        };

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

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial nint GetWindow(nint window, uint command);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static partial nint GetWindowLongPtr(nint window, int index);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowPlacement", SetLastError = true)]
    private static partial int GetWindowPlacementNative(
        nint window,
        ref NativeWindowPlacement placement);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowPlacement", SetLastError = true)]
    private static partial int SetWindowPlacementNative(
        nint window,
        in NativeWindowPlacement placement);

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

#pragma warning disable SYSLIB1054
    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWinEventHook(
        uint eventMinimum,
        uint eventMaximum,
        nint module,
        NativeWinEventCallback callback,
        uint processId,
        uint threadId,
        uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(
        EnumWindowsCallback callback,
        nint state);
#pragma warning restore SYSLIB1054

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnhookWinEvent(nint hook);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumWindowsCallback(nint window, nint state);
}
