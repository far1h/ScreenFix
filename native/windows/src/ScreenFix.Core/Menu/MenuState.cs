namespace ScreenFix.Core.Menu;

public enum MenuCommand
{
    ToggleEnabled,
    Calibrate,
    SelectMonitor,
    ResetDefaults,
    Reload,
    Quit,
}

public sealed record MenuRow(
    string Label,
    bool IsChecked,
    bool IsEnabled,
    bool IsSeparator,
    MenuCommand? Command);

public static class MenuState
{
    public static IReadOnlyList<MenuRow> Build(
        bool enabled,
        bool calibrating,
        bool displayConnected,
        string? pausedReason,
        bool implementationReady)
    {
        var rows = new List<MenuRow>();
        if (!string.IsNullOrWhiteSpace(pausedReason))
        {
            rows.Add(new MenuRow($"Paused: {pausedReason}", false, false, false, null));
        }

        rows.Add(Action(
            enabled ? "Disable" : "Enable",
            MenuCommand.ToggleEnabled,
            enabled,
            implementationReady));
        rows.Add(Action(
            "Calibrate",
            MenuCommand.Calibrate,
            calibrating,
            implementationReady && displayConnected));
        rows.Add(Action(
            "Select Monitor",
            MenuCommand.SelectMonitor,
            false,
            implementationReady));
        rows.Add(Action(
            "Reset to Defaults",
            MenuCommand.ResetDefaults,
            false,
            implementationReady && displayConnected));
        rows.Add(Action("Reload", MenuCommand.Reload, false, implementationReady));
        rows.Add(new MenuRow(string.Empty, false, false, true, null));
        rows.Add(Action("Quit", MenuCommand.Quit, false, true));
        return rows;
    }

    private static MenuRow Action(
        string label,
        MenuCommand command,
        bool isChecked,
        bool isEnabled) =>
        new(label, isChecked, isEnabled, false, command);
}
