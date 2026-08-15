using System.ComponentModel;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;
using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Calibration;

internal static class CalibrationLayeredRenderer
{
    public static Bitmap Render(
        int width,
        int height,
        uint dpi,
        RectD logicalFrame,
        IReadOnlyList<RectD> bands,
        CalibrationLayoutSpec layout)
    {
        if (width <= 0 || height <= 0 || dpi == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        try
        {
            using var graphics = Graphics.FromImage(bitmap);
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.Clear(Color.Transparent);
            graphics.CompositingMode = CompositingMode.SourceOver;
            CalibrationPainter.Paint(graphics, dpi, logicalFrame, bands, layout);
            return bitmap;
        }
        catch
        {
            bitmap.Dispose();
            throw;
        }
    }

    public static void Present(nint window, Rectangle screenBounds, Bitmap bitmap)
    {
        ArgumentNullException.ThrowIfNull(bitmap);
        if (window == 0 || screenBounds.Width != bitmap.Width || screenBounds.Height != bitmap.Height)
        {
            throw new ArgumentException("layered window and bitmap bounds must match");
        }

        var screenDeviceContext = User32.GetDC(0);
        if (screenDeviceContext == 0)
        {
            throw new Win32Exception("screen device context failed");
        }

        nint memoryDeviceContext = 0;
        nint bitmapHandle = 0;
        nint previousObject = 0;
        try
        {
            memoryDeviceContext = Gdi32.CreateCompatibleDC(screenDeviceContext);
            if (memoryDeviceContext == 0)
            {
                throw NativeFailure("layered memory context failed");
            }

            bitmapHandle = bitmap.GetHbitmap(Color.FromArgb(0));
            previousObject = Gdi32.SelectObject(memoryDeviceContext, bitmapHandle);
            if (previousObject == 0 || previousObject == Gdi32.InvalidObject)
            {
                throw NativeFailure("layered bitmap selection failed");
            }

            var destination = new NativePoint(screenBounds.X, screenBounds.Y);
            var size = new NativeSize(screenBounds.Width, screenBounds.Height);
            var source = new NativePoint(0, 0);
            var blend = new NativeBlendFunction
            {
                BlendOperation = User32.AlphaSourceOver,
                BlendFlags = 0,
                SourceConstantAlpha = byte.MaxValue,
                AlphaFormat = User32.AlphaSourceAlpha,
            };
            if (User32.UpdateLayeredWindow(
                    window,
                    screenDeviceContext,
                    in destination,
                    in size,
                    memoryDeviceContext,
                    in source,
                    colorKey: 0,
                    in blend,
                    User32.LayeredWindowAlpha) == 0)
            {
                throw NativeFailure("layered calibration update failed");
            }
        }
        finally
        {
            if (previousObject != 0 && previousObject != Gdi32.InvalidObject)
            {
                _ = Gdi32.SelectObject(memoryDeviceContext, previousObject);
            }

            if (bitmapHandle != 0)
            {
                _ = Gdi32.DeleteObject(bitmapHandle);
            }

            if (memoryDeviceContext != 0)
            {
                _ = Gdi32.DeleteDC(memoryDeviceContext);
            }

            _ = User32.ReleaseDC(0, screenDeviceContext);
        }
    }

    private static Win32Exception NativeFailure(string message) =>
        new(Marshal.GetLastPInvokeError(), message);
}
