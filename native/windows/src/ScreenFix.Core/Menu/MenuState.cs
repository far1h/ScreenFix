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

public sealed record MenuStateInput(
    bool Enabled,
    bool HasSavedDisplay,
    bool DisplayConnected,
    bool Calibrating,
    bool InvalidConfiguration,
    bool MaskRenderingFailed);

public static class MenuState
{
    public static IReadOnlyList<MenuRow> Build(MenuStateInput state)
    {
        var rows = new List<MenuRow>();
        var pausedReason = PausedReason(state);
        if (pausedReason is not null)
        {
            rows.Add(new MenuRow(pausedReason, false, false, false, null));
        }

        rows.Add(Action(
            state.Enabled ? "Disable" : "Enable",
            MenuCommand.ToggleEnabled,
            state.Enabled,
            true));
        rows.Add(Action(
            "Calibrate",
            MenuCommand.Calibrate,
            state.Calibrating,
            state.HasSavedDisplay && state.DisplayConnected));
        rows.Add(Action(
            "Select Monitor",
            MenuCommand.SelectMonitor,
            false,
            true));
        rows.Add(Action(
            "Reset to Defaults",
            MenuCommand.ResetDefaults,
            false,
            state.HasSavedDisplay && state.DisplayConnected));
        rows.Add(Action("Reload", MenuCommand.Reload, false, true));
        rows.Add(new MenuRow(string.Empty, false, false, true, null));
        rows.Add(Action("Quit", MenuCommand.Quit, false, true));
        return rows;
    }

    private static string? PausedReason(MenuStateInput state)
    {
        if (state.InvalidConfiguration)
        {
            return "Paused: Invalid configuration";
        }

        if (state.MaskRenderingFailed)
        {
            return "Paused: Mask rendering failed";
        }

        if (state.Enabled && state.HasSavedDisplay && !state.DisplayConnected)
        {
            return "Paused: Selected display is disconnected";
        }

        if (!state.HasSavedDisplay)
        {
            return "Paused: Select a monitor";
        }

        if (state.Enabled && state.DisplayConnected && !state.Calibrating)
        {
            return "Paused: Window correction is not available in this build";
        }

        return null;
    }

    private static MenuRow Action(
        string label,
        MenuCommand command,
        bool isChecked,
        bool isEnabled) =>
        new(label, isChecked, isEnabled, false, command);
}
