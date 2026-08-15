namespace ScreenFix.App.Lifecycle;

public sealed class ApplicationLifetime : IDisposable
{
    private readonly object syncRoot = new();
    private Action? releaseGate;
    private Action? disposeTrayIcon;
    private Action? disposeMenu;
    private Action? clearMasks;
    private Action? closeEditor;
    private Action? stopSystemMessages;
    private Action? stopGuard;
    private Action? revokeControllerCallbacks;
    private bool disposed;

    public void OwnGate(Action cleanup) => Own(ref releaseGate, cleanup);

    public void OwnTrayIcon(Action cleanup) => Own(ref disposeTrayIcon, cleanup);

    public void OwnMenu(Action cleanup) => Own(ref disposeMenu, cleanup);

    public void OwnMasks(Action cleanup) => Own(ref clearMasks, cleanup);

    public void OwnEditor(Action cleanup) => Own(ref closeEditor, cleanup);

    public void OwnSystemMessages(Action cleanup) => Own(ref stopSystemMessages, cleanup);

    public void OwnGuard(Action cleanup) => Own(ref stopGuard, cleanup);

    public void OwnControllerCallbacks(Action cleanup) => Own(ref revokeControllerCallbacks, cleanup);

    public void Dispose()
    {
        Action?[] actions;
        lock (syncRoot)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            actions =
            [
                revokeControllerCallbacks,
                stopGuard,
                stopSystemMessages,
                closeEditor,
                clearMasks,
                disposeMenu,
                disposeTrayIcon,
                releaseGate,
            ];
            revokeControllerCallbacks = null;
            stopGuard = null;
            stopSystemMessages = null;
            closeEditor = null;
            clearMasks = null;
            disposeMenu = null;
            disposeTrayIcon = null;
            releaseGate = null;
        }

        List<Exception>? errors = null;
        foreach (var action in actions)
        {
            if (action is null)
            {
                continue;
            }

            try
            {
                action();
            }
            catch (Exception error)
            {
                errors ??= [];
                errors.Add(error);
            }
        }

        if (errors is not null)
        {
            throw new AggregateException(errors);
        }
    }

    private void Own(ref Action? slot, Action cleanup)
    {
        ArgumentNullException.ThrowIfNull(cleanup);
        lock (syncRoot)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (slot is not null)
            {
                throw new InvalidOperationException("A cleanup is already registered for this resource");
            }

            slot = cleanup;
        }
    }
}
