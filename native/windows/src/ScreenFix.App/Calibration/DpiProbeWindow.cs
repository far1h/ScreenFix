using System.ComponentModel;
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;

namespace ScreenFix.App.Calibration;

internal sealed class DpiProbeWindow : NativeWindow, IDisposable
{
    private bool disposed;

    private DpiProbeWindow(Rectangle monitorBounds)
    {
        var parameters = new CreateParams
        {
            Caption = "ScreenFix DPI probe",
            X = monitorBounds.Left,
            Y = monitorBounds.Top,
            Width = 1,
            Height = 1,
            Style = unchecked((int)0x80000000),
            ExStyle = User32.WindowExtendedStyleNoActivate |
                User32.WindowExtendedStyleToolWindow,
        };
        CreateHandle(parameters);
    }

    public static uint ReadDpi(Rectangle monitorBounds)
    {
        using var probe = new DpiProbeWindow(monitorBounds);
        var dpi = User32.GetDpiForWindow(probe.Handle);
        if (dpi == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "display DPI lookup failed");
        }

        return dpi;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        DestroyHandle();
    }
}
