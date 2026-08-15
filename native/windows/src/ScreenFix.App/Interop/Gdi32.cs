using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

internal static partial class Gdi32
{
    internal static readonly nint InvalidObject = new(-1);

    [LibraryImport("gdi32.dll", SetLastError = true)]
    internal static partial nint CreateCompatibleDC(nint deviceContext);

    [LibraryImport("gdi32.dll", SetLastError = true)]
    internal static partial int DeleteDC(nint deviceContext);

    [LibraryImport("gdi32.dll", SetLastError = true)]
    internal static partial nint SelectObject(nint deviceContext, nint graphicsObject);

    [LibraryImport("gdi32.dll", SetLastError = true)]
    internal static partial int DeleteObject(nint graphicsObject);
}
