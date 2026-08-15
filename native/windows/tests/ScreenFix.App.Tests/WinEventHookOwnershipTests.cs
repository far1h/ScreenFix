using ScreenFix.App.Guard;
using ScreenFix.App.Notifications;
using ScreenFix.App.Runtime;

namespace ScreenFix.App.Tests;

public sealed class WinEventHookOwnershipTests
{
    [Fact]
    public void Start_InstallsEveryRequiredHookIndividually()
    {
        var native = new FakeWinEventNativeApi();
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);

        var result = hooks.Start(generation: 7, _ => { });

        Assert.True(result.IsSuccess);
        Assert.Equal(
            [
                WinEventId.ObjectCreate,
                WinEventId.ObjectShow,
                WinEventId.ObjectLocationChange,
                WinEventId.SystemMoveSizeEnd,
                WinEventId.SystemForeground,
                WinEventId.SystemMinimizeEnd,
            ],
            native.Registrations.Select(call => call.EventMinimum));
        Assert.All(native.Registrations, call =>
        {
            Assert.Equal(call.EventMinimum, call.EventMaximum);
            Assert.Equal(0u, call.ProcessId);
            Assert.Equal(0u, call.ThreadId);
            Assert.Equal(
                WinEventHookFlags.OutOfContext | WinEventHookFlags.SkipOwnProcess,
                call.Flags);
        });
    }

    [Fact]
    public void Start_FailedRegistrationUnhooksEveryCandidate()
    {
        var native = new FakeWinEventNativeApi { FailRegistrationIndex = 3 };
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);

        var result = hooks.Start(generation: 7, _ => { });

        Assert.False(result.IsSuccess);
        Assert.Equal([new nint(1), new nint(2), new nint(3)], native.Unhooked);
    }

    [Fact]
    public void Start_RegistrationExceptionUnhooksEveryCandidateAndReturnsFailure()
    {
        var native = new FakeWinEventNativeApi { ThrowRegistrationIndex = 2 };
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);

        RuntimeOperationResult result = default;
        var error = Record.Exception(() =>
            result = hooks.Start(generation: 7, _ => { }));

        Assert.Null(error);
        Assert.False(result.IsSuccess);
        Assert.Equal([new nint(1), new nint(2)], native.Unhooked);
    }

    [Fact]
    public void Stop_UnhooksEveryHookExactlyOnceAndKeepsDelegateAliveUntilThen()
    {
        var native = new FakeWinEventNativeApi();
        var dispatcher = new FakeDispatcher();
        var hooks = new WinEventHookSet(native, dispatcher);
        hooks.Start(generation: 7, _ => { });
        var callback = Assert.Single(native.Registrations.Select(x => x.Callback).Distinct());

        hooks.Stop();
        hooks.Stop();
        hooks.Dispose();

        Assert.Equal(6, native.Unhooked.Count);
        Assert.All(native.CallbacksAliveDuringUnhook, Assert.True);
        GC.KeepAlive(callback);
    }

    [Fact]
    public void Callback_PostedBeforeStopIsGenerationRejected()
    {
        var native = new FakeWinEventNativeApi();
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);
        var signals = new List<WinEventSignal>();
        hooks.Start(generation: 7, signals.Add);
        native.Raise(WinEventId.SystemForeground, new nint(17));

        hooks.Stop();
        dispatcher.RunAll();

        Assert.Empty(signals);
    }

    [Theory]
    [InlineData(1, 0)]
    [InlineData(0, 1)]
    public void ObjectCallback_IgnoresNonWindowObjects(int objectId, int childId)
    {
        var native = new FakeWinEventNativeApi();
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);
        var signals = new List<WinEventSignal>();
        hooks.Start(generation: 7, signals.Add);

        native.Raise(
            WinEventId.ObjectLocationChange,
            new nint(17),
            objectId,
            childId);
        dispatcher.RunAll();

        Assert.Empty(signals);
    }

    [Fact]
    public void Start_InstallsBeforeSeedingExistingWindows()
    {
        var native = new FakeWinEventNativeApi
        {
            EnumeratedWindows = [new nint(17), new nint(23)],
        };
        var dispatcher = new FakeDispatcher();
        using var hooks = new WinEventHookSet(native, dispatcher);
        var signals = new List<WinEventSignal>();

        var result = hooks.Start(generation: 7, signals.Add);
        dispatcher.RunAll();

        Assert.True(result.IsSuccess);
        Assert.Equal(6, native.RegistrationCountWhenEnumerated);
        Assert.Equal([new nint(17), new nint(23)], signals.Select(x => x.Window));
        Assert.All(signals, signal => Assert.Equal(WinEventId.Seed, signal.EventType));
    }

    private sealed class FakeWinEventNativeApi : IWinEventNativeApi
    {
        private long nextHook = 1;

        public List<HookRegistration> Registrations { get; } = [];

        public List<nint> Unhooked { get; } = [];

        public List<bool> CallbacksAliveDuringUnhook { get; } = [];

        public int? FailRegistrationIndex { get; set; }

        public int? ThrowRegistrationIndex { get; set; }

        public IReadOnlyList<nint> EnumeratedWindows { get; set; } = [];

        public int RegistrationCountWhenEnumerated { get; private set; }

        public nint SetHook(
            uint eventMinimum,
            uint eventMaximum,
            NativeWinEventCallback callback,
            uint processId,
            uint threadId,
            uint flags)
        {
            if (ThrowRegistrationIndex == Registrations.Count)
            {
                throw new InvalidOperationException("registration failed");
            }

            if (FailRegistrationIndex == Registrations.Count)
            {
                return 0;
            }

            Registrations.Add(new HookRegistration(
                eventMinimum,
                eventMaximum,
                callback,
                processId,
                threadId,
                flags));
            return new nint(nextHook++);
        }

        public bool Unhook(nint hook)
        {
            Unhooked.Add(hook);
            CallbacksAliveDuringUnhook.Add(
                Registrations.Any(registration => registration.Callback is not null));
            return true;
        }

        public bool TryEnumerateWindows(out IReadOnlyList<nint> windows)
        {
            RegistrationCountWhenEnumerated = Registrations.Count;
            windows = EnumeratedWindows;
            return true;
        }

        public void Raise(
            uint eventType,
            nint window,
            int objectId = 0,
            int childId = 0)
        {
            var registration = Registrations.Single(x => x.EventMinimum == eventType);
            registration.Callback(
                new nint(1),
                eventType,
                window,
                objectId,
                childId,
                eventThread: 9,
                eventTime: 10);
        }
    }

    private sealed class FakeDispatcher : IUiDispatcher
    {
        private readonly List<Action> pending = [];

        public void Post(Action action) => pending.Add(action);

        public void RunAll()
        {
            var actions = pending.ToArray();
            pending.Clear();
            foreach (var action in actions)
            {
                action();
            }
        }
    }

    private sealed record HookRegistration(
        uint EventMinimum,
        uint EventMaximum,
        NativeWinEventCallback Callback,
        uint ProcessId,
        uint ThreadId,
        uint Flags);
}
