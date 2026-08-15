namespace ScreenFix.App.Notifications;

public static class SystemMessage
{
    public const int SettingChange = 0x001A;
    public const int DisplayChange = 0x007E;
    public const int PowerBroadcast = 0x0218;
    public const int DpiChanged = 0x02E0;
}

public interface IUiDispatcher
{
    void Post(Action action);
}

public interface ISystemMessageTarget
{
    void ReconcileDisplays();

    void Suspend();

    void Resume();

    void CancelEditorForDpiChange(long editorGeneration);
}

public sealed class SystemMessageCoordinator
{
    public const int SetWorkArea = 0x002F;
    public const int PowerSuspend = 0x0004;
    public const int PowerResumeAutomatic = 0x0012;

    private readonly ISystemMessageTarget target;
    private readonly IUiDispatcher dispatcher;
    private bool reconcileQueued;
    private bool suspendQueued;
    private bool resumeQueued;
    private bool dpiQueued;
    private long queuedDpiEditorGeneration;
    private PowerState powerState;

    public SystemMessageCoordinator(
        ISystemMessageTarget target,
        IUiDispatcher dispatcher,
        long generation)
    {
        this.target = target ?? throw new ArgumentNullException(nameof(target));
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        Generation = generation;
    }

    public long Generation { get; private set; }

    public void Handle(int message, int value, long callbackGeneration)
    {
        if (callbackGeneration != Generation)
        {
            return;
        }

        switch (message)
        {
            case SystemMessage.DisplayChange:
                QueueReconcile(callbackGeneration);
                break;
            case SystemMessage.SettingChange when value == SetWorkArea:
                QueueReconcile(callbackGeneration);
                break;
            case SystemMessage.PowerBroadcast when value == PowerSuspend:
                QueueSuspend(callbackGeneration);
                break;
            case SystemMessage.PowerBroadcast when value == PowerResumeAutomatic:
                QueueResume(callbackGeneration);
                break;
        }
    }

    public void HandleEditorDpiChanged(long editorGeneration, long callbackGeneration)
    {
        if (callbackGeneration == Generation)
        {
            QueueDpiChange(callbackGeneration, editorGeneration);
        }
    }

    public void ReplaceGeneration(long generation)
    {
        Generation = generation;
        reconcileQueued = false;
        suspendQueued = false;
        resumeQueued = false;
        dpiQueued = false;
        queuedDpiEditorGeneration = 0;
        powerState = PowerState.Unknown;
    }

    private void QueueReconcile(long callbackGeneration)
    {
        if (reconcileQueued)
        {
            return;
        }

        reconcileQueued = true;
        dispatcher.Post(() =>
        {
            if (callbackGeneration != Generation)
            {
                return;
            }

            reconcileQueued = false;
            target.ReconcileDisplays();
        });
    }

    private void QueueSuspend(long callbackGeneration)
    {
        if (suspendQueued || powerState == PowerState.Suspended)
        {
            return;
        }

        suspendQueued = true;
        dispatcher.Post(() =>
        {
            if (callbackGeneration != Generation)
            {
                return;
            }

            suspendQueued = false;
            powerState = PowerState.Suspended;
            target.Suspend();
        });
    }

    private void QueueResume(long callbackGeneration)
    {
        if (resumeQueued || powerState == PowerState.Resumed)
        {
            return;
        }

        resumeQueued = true;
        dispatcher.Post(() =>
        {
            if (callbackGeneration != Generation)
            {
                return;
            }

            resumeQueued = false;
            powerState = PowerState.Resumed;
            target.Resume();
        });
    }

    private void QueueDpiChange(long callbackGeneration, long editorGeneration)
    {
        queuedDpiEditorGeneration = editorGeneration;
        if (dpiQueued)
        {
            return;
        }

        dpiQueued = true;
        dispatcher.Post(() =>
        {
            if (callbackGeneration != Generation)
            {
                return;
            }

            dpiQueued = false;
            var latestEditorGeneration = queuedDpiEditorGeneration;
            queuedDpiEditorGeneration = 0;
            target.CancelEditorForDpiChange(latestEditorGeneration);
        });
    }

    private enum PowerState
    {
        Unknown,
        Suspended,
        Resumed,
    }
}
