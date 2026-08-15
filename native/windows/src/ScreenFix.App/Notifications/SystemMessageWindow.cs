namespace ScreenFix.App.Notifications;

internal sealed class SystemMessageWindow : NativeWindow, IDisposable
{
    private const int WindowStylePopup = unchecked((int)0x80000000);
    private const int ExtendedStyleToolWindow = 0x00000080;
    private const int ExtendedStyleNoActivate = 0x08000000;
    private bool disposed;

    public SystemMessageWindow(SystemMessageCoordinator coordinator)
    {
        Coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        CreateHandle(new CreateParams
        {
            Caption = "ScreenFix.SystemMessages",
            X = -32_000,
            Y = -32_000,
            Width = 1,
            Height = 1,
            Style = WindowStylePopup,
            ExStyle = ExtendedStyleToolWindow | ExtendedStyleNoActivate,
        });
    }

    public SystemMessageCoordinator Coordinator { get; }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        Coordinator.ReplaceGeneration(Coordinator.Generation + 1);
        DestroyHandle();
    }

    protected override void WndProc(ref Message message)
    {
        var messageId = message.Msg;
        var value = unchecked((int)message.WParam.ToInt64());
        var generation = Coordinator.Generation;
        Coordinator.Handle(messageId, value, generation);
        base.WndProc(ref message);
    }
}
