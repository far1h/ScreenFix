using System.ComponentModel;
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Displays;

internal sealed record WindowsDisplay(nint MonitorHandle, ConnectedDisplay Descriptor);

internal sealed class WindowsDisplayTopology
{
    private const int MaximumTopologyAttempts = 3;

    public IReadOnlyList<WindowsDisplay> Enumerate()
    {
        var monitorEntries = EnumerateMonitors();
        var activePaths = TryEnumerateActivePaths();
        var descriptors = DisplayTopologyBuilder.Build(
            monitorEntries.Select(entry => entry.Record).ToArray(),
            activePaths);
        var orderedEntries = monitorEntries
            .Where(entry => entry.Record.FullBounds.Width > 0 && entry.Record.FullBounds.Height > 0)
            .OrderBy(entry => entry.Record.FullBounds.X)
            .ThenBy(entry => entry.Record.FullBounds.Y)
            .ThenBy(entry => entry.Record.GdiDeviceName, StringComparer.Ordinal)
            .ToArray();

        return descriptors.Zip(
            orderedEntries,
            (descriptor, entry) => new WindowsDisplay(entry.Handle, descriptor)).ToArray();
    }

    private static IReadOnlyList<MonitorEntry> EnumerateMonitors()
    {
        var entries = new List<MonitorEntry>();
        Exception? callbackError = null;
        User32.MonitorEnumProcedure callback = (monitor, _, _, _) =>
        {
            try
            {
                var info = new MonitorInfoEx
                {
                    Size = checked((uint)Marshal.SizeOf<MonitorInfoEx>()),
                    DeviceName = string.Empty,
                };
                if (User32.GetMonitorInfo(monitor, ref info) == 0)
                {
                    callbackError = new Win32Exception(
                        Marshal.GetLastPInvokeError(),
                        "monitor information failed");
                    return 0;
                }

                var fallbackName = ReadFallbackName(info.DeviceName);
                entries.Add(new MonitorEntry(
                    monitor,
                    new MonitorRecord(
                        info.DeviceName,
                        fallbackName,
                        ToRect(info.Monitor),
                        ToRect(info.Work))));
                return 1;
            }
            catch (Exception error)
            {
                callbackError = error;
                return 0;
            }
        };

        if (User32.EnumDisplayMonitors(0, 0, callback, 0) == 0)
        {
            if (callbackError is not null)
            {
                throw callbackError;
            }

            throw new Win32Exception(Marshal.GetLastPInvokeError(), "monitor enumeration failed");
        }

        GC.KeepAlive(callback);
        return entries;
    }

    private static string ReadFallbackName(string gdiDeviceName)
    {
        var device = new DisplayDevice
        {
            Size = checked((uint)Marshal.SizeOf<DisplayDevice>()),
            DeviceName = string.Empty,
            DeviceString = string.Empty,
            DeviceId = string.Empty,
            DeviceKey = string.Empty,
        };
        return User32.EnumDisplayDevices(gdiDeviceName, 0, ref device, 0) != 0
            ? device.DeviceString?.Trim() ?? string.Empty
            : string.Empty;
    }

    private static IReadOnlyList<ActivePathRecord> TryEnumerateActivePaths()
    {
        try
        {
            return EnumerateActivePaths();
        }
        catch (DisplayTopologyException)
        {
            return [];
        }
    }

