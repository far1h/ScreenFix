using ScreenFix.Core.Menu;

namespace ScreenFix.Core.Tests;

public sealed class MenuStateTests
{
    [Fact]
    public void Build_EnabledConnectedStateHasExactOrderAndIntermediateStatus()
    {
        var rows = MenuState.Build(State());

        Assert.Equal(
            [
                "Paused: Window correction is not available in this build",
                "Disable",
                "Calibrate",
                "Select Monitor",
                "Reset to Defaults",
                "Reload",
                "<separator>",
                "Quit",
            ],
            Labels(rows));
        Assert.True(Row(rows, MenuCommand.ToggleEnabled).IsChecked);
        Assert.All(ActionRows(rows), row => Assert.True(row.IsEnabled));
    }

    [Theory]
    [InlineData(true, false, false, false, "Paused: Invalid configuration")]
    [InlineData(false, true, false, false, "Paused: Mask rendering failed")]
    [InlineData(false, false, true, false, "Paused: Selected display is disconnected")]
    [InlineData(false, false, false, true, "Paused: Select a monitor")]
    public void Build_UsesExactIndividualPausedReason(
        bool invalid,
        bool maskFailed,
        bool disconnected,
        bool missing,
        string expected)
    {
        var state = State() with
        {
            InvalidConfiguration = invalid,
            MaskRenderingFailed = maskFailed,
            HasSavedDisplay = !missing,
            DisplayConnected = !disconnected && !missing,
        };

        var rows = MenuState.Build(state);

        Assert.Equal(expected, Assert.Single(PausedRows(rows)).Label);
    }

    [Theory]
    [InlineData(true, true, true, false, "Paused: Invalid configuration")]
    [InlineData(true, false, false, false, "Paused: Invalid configuration")]
    [InlineData(false, true, true, false, "Paused: Mask rendering failed")]
    [InlineData(false, true, false, false, "Paused: Mask rendering failed")]
    public void Build_HigherPriorityPausedReasonWinsPairwiseCombinations(
        bool invalid,
        bool maskFailed,
        bool hasSaved,
        bool connected,
        string expected)
    {
        var rows = MenuState.Build(State() with
        {
            InvalidConfiguration = invalid,
            MaskRenderingFailed = maskFailed,
            HasSavedDisplay = hasSaved,
            DisplayConnected = connected,
        });

        Assert.Equal(expected, Assert.Single(PausedRows(rows)).Label);
    }

    [Fact]
    public void Build_IntentionalDisableHasNoPausedRow()
    {
        var rows = MenuState.Build(State() with
        {
            Enabled = false,
            DisplayConnected = false,
        });

        Assert.Empty(PausedRows(rows));
        var toggle = Row(rows, MenuCommand.ToggleEnabled);
        Assert.Equal("Enable", toggle.Label);
        Assert.False(toggle.IsChecked);
    }

    [Fact]
    public void Build_CalibrationSuppressesOnlyIntermediateStatusAndChecksCommand()
    {
        var rows = MenuState.Build(State() with { Calibrating = true });

        Assert.Empty(PausedRows(rows));
        Assert.True(Row(rows, MenuCommand.Calibrate).IsChecked);
    }

    [Fact]
    public void Build_DisplayDependentCommandsRequireConnectedSavedDisplay()
    {
        var rows = MenuState.Build(State() with
        {
            HasSavedDisplay = false,
            DisplayConnected = false,
        });

        Assert.False(Row(rows, MenuCommand.Calibrate).IsEnabled);
        Assert.False(Row(rows, MenuCommand.ResetDefaults).IsEnabled);
        Assert.True(Row(rows, MenuCommand.ToggleEnabled).IsEnabled);
        Assert.True(Row(rows, MenuCommand.SelectMonitor).IsEnabled);
        Assert.True(Row(rows, MenuCommand.Reload).IsEnabled);
        Assert.True(Row(rows, MenuCommand.Quit).IsEnabled);
    }

    [Fact]
    public void Build_EmitsAtMostOnePausedRowForEveryBooleanCombination()
    {
        for (var bits = 0; bits < 64; bits++)
        {
            var rows = MenuState.Build(new MenuStateInput(
                Enabled: (bits & 1) != 0,
                HasSavedDisplay: (bits & 2) != 0,
                DisplayConnected: (bits & 4) != 0,
                Calibrating: (bits & 8) != 0,
                InvalidConfiguration: (bits & 16) != 0,
                MaskRenderingFailed: (bits & 32) != 0));

            Assert.True(PausedRows(rows).Count() <= 1);
        }
    }

    private static MenuStateInput State() => new(
        Enabled: true,
        HasSavedDisplay: true,
        DisplayConnected: true,
        Calibrating: false,
        InvalidConfiguration: false,
        MaskRenderingFailed: false);

    private static IEnumerable<MenuRow> PausedRows(IReadOnlyList<MenuRow> rows) =>
        rows.Where(row => row.Label.StartsWith("Paused:", StringComparison.Ordinal));

    private static string[] Labels(IReadOnlyList<MenuRow> rows) => rows
        .Select(row => row.IsSeparator ? "<separator>" : row.Label)
        .ToArray();

    private static IEnumerable<MenuRow> ActionRows(IReadOnlyList<MenuRow> rows) => rows
        .Where(row => row.Command is not null);

    private static MenuRow Row(IReadOnlyList<MenuRow> rows, MenuCommand command) =>
        Assert.Single(rows, row => row.Command == command);
}
