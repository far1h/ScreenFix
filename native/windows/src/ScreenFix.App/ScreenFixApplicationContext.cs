using ScreenFix.App.Lifecycle;
using ScreenFix.Core.Menu;

namespace ScreenFix.App;

internal sealed class ScreenFixApplicationContext : ApplicationContext
{
    private readonly ResourceOwner resources = new();

    public ScreenFixApplicationContext(SingleInstanceGate gate)
    {
        ArgumentNullException.ThrowIfNull(gate);
        resources.Register(gate.Dispose);

        try
        {
            var icon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "ScreenFix",
            };
            resources.Register(icon.Dispose);

            var menu = BuildMenu();
            resources.Register(menu.Dispose);
            icon.ContextMenuStrip = menu;
            resources.Register(() => icon.Visible = false);
            icon.Visible = true;
        }
        catch
        {
            resources.Dispose();
            throw;
        }
    }

    protected override void ExitThreadCore()
    {
        try
        {
            resources.Dispose();
        }
        finally
        {
            base.ExitThreadCore();
        }
    }

    protected override void Dispose(bool disposing)
    {
        try
        {
            if (disposing)
            {
                resources.Dispose();
            }
        }
        finally
        {
            base.Dispose(disposing);
        }
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        var rows = MenuState.Build(new MenuStateInput(
            Enabled: false,
            HasSavedDisplay: false,
            DisplayConnected: false,
            Calibrating: false,
            InvalidConfiguration: false,
            MaskRenderingFailed: false));

        foreach (var row in rows)
        {
            if (row.IsSeparator)
            {
                menu.Items.Add(new ToolStripSeparator());
                continue;
            }

            var item = new ToolStripMenuItem(row.Label)
            {
                Checked = row.IsChecked,
                Enabled = row.IsEnabled,
            };
            if (row.Command == MenuCommand.Quit)
            {
                item.Click += (_, _) => ExitThread();
            }

            menu.Items.Add(item);
        }

        return menu;
    }
}
