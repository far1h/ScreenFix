namespace ScreenFix.App.Guard;

public interface IUiDelay
{
    IDisposable Schedule(TimeSpan delay, Action callback);
}

public sealed class GuardScheduler(IUiDelay delay) : IDisposable
{
    private readonly Dictionary<long, PendingWork> pending = [];
    private bool active;
    private long generation;

    public void Start(long generation)
    {
        CancelPending();
        this.generation = generation;
        active = true;
    }

    public void Signal(long key, Action<long> correction)
    {
        ArgumentNullException.ThrowIfNull(correction);
        if (pending.Remove(key, out var retired))
        {
            retired.Cancellation.Dispose();
        }

        var callbackGeneration = generation;
        var token = new object();
        var cancellation = delay.Schedule(TimeSpan.FromMilliseconds(150), () =>
        {
            if (!pending.TryGetValue(key, out var current) ||
                !ReferenceEquals(current.Token, token))
            {
                return;
            }

            pending.Remove(key);
            current.Cancellation.Dispose();
            if (active && callbackGeneration == generation)
            {
                correction(key);
            }
        });
        pending[key] = new PendingWork(token, cancellation);
    }

    public void Stop()
    {
        active = false;
        generation++;
        CancelPending();
    }

    public void Dispose() => Stop();

    private void CancelPending()
    {
        foreach (var work in pending.Values)
        {
            work.Cancellation.Dispose();
        }

        pending.Clear();
    }

    private sealed record PendingWork(object Token, IDisposable Cancellation);
}
