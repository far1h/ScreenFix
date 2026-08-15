using ScreenFix.App.Guard;
using ScreenFix.App.Interop;

namespace ScreenFix.Windows.Tests;

public sealed class WindowNativeIdentityTests
{
    [Fact]
    public void WriterRejectsIdentityWhoseOwnerThreadNoLongerMatches()
    {
        using var window = new ProbeWindow();
        var native = new WindowNative();
        Assert.True(native.TryGetThreadProcessId(
            window.Handle,
            out var threadId,
            out var processId));
        var identity = new WindowIdentity(
            window.Handle,
            processId,
            threadId,
            Incarnation: 1);
        var frame = new NativeWindowFrame(20, 20, 200, 120);

        var currentResult = native.TrySetFrame(
            identity,
            frame,
            WindowCorrectionFlags.NoActivate |
            WindowCorrectionFlags.NoZOrder);
        var recycledResult = native.TrySetFrame(
            identity with { ThreadId = threadId + 1 },
            frame,
            WindowCorrectionFlags.NoActivate |
            WindowCorrectionFlags.NoZOrder);

        Assert.True(currentResult);
        Assert.False(recycledResult);
    }

    private sealed class ProbeWindow : NativeWindow, IDisposable
    {
        public ProbeWindow()
        {
            CreateHandle(new CreateParams
            {
                Caption = "ScreenFix identity test",
                X = 10,
                Y = 10,
                Width = 160,
                Height = 100,
                Style = unchecked((int)0x80000000),
            });
        }

        public void Dispose() => DestroyHandle();
    }
}
