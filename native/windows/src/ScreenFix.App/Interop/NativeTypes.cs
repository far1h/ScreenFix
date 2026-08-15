using System.Runtime.InteropServices;

namespace ScreenFix.App.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRect
{
    internal int Left;
    internal int Top;
    internal int Right;
    internal int Bottom;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativePoint(int x, int y)
{
    internal int X = x;
    internal int Y = y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeSize(int width, int height)
{
    internal int Width = width;
    internal int Height = height;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
internal struct NativeBlendFunction
{
    internal byte BlendOperation;
    internal byte BlendFlags;
    internal byte SourceConstantAlpha;
    internal byte AlphaFormat;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct MonitorInfoEx
{
    internal uint Size;
    internal NativeRect Monitor;
    internal NativeRect Work;
    internal uint Flags;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    internal string DeviceName;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct DisplayDevice
{
    internal uint Size;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    internal string DeviceName;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    internal string DeviceString;

    internal uint StateFlags;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    internal string DeviceId;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    internal string DeviceKey;
}

[StructLayout(LayoutKind.Sequential)]
internal struct LocallyUniqueIdentifier
{
    internal uint LowPart;
    internal int HighPart;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigRational
{
    internal uint Numerator;
    internal uint Denominator;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigPathSourceInfo
{
    internal LocallyUniqueIdentifier AdapterId;
    internal uint Id;
    internal uint ModeInfoIndex;
    internal uint StatusFlags;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigPathTargetInfo
{
    internal LocallyUniqueIdentifier AdapterId;
    internal uint Id;
    internal uint ModeInfoIndex;
    internal uint OutputTechnology;
    internal uint Rotation;
    internal uint Scaling;
    internal DisplayConfigRational RefreshRate;
    internal uint ScanLineOrdering;
    internal int TargetAvailable;
    internal uint StatusFlags;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigPathInfo
{
    internal DisplayConfigPathSourceInfo SourceInfo;
    internal DisplayConfigPathTargetInfo TargetInfo;
    internal uint Flags;
}

[StructLayout(LayoutKind.Explicit, Size = 48)]
internal struct DisplayConfigModeInfoUnion
{
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigModeInfo
{
    internal uint InfoType;
    internal uint Id;
    internal LocallyUniqueIdentifier AdapterId;
    internal DisplayConfigModeInfoUnion ModeInfo;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DisplayConfigDeviceInfoHeader
{
    internal uint Type;
    internal uint Size;
    internal LocallyUniqueIdentifier AdapterId;
    internal uint Id;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct DisplayConfigSourceDeviceName
{
    internal DisplayConfigDeviceInfoHeader Header;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    internal string ViewGdiDeviceName;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct DisplayConfigTargetDeviceName
{
    internal DisplayConfigDeviceInfoHeader Header;
    internal uint Flags;
    internal uint OutputTechnology;
    internal ushort EdidManufactureId;
    internal ushort EdidProductCodeId;
    internal uint ConnectorInstance;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
    internal string MonitorFriendlyDeviceName;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    internal string MonitorDevicePath;
}
