using System.ComponentModel;
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Overlays;

internal sealed class MaskFormFactory : IMaskSurfaceFactory
{
    public IMaskSurface Create() => new MaskForm();
}

internal sealed class MaskForm : Form, IMaskSurface
{
    private Rectangle requestedBounds;

    public MaskForm()
    {
        AutoScaleMode = AutoScaleMode.None;
        BackColor = Color.Black;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
    }

    public bool IsReady
    {
        get
        {
            if (!IsHandleCreated || !Visible)
            {
                return false;
            }

            if (User32.GetWindowRect(Handle, out var actual) == 0)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "mask bounds check failed");
            }

            return actual.Left == requestedBounds.Left &&
                actual.Top == requestedBounds.Top &&
                actual.Right == requestedBounds.Right &&
                actual.Bottom == requestedBounds.Bottom;
        }
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= User32.WindowExtendedStyleLayered |
                User32.WindowExtendedStyleTransparent |
                User32.WindowExtendedStyleNoActivate |
                User32.WindowExtendedStyleToolWindow;
            return parameters;
        }
    }

    public void Prepare(RectD nativeBounds)
    {
        requestedBounds = ToRectangle(nativeBounds);
        Bounds = requestedBounds;
    }

    public void ShowNoActivate()
    {
        if (!IsHandleCreated)
        {
            CreateHandle();
        }

        if (User32.SetLayeredWindowAttributes(
                Handle,
                0,
                byte.MaxValue,
                User32.LayeredWindowAlpha) == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "mask opacity failed");
        }

        SetVisibleCore(true);
        var flags = User32.SetWindowPositionNoActivate |
            User32.SetWindowPositionShowWindow |
            User32.SetWindowPositionNoOwnerZOrder;
        if (User32.SetWindowPos(
                Handle,
                User32.TopMostWindow,
                requestedBounds.X,
                requestedBounds.Y,
                requestedBounds.Width,
                requestedBounds.Height,
                flags) == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "mask positioning failed");
        }
    }

    private static Rectangle ToRectangle(RectD bounds)
    {
        if (!IsNativeInteger(bounds.X) || !IsNativeInteger(bounds.Y) ||
            !IsNativeInteger(bounds.Width) || !IsNativeInteger(bounds.Height) ||
            bounds.Width <= 0 || bounds.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(bounds));
        }

        return new Rectangle(
            checked((int)bounds.X),
            checked((int)bounds.Y),
            checked((int)bounds.Width),
            checked((int)bounds.Height));
    }

    private static bool IsNativeInteger(double value) =>
        !double.IsNaN(value) &&
        !double.IsInfinity(value) &&
        value >= int.MinValue &&
        value <= int.MaxValue &&
        value == Math.Truncate(value);
}
