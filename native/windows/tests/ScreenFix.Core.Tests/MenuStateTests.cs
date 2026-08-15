using ScreenFix.Core.Menu;

namespace ScreenFix.Core.Tests;

public sealed class MenuStateTests
{
    [Fact]
    public void Build_EnabledStateHasExactOrderAndChecksDisable()
    {
        var rows = MenuState.Build(
            enabled: true,
            calibrating: false,
            displayConnected: true,
            pausedReason: null,
            implementationReady: true);

        Assert.Equal(
            ["Disable", "Calibrate", "Select Monitor", "Reset to Defaults", "Reload", "<separator>", "Quit"],
            Labels(rows));
        Assert.True(Row(rows, MenuCommand.ToggleEnabled).IsChecked);
        Assert.All(ActionRows(rows), row => Assert.True(row.IsEnabled));
    }

    [Fact]
    public void Build_DisabledStateShowsUncheckedEnable()
    {
        var rows = MenuState.Build(false, false, true, null, true);

        var toggle = Row(rows, MenuCommand.ToggleEnabled);
        Assert.Equal("Enable", toggle.Label);
        Assert.False(toggle.IsChecked);
    }

    [Fact]
    public void Build_CalibratingStateChecksCalibrate()
    {
        var rows = MenuState.Build(true, true, true, null, true);

        Assert.True(Row(rows, MenuCommand.Calibrate).IsChecked);
    }

    [Fact]
    public void Build_DisconnectedStateDisablesDisplayDependentCommands()
    {
        var rows = MenuState.Build(true, false, false, null, true);

        Assert.False(Row(rows, MenuCommand.Calibrate).IsEnabled);
        Assert.False(Row(rows, MenuCommand.ResetDefaults).IsEnabled);
        Assert.True(Row(rows, MenuCommand.SelectMonitor).IsEnabled);
        Assert.True(Row(rows, MenuCommand.Reload).IsEnabled);
    }

    [Fact]
    public void Build_PausedStatePrependsDisabledStatus()
    {
        var rows = MenuState.Build(
            true,
            false,
            true,
            "window correction permission missing",
            true);

        Assert.Equal("Paused: window correction permission missing", rows[0].Label);
        Assert.False(rows[0].IsEnabled);
        Assert.Null(rows[0].Command);
        Assert.False(rows[0].IsSeparator);
        Assert.Equal("Disable", rows[1].Label);
    }

    [Fact]
    public void Build_UnreadyShellDisablesEveryActionExceptQuit()
    {
        var rows = MenuState.Build(true, false, true, null, false);

        foreach (var row in ActionRows(rows))
        {
            Assert.Equal(row.Command == MenuCommand.Quit, row.IsEnabled);
        }
    }

    [Fact]
    public void Build_SelectMonitorStaysAvailableWithoutConnectedDisplay()
    {
        var rows = MenuState.Build(false, false, false, null, true);

        Assert.True(Row(rows, MenuCommand.SelectMonitor).IsEnabled);
    }

    private static string[] Labels(IReadOnlyList<MenuRow> rows) => rows
        .Select(row => row.IsSeparator ? "<separator>" : row.Label)
        .ToArray();

    private static IEnumerable<MenuRow> ActionRows(IReadOnlyList<MenuRow> rows) => rows
        .Where(row => row.Command is not null);

    private static MenuRow Row(IReadOnlyList<MenuRow> rows, MenuCommand command) =>
        Assert.Single(rows, row => row.Command == command);
}
