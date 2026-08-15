namespace ScreenFix.App.Notifications;

internal sealed class SystemMessageTargetBridge : ISystemMessageTarget
{
    private ISystemMessageTarget? target;

    public void Connect(ISystemMessageTarget value)
    {
        ArgumentNullException.ThrowIfNull(value);
        if (target is not null)
        {
            throw new InvalidOperationException("System message target is already connected");
        }

        target = value;
    }

    public void Disconnect() => target = null;

    public void ReconcileDisplays() => target?.ReconcileDisplays();

    public void Suspend() => target?.Suspend();

    public void Resume() => target?.Resume();

    public void CancelEditorForDpiChange(long editorGeneration) =>
        target?.CancelEditorForDpiChange(editorGeneration);
}
