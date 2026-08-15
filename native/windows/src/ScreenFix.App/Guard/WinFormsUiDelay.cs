namespace ScreenFix.App.Guard;

internal sealed class WinFormsUiDelay : IUiDelay
{
    public IDisposable Schedule(TimeSpan delay, Action callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        var interval = checked((int)Math.Ceiling(delay.TotalMilliseconds));
        if (interval <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(delay));
        }

        var timer = new System.Windows.Forms.Timer
        {
            Interval = interval,
        };
        EventHandler? handler = null;
        handler = (_, _) =>
        {
            timer.Stop();
            timer.Tick -= handler;
            timer.Dispose();
            callback();
        };
        timer.Tick += handler;
        timer.Start();
        return new TimerCancellation(timer, handler);
    }

    private sealed class TimerCancellation(
        System.Windows.Forms.Timer timer,
        EventHandler handler) : IDisposable
    {
        private bool disposed;

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            timer.Stop();
            timer.Tick -= handler;
            timer.Dispose();
        }
    }
}
