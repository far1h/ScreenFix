using ScreenFix.App.Notifications;

namespace ScreenFix.App.Tests;

public sealed class SystemMessageCoordinatorTests
{
    [Theory]
    [InlineData(SystemMessage.DisplayChange, 0, ExpectedCall.Reconcile)]
    [InlineData(SystemMessage.SettingChange, SystemMessageCoordinator.SetWorkArea, ExpectedCall.Reconcile)]
    [InlineData(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerSuspend, ExpectedCall.Suspend)]
    [InlineData(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerResumeAutomatic, ExpectedCall.Resume)]
    [InlineData(SystemMessage.DpiChanged, 0, ExpectedCall.CancelEditorForDpi)]
    public void Handle_RoutesSupportedMessageOnNextUiTurn(
        int message,
        int value,
        ExpectedCall expected)
    {
        var target = new FakeTarget();
        var dispatcher = new FakeDispatcher();
        var coordinator = new SystemMessageCoordinator(target, dispatcher, generation: 7);

        coordinator.Handle(message, value, callbackGeneration: 7);

        Assert.Empty(target.Calls);
        dispatcher.RunAll();
        Assert.Equal([expected], target.Calls);
    }

    [Fact]
    public void Handle_DuplicateDisplayMessagesCoalesceIntoOneReconcile()
    {
        var target = new FakeTarget();
        var dispatcher = new FakeDispatcher();
        var coordinator = new SystemMessageCoordinator(target, dispatcher, generation: 1);

        coordinator.Handle(SystemMessage.DisplayChange, 0, 1);
        coordinator.Handle(SystemMessage.DisplayChange, 0, 1);

        Assert.Single(dispatcher.Pending);
        dispatcher.RunAll();
        Assert.Equal([ExpectedCall.Reconcile], target.Calls);
    }

    [Fact]
    public void Handle_SuspendAndResumeAreIdempotent()
    {
        var target = new FakeTarget();
        var dispatcher = new FakeDispatcher();
        var coordinator = new SystemMessageCoordinator(target, dispatcher, generation: 1);

        coordinator.Handle(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerSuspend, 1);
        coordinator.Handle(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerSuspend, 1);
        dispatcher.RunAll();
        coordinator.Handle(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerResumeAutomatic, 1);
        coordinator.Handle(SystemMessage.PowerBroadcast, SystemMessageCoordinator.PowerResumeAutomatic, 1);
        dispatcher.RunAll();

        Assert.Equal([ExpectedCall.Suspend, ExpectedCall.Resume], target.Calls);
    }

    [Fact]
    public void Handle_QueuedOldGenerationIsIgnoredAfterReplacement()
    {
        var target = new FakeTarget();
        var dispatcher = new FakeDispatcher();
        var coordinator = new SystemMessageCoordinator(target, dispatcher, generation: 1);
        coordinator.Handle(SystemMessage.DisplayChange, 0, 1);

        coordinator.ReplaceGeneration(2);
        dispatcher.RunAll();

        Assert.Empty(target.Calls);
    }

    private sealed class FakeTarget : ISystemMessageTarget
    {
        public List<ExpectedCall> Calls { get; } = [];

        public void ReconcileDisplays() => Calls.Add(ExpectedCall.Reconcile);

        public void Suspend() => Calls.Add(ExpectedCall.Suspend);

        public void Resume() => Calls.Add(ExpectedCall.Resume);

        public void CancelEditorForDpiChange() => Calls.Add(ExpectedCall.CancelEditorForDpi);
    }

    private sealed class FakeDispatcher : IUiDispatcher
    {
        public List<Action> Pending { get; } = [];

        public void Post(Action action) => Pending.Add(action);

        public void RunAll()
        {
            var pending = Pending.ToArray();
            Pending.Clear();
            foreach (var action in pending)
            {
                action();
            }
        }
    }

    public enum ExpectedCall
    {
        Reconcile,
        Suspend,
        Resume,
        CancelEditorForDpi,
    }
}
