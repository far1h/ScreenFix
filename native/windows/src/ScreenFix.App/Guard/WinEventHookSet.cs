using System.Runtime.InteropServices;
using ScreenFix.App.Notifications;
using ScreenFix.App.Runtime;

namespace ScreenFix.App.Guard;

public static class WinEventId
{
    public const uint Seed = 0;
    public const uint SystemForeground = 0x0003;
    public const uint SystemMoveSizeEnd = 0x000B;
    public const uint SystemMinimizeEnd = 0x0017;
    public const uint ObjectCreate = 0x8000;
    public const uint ObjectDestroy = 0x8001;
    public const uint ObjectShow = 0x8002;
    public const uint ObjectLocationChange = 0x800B;
}

public static class WinEventHookFlags
{
    public const uint OutOfContext = 0x0000;
    public const uint SkipOwnProcess = 0x0002;
}

public readonly record struct WinEventSignal(
    long Generation,
    uint EventType,
    nint Window,
    int ObjectId,
    int ChildId);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
public delegate void NativeWinEventCallback(
    nint hook,
    uint eventType,
    nint window,
    int objectId,
    int childId,
    uint eventThread,
    uint eventTime);

public interface IWinEventNativeApi
{
    nint SetHook(
        uint eventMinimum,
        uint eventMaximum,
        NativeWinEventCallback callback,
        uint processId,
        uint threadId,
        uint flags);

    bool Unhook(nint hook);

    bool TryEnumerateWindows(out IReadOnlyList<nint> windows);
}

public interface IWinEventSource : IDisposable
{
    RuntimeOperationResult Start(
        long generation,
        Action<WinEventSignal> signal);

    void Stop();
}

public sealed class WinEventHookSet(
    IWinEventNativeApi native,
    IUiDispatcher dispatcher) : IWinEventSource
{
    private static readonly uint[] Events =
    [
        WinEventId.ObjectCreate,
        WinEventId.ObjectDestroy,
        WinEventId.ObjectShow,
        WinEventId.ObjectLocationChange,
        WinEventId.SystemMoveSizeEnd,
        WinEventId.SystemForeground,
        WinEventId.SystemMinimizeEnd,
    ];

    private readonly List<nint> hooks = [];
    private NativeWinEventCallback? callback;
    private GCHandle callbackLease;
    private Action<WinEventSignal>? signal;
    private bool active;
    private bool disposed;
    private long generation;
    private int? installingThreadId;

    internal int RetainedHookCount => hooks.Count;

    internal bool IsCallbackRooted => callbackLease.IsAllocated && callback is not null;

    public RuntimeOperationResult Start(
        long generation,
        Action<WinEventSignal> signal)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(signal);
        if (active || hooks.Count != 0)
        {
            return RuntimeOperationResult.Failure("Window event hooks are already active");
        }

        callback = HandleNativeEvent;
        callbackLease = GCHandle.Alloc(callback);
        installingThreadId = Environment.CurrentManagedThreadId;
        IReadOnlyList<nint> windows;
        try
        {
            foreach (var eventId in Events)
            {
                var hook = native.SetHook(
                    eventId,
                    eventId,
                    callback,
                    processId: 0,
                    threadId: 0,
                    WinEventHookFlags.OutOfContext | WinEventHookFlags.SkipOwnProcess);
                if (hook == 0)
                {
                    ReleaseHooks();
                    return RuntimeOperationResult.Failure("Window event hook registration failed");
                }

                hooks.Add(hook);
            }

            if (!native.TryEnumerateWindows(out windows))
            {
                ReleaseHooks();
                return RuntimeOperationResult.Failure("Window enumeration failed");
            }
        }
        catch
        {
            ReleaseHooks();
            return RuntimeOperationResult.Failure("Window event hook registration failed");
        }

        this.generation = generation;
        this.signal = signal;
        active = true;
        foreach (var window in windows)
        {
            var seed = new WinEventSignal(generation, WinEventId.Seed, window, 0, 0);
            dispatcher.Post(() => Dispatch(seed));
        }

        return RuntimeOperationResult.Success();
    }

    public void Stop()
    {
        active = false;
        generation++;
        signal = null;
        ReleaseHooks();
    }

    public void Dispose()
    {
        if (disposed && hooks.Count == 0)
        {
            return;
        }

        disposed = true;
        Stop();
    }

    private void HandleNativeEvent(
        nint hook,
        uint eventType,
        nint window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime)
    {
        _ = hook;
        _ = eventThread;
        _ = eventTime;
        var copied = new WinEventSignal(
            generation,
            eventType,
            window,
            objectId,
            childId);
        if (window == 0 ||
            (IsObjectEvent(eventType) && (objectId != 0 || childId != 0)))
        {
            return;
        }

        dispatcher.Post(() => Dispatch(copied));
    }

    private void Dispatch(WinEventSignal copied)
    {
        if (active && copied.Generation == generation)
        {
            signal?.Invoke(copied);
        }
    }

    private void ReleaseHooks()
    {
        if (installingThreadId != Environment.CurrentManagedThreadId)
        {
            return;
        }

        var retained = new List<nint>();
        foreach (var hook in hooks)
        {
            try
            {
                if (!native.Unhook(hook))
                {
                    retained.Add(hook);
                }
            }
            catch
            {
                retained.Add(hook);
            }
        }

        hooks.Clear();
        hooks.AddRange(retained);
        if (hooks.Count != 0)
        {
            return;
        }

        if (callbackLease.IsAllocated)
        {
            callbackLease.Free();
        }

        callback = null;
        installingThreadId = null;
    }

    private static bool IsObjectEvent(uint eventType) =>
        eventType >= WinEventId.ObjectCreate;
}
