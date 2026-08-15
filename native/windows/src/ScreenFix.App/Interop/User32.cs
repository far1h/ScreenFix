using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

internal static partial class User32
{
    internal const int WindowExtendedStyleLayered = 0x00080000;
    internal const int WindowExtendedStyleTransparent = 0x00000020;
    internal const int WindowExtendedStyleNoActivate = 0x08000000;
    internal const int WindowExtendedStyleToolWindow = 0x00000080;
    internal const uint LayeredWindowAlpha = 0x00000002;
    internal const byte AlphaSourceOver = 0x00;
    internal const byte AlphaSourceAlpha = 0x01;
    internal const uint SetWindowPositionNoActivate = 0x0010;
    internal const uint SetWindowPositionShowWindow = 0x0040;
    internal const uint SetWindowPositionNoOwnerZOrder = 0x0200;
    internal static readonly nint TopMostWindow = new(-1);

    internal delegate int MonitorEnumProcedure(
        nint monitor,
        nint monitorDeviceContext,
        nint monitorRectangle,
        nint state);

#pragma warning disable SYSLIB1054
    [DllImport("user32.dll", SetLastError = true)]
    internal static extern int EnumDisplayMonitors(
        nint deviceContext,
        nint clipRectangle,
        MonitorEnumProcedure callback,
        nint state);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern int GetMonitorInfo(nint monitor, ref MonitorInfoEx monitorInfo);

    [DllImport("user32.dll", EntryPoint = "EnumDisplayDevicesW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern int EnumDisplayDevices(
        string deviceName,
        uint deviceNumber,
        ref DisplayDevice displayDevice,
        uint flags);
#pragma warning restore SYSLIB1054

    [LibraryImport("user32.dll", SetLastError = true)]
    internal static partial int SetLayeredWindowAttributes(
        nint window,
        uint colorKey,
        byte alpha,
        uint flags);

    [LibraryImport("user32.dll", SetLastError = true)]
    internal static partial int SetWindowPos(
        nint window,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [LibraryImport("user32.dll", SetLastError = true)]
    internal static partial int GetWindowRect(nint window, out NativeRect rectangle);

    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint window);

    [LibraryImport("user32.dll")]
    internal static partial nint GetDC(nint window);

    [LibraryImport("user32.dll")]
    internal static partial int ReleaseDC(nint window, nint deviceContext);

    [LibraryImport("user32.dll", SetLastError = true)]
    internal static partial int UpdateLayeredWindow(
        nint window,
        nint destinationDeviceContext,
        in NativePoint destination,
        in NativeSize size,
        nint sourceDeviceContext,
        in NativePoint source,
        uint colorKey,
        in NativeBlendFunction blend,
        uint flags);
}
