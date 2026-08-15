using ScreenFix.App.Calibration;
using ScreenFix.App.Interop;
using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Windows.Tests;

public sealed class CalibrationLayeredRendererTests
{
    [Fact]
    public void RenderAndPresent_KeepBackgroundTransparentAndControlsInteractive()
    {
        const int width = 300;
        const int height = 200;
        var logicalFrame = new RectD(0, 0, width, height);
        var bands = new[]
        {
            new RectD(0.2, 0.45, 0.25, 0.2),
        };
        var layout = Assert.IsType<CalibrationLayoutSpec>(
            CalibrationLayout.TryCreate(width, height).Value);

        using var bitmap = CalibrationLayeredRenderer.Render(
            width,
            height,
            dpi: 96,
            logicalFrame,
            bands,
            layout);

        Assert.Equal(0, bitmap.GetPixel(285, 100).A);
        Assert.InRange(bitmap.GetPixel(100, 110).A, 80, 96);
        Assert.Equal(255, bitmap.GetPixel(62, 110).A);

        var workingArea = Screen.PrimaryScreen!.WorkingArea;
        Assert.True(workingArea.Width >= width && workingArea.Height >= height);
        var bounds = new Rectangle(workingArea.X, workingArea.Y, width, height);
        using var backingWindow = new ProbeWindow(bounds, layered: false);
        using var layeredWindow = new ProbeWindow(bounds, layered: true);
        backingWindow.ShowBehind();
        CalibrationLayeredRenderer.Present(
            layeredWindow.Handle,
            bounds,
            bitmap);
        layeredWindow.ShowAbove();

        var transparentPoint = new NativePoint(bounds.X + 285, bounds.Y + 100);
        var paintedPoint = new NativePoint(bounds.X + 100, bounds.Y + 110);
        Assert.Equal(backingWindow.Handle, User32.WindowFromPoint(transparentPoint));
        Assert.Equal(layeredWindow.Handle, User32.WindowFromPoint(paintedPoint));
    }

    private sealed class ProbeWindow : NativeWindow, IDisposable
    {
        private readonly Rectangle bounds;

        public ProbeWindow(Rectangle bounds, bool layered)
        {
            this.bounds = bounds;
            CreateHandle(new CreateParams
            {
                Caption = "ScreenFix layered render test",
                X = bounds.X,
                Y = bounds.Y,
                Width = bounds.Width,
                Height = bounds.Height,
                Style = unchecked((int)0x80000000),
                ExStyle = User32.WindowExtendedStyleToolWindow |
                    User32.WindowExtendedStyleNoActivate |
                    (layered ? User32.WindowExtendedStyleLayered : 0),
            });
        }

        public void ShowBehind() => Show(nint.Zero);

        public void ShowAbove() => Show(User32.TopMostWindow);

        public void Dispose() => DestroyHandle();

        private void Show(nint insertAfter)
        {
            Assert.NotEqual(
                0,
                User32.SetWindowPos(
                    Handle,
                    insertAfter,
                    bounds.X,
                    bounds.Y,
                    bounds.Width,
                    bounds.Height,
                    User32.SetWindowPositionNoActivate |
                    User32.SetWindowPositionShowWindow |
                    User32.SetWindowPositionNoOwnerZOrder));
        }
    }
}
