using System.Runtime.InteropServices;
using ScreenFix.App.Interop;

namespace ScreenFix.App.Tests;

public sealed class NativeWindowPlacementTests
{
    [Fact]
    public void WindowsAbiIsExactlyFortyFourBytes()
    {
        Assert.Equal(44, Marshal.SizeOf<NativeWindowPlacement>());
    }
}
