using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

internal static partial class DwmApi
{
    private const uint ExtendedFrameBounds = 9;

    internal static bool TryGetExtendedFrame(nint window, out NativeRect rectangle) =>
        DwmGetWindowAttribute(
            window,
            ExtendedFrameBounds,
            out rectangle,
            (uint)Marshal.SizeOf<NativeRect>()) >= 0;

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmGetWindowAttribute(
        nint window,
        uint attribute,
        out NativeRect value,
        uint valueSize);
}
