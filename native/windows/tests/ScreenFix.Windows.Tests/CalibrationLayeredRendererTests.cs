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
        const int width = 1000;
        const int height = 800;
        var logicalFrame = new RectD(0, 0, width, height);
        var bands = new[]
        {
            new RectD(0.2, 0.2, 0.2, 0.2),
            new RectD(0.6, 0.45, 0.2, 0.15),
            new RectD(0.7, 0.7, 0.2, 0.15),
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

        Assert.Equal(0, bitmap.GetPixel(50, 400).A);
        Assert.InRange(bitmap.GetPixel(300, 240).A, 80, 96);
        Assert.Equal(255, bitmap.GetPixel(202, 240).A);

        using var window = new LayeredProbeWindow();
        CalibrationLayeredRenderer.Present(
            window.Handle,
            new Rectangle(-32_000, -32_000, width, height),
            bitmap);
        Assert.NotEqual(nint.Zero, window.Handle);
    }

    private sealed class LayeredProbeWindow : NativeWindow, IDisposable
    {
        public LayeredProbeWindow()
        {
            CreateHandle(new CreateParams
            {
                Caption = "ScreenFix layered render test",
                X = -32_000,
                Y = -32_000,
                Width = 1000,
                Height = 800,
                Style = unchecked((int)0x80000000),
                ExStyle = User32.WindowExtendedStyleLayered |
                    User32.WindowExtendedStyleToolWindow |
                    User32.WindowExtendedStyleNoActivate,
            });
        }

        public void Dispose() => DestroyHandle();
    }
}
