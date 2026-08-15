using ScreenFix.Core.Displays;

namespace ScreenFix.App.Calibration;

internal sealed class MonitorPickerForm : Form
{
    private readonly ListBox monitorList = new();
    private readonly Button saveButton = new();

    public MonitorPickerForm(IReadOnlyList<ConnectedDisplay> displays)
    {
        ArgumentNullException.ThrowIfNull(displays);

        Text = "Select ScreenFix monitor";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(520, 300);

        monitorList.Bounds = new Rectangle(16, 16, 488, 220);
        monitorList.DrawMode = DrawMode.OwnerDrawFixed;
        monitorList.DrawItem += DrawMonitor;
        monitorList.SelectedIndexChanged += (_, _) =>
            saveButton.Enabled = SelectedDisplay?.StableId is not null;
        foreach (var display in displays)
        {
            monitorList.Items.Add(new PickerEntry(display));
        }

        saveButton.Text = "Save";
        saveButton.Bounds = new Rectangle(312, 252, 92, 32);
        saveButton.Enabled = false;
        saveButton.DialogResult = DialogResult.OK;

        var cancelButton = new Button
        {
            Text = "Cancel",
            Bounds = new Rectangle(412, 252, 92, 32),
            DialogResult = DialogResult.Cancel,
        };

        AcceptButton = saveButton;
        CancelButton = cancelButton;
        Controls.Add(monitorList);
        Controls.Add(saveButton);
        Controls.Add(cancelButton);
    }

    public ConnectedDisplay? SelectedDisplay =>
        (monitorList.SelectedItem as PickerEntry)?.Display is { StableId: not null } display
            ? display
            : null;

    private void DrawMonitor(object? sender, DrawItemEventArgs eventArgs)
    {
        eventArgs.DrawBackground();
        if (eventArgs.Index < 0 || eventArgs.Index >= monitorList.Items.Count)
        {
            return;
        }

        var entry = (PickerEntry)monitorList.Items[eventArgs.Index];
        var color = entry.Display.StableId is null
            ? SystemColors.GrayText
            : eventArgs.ForeColor;
        TextRenderer.DrawText(
            eventArgs.Graphics,
            entry.ToString(),
            eventArgs.Font,
            eventArgs.Bounds,
            color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        eventArgs.DrawFocusRectangle();
    }

    private sealed record PickerEntry(ConnectedDisplay Display)
    {
        public override string ToString()
        {
            var origin = $"{Display.FullBounds.X:0}/{Display.FullBounds.Y:0}";
            var unavailable = Display.StableId is null ? " — unavailable" : string.Empty;
            return $"{Display.Name} — {Display.Width} x {Display.Height} — {origin}{unavailable}";
        }
    }
}
