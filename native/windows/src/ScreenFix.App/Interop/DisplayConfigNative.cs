using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

internal static partial class DisplayConfigNative
{
    internal const uint QueryOnlyActivePaths = 0x00000002;
    internal const uint QueryVirtualModeAware = 0x00000010;
    internal const int ErrorSuccess = 0;
    internal const int ErrorInsufficientBuffer = 122;
    internal const uint GetSourceName = 1;
    internal const uint GetTargetName = 2;

    [LibraryImport("user32.dll")]
    internal static partial int GetDisplayConfigBufferSizes(
        uint flags,
        out uint pathCount,
        out uint modeCount);

    [LibraryImport("user32.dll")]
    internal static partial int QueryDisplayConfig(
        uint flags,
        ref uint pathCount,
        nint paths,
        ref uint modeCount,
        nint modes,
        nint currentTopologyId);

    [LibraryImport("user32.dll")]
    internal static partial int DisplayConfigGetDeviceInfo(nint requestPacket);
}
