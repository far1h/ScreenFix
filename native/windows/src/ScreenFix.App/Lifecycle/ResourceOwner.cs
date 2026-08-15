namespace ScreenFix.App.Lifecycle;

public sealed class ResourceOwner : IDisposable
{
    private readonly object syncRoot = new();
    private readonly Stack<Action> cleanupActions = new();
    private bool disposed;

    public void Register(Action cleanup)
    {
        ArgumentNullException.ThrowIfNull(cleanup);

        lock (syncRoot)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            cleanupActions.Push(cleanup);
        }
    }

    public void Dispose()
    {
        Action[] actions;
        lock (syncRoot)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            actions = cleanupActions.ToArray();
            cleanupActions.Clear();
        }

        List<Exception>? errors = null;
        foreach (var action in actions)
        {
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
}
