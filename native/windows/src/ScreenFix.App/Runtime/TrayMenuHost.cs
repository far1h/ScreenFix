using ScreenFix.Core.Menu;

namespace ScreenFix.App.Runtime;

internal sealed class TrayMenuHost(
    NotifyIcon icon,
    Action<MenuCommand> commandSelected) : IMenuHost, IDisposable
{
    private ContextMenuStrip? menu;
    private bool disposed;

    public void Refresh(IReadOnlyList<MenuRow> rows)
    {
        ArgumentNullException.ThrowIfNull(rows);
        ObjectDisposedException.ThrowIf(disposed, this);

        var candidate = BuildMenu(rows);
        var retired = menu;
        menu = candidate;
        icon.ContextMenuStrip = candidate;
        retired?.Dispose();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        icon.ContextMenuStrip = null;
        menu?.Dispose();
        menu = null;
    }

    private ContextMenuStrip BuildMenu(IReadOnlyList<MenuRow> rows)
    {
        var candidate = new ContextMenuStrip();
        foreach (var row in rows)
        {
            if (row.IsSeparator)
            {
                candidate.Items.Add(new ToolStripSeparator());
                continue;
            }

            var item = new ToolStripMenuItem(row.Label)
            {
                Checked = row.IsChecked,
                Enabled = row.IsEnabled,
            };
            if (row.Command is { } command)
            {
                item.Click += (_, _) => commandSelected(command);
            }

            candidate.Items.Add(item);
        }

        return candidate;
    }
}
