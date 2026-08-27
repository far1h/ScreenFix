using System.Diagnostics;
using System.Runtime.InteropServices;
using ScreenFix.App.Guard;
using ScreenFix.App.Interop;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace ScreenFix.Windows.Tests;

public sealed class WindowNativePlacementTests
{
    private static readonly TimeSpan WaitTimeout = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task MaximizedWindow_RestoresAndMovesAcrossThreads()
    {
        var probe = new StaProbeWindow();
        try
        {
            var handle = await probe.WaitUntilShownAsync();
            var native = new WindowNative();
            var query = (IWindowNativeQuery)native;

            await probe.InvokeAsync(form =>
            {
                form.WindowState = FormWindowState.Maximized;
            });
            await WaitUntilAsync(
                () => query.IsZoomed(handle),
                "The probe window did not enter the maximized state.");

            var identitySucceeded = native.TryGetThreadProcessId(
                handle,
                out var threadId,
                out var processId);
            var identityError = identitySucceeded ? 0 : Marshal.GetLastPInvokeError();
            Assert.True(
                identitySucceeded,
                $"TryGetThreadProcessId returned false with last P/Invoke error {identityError}.");
            var identity = new WindowIdentity(
                handle,
                processId,
                threadId,
                Incarnation: 1);

            var getPlacementSucceeded = native.TryGetPlacement(identity, out var placement);
            var getPlacementError = getPlacementSucceeded ? 0 : Marshal.GetLastPInvokeError();
            Assert.True(
                getPlacementSucceeded,
                $"TryGetPlacement returned false with last P/Invoke error {getPlacementError}.");

            var restored = placement with
            {
                Flags = placement.Flags | WindowPlacementFlags.AsyncWindowPlacement,
                ShowCommand = WindowShowCommand.ShowNoActivate,
            };
            var setPlacementSucceeded = native.TrySetPlacement(identity, restored);
            var setPlacementError = setPlacementSucceeded ? 0 : Marshal.GetLastPInvokeError();
            Assert.True(
                setPlacementSucceeded,
                $"TrySetPlacement returned false with last P/Invoke error {setPlacementError}.");

            var target = CreateTargetFrame();
            var setFrameSucceeded = native.TrySetFrame(
                identity,
                target,
                WindowCorrectionFlags.NoActivate |
                WindowCorrectionFlags.NoZOrder |
                WindowCorrectionFlags.NoOwnerZOrder |
                WindowCorrectionFlags.AsyncWindowPosition);
            var setFrameError = setFrameSucceeded ? 0 : Marshal.GetLastPInvokeError();
            Assert.True(
                setFrameSucceeded,
                $"TrySetFrame returned false with last P/Invoke error {setFrameError}.");

            await WaitForFinalFrameAsync(native, query, handle, target);
        }
        finally
        {
            await probe.StopAsync();
        }
    }

    private static NativeWindowFrame CreateTargetFrame()
    {
        var primaryScreen = Screen.PrimaryScreen;
        Assert.NotNull(primaryScreen);
        var workingArea = primaryScreen.WorkingArea;
        const int inset = 80;
        Assert.True(
            workingArea.Width > inset * 2 && workingArea.Height > inset * 2,
            $"Primary working area {workingArea} is too small for the probe frame.");

        return new NativeWindowFrame(
            workingArea.Left + inset,
            workingArea.Top + inset,
            Math.Min(640, workingArea.Width - (inset * 2)),
            Math.Min(480, workingArea.Height - (inset * 2)));
    }

    private static async Task WaitForFinalFrameAsync(
        WindowNative native,
        IWindowNativeQuery query,
        nint handle,
        NativeWindowFrame target)
    {
        var deadline = Stopwatch.StartNew();
        var lastZoomed = true;
        var lastFrame = "unavailable";
        var lastFrameError = 0;

        while (deadline.Elapsed < WaitTimeout)
        {
            lastZoomed = query.IsZoomed(handle);
            var frameSucceeded = native.TryGetOuterFrame(handle, out var frame);
            lastFrameError = frameSucceeded ? 0 : Marshal.GetLastPInvokeError();
            if (frameSucceeded)
            {
                lastFrame = frame.ToString();
                if (!lastZoomed &&
                    frame.X == target.X &&
                    frame.Y == target.Y &&
                    frame.Width == target.Width &&
                    frame.Height == target.Height)
                {
                    return;
                }
            }

            await Task.Delay(25);
        }

        Assert.Fail(
            $"The probe window did not reach the target frame. " +
            $"Last zoom state: {lastZoomed}; last frame: {lastFrame}; " +
            $"last TryGetOuterFrame P/Invoke error: {lastFrameError}; target: {target}.");
    }

    private static async Task WaitUntilAsync(Func<bool> condition, string timeoutMessage)
    {
        var deadline = Stopwatch.StartNew();
        while (deadline.Elapsed < WaitTimeout)
        {
            if (condition())
            {
                return;
            }

            await Task.Delay(25);
        }

        Assert.Fail(timeoutMessage);
    }

    private sealed class StaProbeWindow
    {
        private readonly TaskCompletionSource<nint> shown =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<object?> exited =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly Thread ownerThread;
        private Form? form;
        private Exception? ownerException;

        public StaProbeWindow()
        {
            ownerThread = new Thread(Run)
            {
                IsBackground = true,
                Name = "ScreenFix placement probe",
            };
            ownerThread.SetApartmentState(ApartmentState.STA);
            ownerThread.Start();
        }

        public async Task<nint> WaitUntilShownAsync() =>
            await shown.Task.WaitAsync(WaitTimeout);

        public async Task InvokeAsync(Action<Form> action)
        {
            ArgumentNullException.ThrowIfNull(action);
            var currentForm = form ?? throw new InvalidOperationException(
                "The probe window has not been shown.");
            var completed = new TaskCompletionSource<object?>(
                TaskCreationOptions.RunContinuationsAsynchronously);

            currentForm.BeginInvoke(new Action(() =>
            {
                try
                {
                    action(currentForm);
                    completed.TrySetResult(null);
                }
                catch (Exception exception)
                {
                    completed.TrySetException(exception);
                }
            }));
            await completed.Task.WaitAsync(WaitTimeout);
        }

        public async Task StopAsync()
        {
            if (form is { IsDisposed: false })
            {
                await InvokeAsync(currentForm => currentForm.Close());
            }

            await exited.Task.WaitAsync(WaitTimeout);
            Assert.True(
                ownerThread.Join(WaitTimeout),
                "The probe window owner thread did not exit within 15 seconds.");
            if (ownerException is not null)
            {
                throw new InvalidOperationException(
                    "The probe window owner thread failed.",
                    ownerException);
            }
        }

        private void Run()
        {
            try
            {
                using var currentForm = new Form
                {
                    Bounds = new Rectangle(40, 40, 640, 480),
                    FormBorderStyle = FormBorderStyle.Sizable,
                    MaximizeBox = true,
                    MinimizeBox = true,
                    StartPosition = FormStartPosition.Manual,
                    Text = "ScreenFix placement test",
                };
                form = currentForm;
                currentForm.Shown += (_, _) => shown.TrySetResult(currentForm.Handle);
                Application.Run(currentForm);
            }
            catch (Exception exception)
            {
                ownerException = exception;
                shown.TrySetException(exception);
            }
            finally
            {
                exited.TrySetResult(null);
            }
        }
    }
}
