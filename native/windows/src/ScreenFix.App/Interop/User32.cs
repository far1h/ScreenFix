using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

internal static partial class User32
{
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
}
