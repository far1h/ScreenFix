using ScreenFix.App.Lifecycle;

namespace ScreenFix.App;

internal static class ScreenFixApplicationIdentity
{
    internal const string SingleInstanceMutexName = @"Local\ScreenFix.Native";

    internal static SingleInstanceGate? TryAcquire()
    {
        return SingleInstanceGate.TryAcquire(SingleInstanceMutexName);
    }
}
