using System.ComponentModel;
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Calibration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Calibration;

internal sealed class CalibrationForm : Form
{
    private const int DpiChangedMessage = 0x02E0;

    private readonly Rectangle physicalBounds;
    private readonly uint dpi;
    private readonly long generation;
    private readonly CalibrationHostCallbacks callbacks;
    private readonly CalibrationLayoutSpec layout;
    private readonly RectD logicalFrame;
    private readonly CalibrationSession session;
    private readonly CalibrationCommandAdapter commands;
    private bool intentionallyChangingCapture;
    private bool renderFailureReported;
    private bool readyForRendering;

    public CalibrationForm(
        Rectangle physicalBounds,
        uint dpi,
        long generation,
        IReadOnlyList<RectD> bands,
        CalibrationLayoutSpec layout,
        CalibrationHostCallbacks callbacks)
    {
        this.physicalBounds = physicalBounds;
        this.dpi = dpi;
        this.generation = generation;
        this.layout = layout;
        this.callbacks = callbacks;
        logicalFrame = new RectD(
            0,
            0,
            physicalBounds.Width * 96d / dpi,
            physicalBounds.Height * 96d / dpi);
        session = new CalibrationSession(bands, logicalFrame);
        commands = new CalibrationCommandAdapter(session, ReleaseCapture);

        AutoScaleMode = AutoScaleMode.None;
        Bounds = physicalBounds;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= User32.WindowExtendedStyleLayered |
                User32.WindowExtendedStyleToolWindow;
            return parameters;
        }
    }

    public void PrepareAndShow()
    {
        if (!IsHandleCreated)
        {
            CreateHandle();
        }

        var actualDpi = User32.GetDpiForWindow(Handle);
        if (actualDpi == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "editor DPI lookup failed");
        }

        if (actualDpi != dpi || DeviceDpi != dpi)
        {
            throw new InvalidOperationException("display DPI changed during calibration startup");
        }

        Bounds = physicalBounds;
        readyForRendering = true;
        RenderLayered();
        Show();
        if (User32.GetWindowRect(Handle, out var actualBounds) == 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "editor bounds check failed");
        }

        if (actualBounds.Left != physicalBounds.Left ||
            actualBounds.Top != physicalBounds.Top ||
            actualBounds.Right != physicalBounds.Right ||
            actualBounds.Bottom != physicalBounds.Bottom)
        {
            throw new InvalidOperationException("display bounds changed during calibration startup");
        }
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        _ = eventArgs;
        if (readyForRendering)
        {
            TryRenderLayered();
        }
    }

    protected override void OnMouseDown(MouseEventArgs eventArgs)
    {
        base.OnMouseDown(eventArgs);
        var point = ToLogical(eventArgs.Location);
        if (eventArgs.Button == MouseButtons.Left && Contains(layout.SaveButton, point))
        {
            commands.Save(bands => callbacks.Save(generation, bands));
            return;
        }

        if (eventArgs.Button == MouseButtons.Left && Contains(layout.CancelButton, point))
        {
            commands.Cancel(() => callbacks.Cancel(generation));
            return;
        }

        var action = session.PointerDown(point, eventArgs.Button == MouseButtons.Left);
        ApplyCaptureAction(action);
    }

    protected override void OnMouseMove(MouseEventArgs eventArgs)
    {
        base.OnMouseMove(eventArgs);
        var action = session.PointerMove(
            ToLogical(eventArgs.Location),
            (eventArgs.Button & MouseButtons.Left) != 0);
        if (action == CalibrationAction.Render)
        {
            TryRenderLayered();
        }
    }

    protected override void OnMouseUp(MouseEventArgs eventArgs)
    {
        base.OnMouseUp(eventArgs);
        var action = session.PointerUp(
            ToLogical(eventArgs.Location),
            eventArgs.Button == MouseButtons.Left);
        ApplyCaptureAction(action);
    }

    protected override void OnMouseCaptureChanged(EventArgs eventArgs)
    {
        base.OnMouseCaptureChanged(eventArgs);
        if (!intentionallyChangingCapture && !Capture)
        {
            session.CaptureLost();
        }
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == DpiChangedMessage)
        {
            callbacks.DpiChanged(generation);
            return;
        }

        base.WndProc(ref message);
    }

    private void ApplyCaptureAction(CalibrationAction action)
    {
        if (action == CalibrationAction.AcquireCapture && !Capture)
        {
            SetCapture(true);
        }
        else if (action == CalibrationAction.ReleaseCapture && Capture)
        {
            SetCapture(false);
        }
    }

    private void SetCapture(bool value)
    {
        intentionallyChangingCapture = true;
        try
        {
            Capture = value;
        }
        finally
        {
            intentionallyChangingCapture = false;
        }
    }

    private void ReleaseCapture()
    {
        if (Capture)
        {
            SetCapture(false);
        }
    }

    private void RenderLayered()
    {
        using var bitmap = CalibrationLayeredRenderer.Render(
            physicalBounds.Width,
            physicalBounds.Height,
            dpi,
            logicalFrame,
            session.WorkingBands,
            layout);
        CalibrationLayeredRenderer.Present(Handle, physicalBounds, bitmap);
    }

    private void TryRenderLayered()
    {
        if (renderFailureReported || IsDisposed)
        {
            return;
        }

        try
        {
            RenderLayered();
        }
        catch
        {
            renderFailureReported = true;
            callbacks.Cancel(generation);
        }
    }

    private PointD ToLogical(Point point) => new(
        point.X * 96d / dpi,
        point.Y * 96d / dpi);

    private static bool Contains(RectD frame, PointD point) =>
        point.X >= frame.X &&
        point.X < frame.Right &&
        point.Y >= frame.Y &&
        point.Y < frame.Bottom;
}
