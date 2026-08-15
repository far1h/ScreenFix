namespace ScreenFix.App.Lifecycle;

public sealed class SingleInstanceGate : IDisposable
{
    private Mutex? mutex;

    private SingleInstanceGate(Mutex mutex)
    {
        this.mutex = mutex;
    }

    public static SingleInstanceGate? TryAcquire(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        var candidate = new Mutex(initiallyOwned: true, name, out var createdNew);
        if (!createdNew)
        {
            candidate.Dispose();
            return null;
        }

        return new SingleInstanceGate(candidate);
    }

    public void Dispose()
    {
        var owned = Interlocked.Exchange(ref mutex, null);
        if (owned is null)
        {
            return;
        }

        owned.ReleaseMutex();
        owned.Dispose();
    }
}