    private static IReadOnlyList<ActivePathRecord> EnumerateActivePaths()
    {
        var flags = DisplayConfigNative.QueryOnlyActivePaths |
            DisplayConfigNative.QueryVirtualModeAware;

        for (var attempt = 0; attempt < MaximumTopologyAttempts; attempt++)
        {
            var sizeResult = DisplayConfigNative.GetDisplayConfigBufferSizes(
                flags,
                out var pathCount,
                out var modeCount);
            if (sizeResult != DisplayConfigNative.ErrorSuccess)
            {
                throw new DisplayTopologyException("display configuration sizing failed", sizeResult);
            }

            using var paths = NativeBuffer<DisplayConfigPathInfo>.Allocate(pathCount);
            using var modes = NativeBuffer<DisplayConfigModeInfo>.Allocate(modeCount);
            var queryResult = DisplayConfigNative.QueryDisplayConfig(
                flags,
                ref pathCount,
                paths.Pointer,
                ref modeCount,
                modes.Pointer,
                0);
            if (queryResult == DisplayConfigNative.ErrorInsufficientBuffer)
            {
                continue;
            }

            if (queryResult != DisplayConfigNative.ErrorSuccess)
            {
                throw new DisplayTopologyException("display configuration query failed", queryResult);
            }

            return Enumerable.Range(0, checked((int)pathCount))
                .Select(index => ReadActivePath(paths.Read(index)))
                .ToArray();
        }

        throw new DisplayTopologyException(
            "display configuration changed continuously",
            DisplayConfigNative.ErrorInsufficientBuffer);
    }

    private static ActivePathRecord ReadActivePath(DisplayConfigPathInfo path)
    {
        var source = new DisplayConfigSourceDeviceName
        {
            Header = new DisplayConfigDeviceInfoHeader
            {
                Type = DisplayConfigNative.GetSourceName,
                Size = checked((uint)Marshal.SizeOf<DisplayConfigSourceDeviceName>()),
                AdapterId = path.SourceInfo.AdapterId,
                Id = path.SourceInfo.Id,
            },
            ViewGdiDeviceName = string.Empty,
        };
        var sourceResult = GetDeviceInfo(ref source);
        if (sourceResult != DisplayConfigNative.ErrorSuccess)
        {
            return new ActivePathRecord(string.Empty, null, null);
        }

        var target = new DisplayConfigTargetDeviceName
        {
            Header = new DisplayConfigDeviceInfoHeader
            {
                Type = DisplayConfigNative.GetTargetName,
                Size = checked((uint)Marshal.SizeOf<DisplayConfigTargetDeviceName>()),
                AdapterId = path.TargetInfo.AdapterId,
                Id = path.TargetInfo.Id,
            },
            MonitorFriendlyDeviceName = string.Empty,
            MonitorDevicePath = string.Empty,
        };
        var targetResult = GetDeviceInfo(ref target);
        return new ActivePathRecord(
            source.ViewGdiDeviceName,
            targetResult == DisplayConfigNative.ErrorSuccess
                ? NullIfWhiteSpace(target.MonitorDevicePath)
                : null,
            targetResult == DisplayConfigNative.ErrorSuccess
                ? NullIfWhiteSpace(target.MonitorFriendlyDeviceName)
                : null);
    }

    private static int GetDeviceInfo<T>(ref T value)
        where T : struct
    {
        var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<T>());
        try
        {
            Marshal.StructureToPtr(value, pointer, false);
            var result = DisplayConfigNative.DisplayConfigGetDeviceInfo(pointer);
            value = Marshal.PtrToStructure<T>(pointer);
            return result;
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private static string? NullIfWhiteSpace(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static RectD ToRect(NativeRect value) => new(
        value.Left,
        value.Top,
        value.Right - value.Left,
        value.Bottom - value.Top);

    private sealed record MonitorEntry(nint Handle, MonitorRecord Record);

    private sealed class NativeBuffer<T> : IDisposable
        where T : struct
    {
        private readonly int stride = Marshal.SizeOf<T>();
        private nint pointer;

        private NativeBuffer(uint count)
        {
            var bytes = checked(stride * checked((int)count));
            pointer = bytes == 0 ? 0 : Marshal.AllocHGlobal(bytes);
        }

        public nint Pointer => pointer;

        public static NativeBuffer<T> Allocate(uint count) => new(count);

        public T Read(int index) => Marshal.PtrToStructure<T>(pointer + (index * stride));

        public void Dispose()
        {
            if (pointer == 0)
            {
                return;
            }

            Marshal.FreeHGlobal(pointer);
            pointer = 0;
        }
    }
}

internal sealed class DisplayTopologyException(string message, int nativeError)
    : Exception($"{message} ({nativeError})");
