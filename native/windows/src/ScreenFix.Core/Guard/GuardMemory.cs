using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Guard;

public sealed class GuardMemory
{
    private static readonly TimeSpan SuccessLifetime = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan RefusalLifetime = TimeSpan.FromSeconds(1);
    private readonly Dictionary<long, SuccessEntry> successes = [];
    private readonly Dictionary<long, DateTimeOffset> refusals = [];

    public bool ShouldSuppressRecent(long key, RectD currentFrame, DateTimeOffset now)
    {
        if (!successes.TryGetValue(key, out var success))
        {
            return false;
        }

        if (now >= success.RecordedAt + SuccessLifetime ||
            !Near(currentFrame, success.Target))
        {
            successes.Remove(key);
            return false;
        }

        return true;
    }

    public void RecordSuccess(long key, RectD target, DateTimeOffset now) =>
        successes[key] = new SuccessEntry(target, now);

    public bool IsRefused(long key, DateTimeOffset now)
    {
        if (!refusals.TryGetValue(key, out var recordedAt))
        {
            return false;
        }

        if (now >= recordedAt + RefusalLifetime)
        {
            refusals.Remove(key);
            return false;
        }

        return true;
    }

    public void RecordRefusal(long key, DateTimeOffset now) =>
        refusals[key] = now;

    public void Forget(long key)
    {
        successes.Remove(key);
        refusals.Remove(key);
    }

    public void Clear()
    {
        successes.Clear();
        refusals.Clear();
    }

    public void Prune(DateTimeOffset now)
    {
        foreach (var key in successes
                     .Where(entry => now >= entry.Value.RecordedAt + SuccessLifetime)
                     .Select(entry => entry.Key)
                     .ToArray())
        {
            successes.Remove(key);
        }

        foreach (var key in refusals
                     .Where(entry => now >= entry.Value + RefusalLifetime)
                     .Select(entry => entry.Key)
                     .ToArray())
        {
            refusals.Remove(key);
        }
    }

    private static bool Near(RectD first, RectD second) =>
        Math.Abs(first.X - second.X) <= 1 &&
        Math.Abs(first.Y - second.Y) <= 1 &&
        Math.Abs(first.Right - second.Right) <= 1 &&
        Math.Abs(first.Bottom - second.Bottom) <= 1;

    private sealed record SuccessEntry(RectD Target, DateTimeOffset RecordedAt);
}
