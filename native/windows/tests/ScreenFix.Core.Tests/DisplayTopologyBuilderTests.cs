using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class DisplayTopologyBuilderTests
{
    [Fact]
    public void Build_JoinsGdiNamesCaseInsensitivelyAndPrefersTargetFriendlyName()
    {
        MonitorRecord[] monitors =
        [
            new(
                @"\\.\DISPLAY1",
                "Independent name",
                new RectD(-1920, 0, 1920, 1080),
                new RectD(-1920, 0, 1920, 1040)),
        ];
        ActivePathRecord[] paths =
        [
            new(@"\\.\display1", "target-path", "Target friendly name"),
        ];

        var result = DisplayTopologyBuilder.Build(monitors, paths);

        var display = Assert.Single(result);
        Assert.Equal("target-path", display.StableId);
        Assert.Equal("Target friendly name", display.Name);
        Assert.Equal(new RectD(-1920, 0, 1920, 1080), display.FullBounds);
        Assert.Equal(new RectD(-1920, 0, 1920, 1040), display.WorkArea);
    }

    [Fact]
    public void Build_SortsByFullXThenYThenOrdinalGdiName()
    {
        MonitorRecord[] monitors =
        [
            Monitor(@"\\.\DISPLAY3", 0, 100),
            Monitor(@"\\.\DISPLAY2", -100, 0),
            Monitor(@"\\.\DISPLAY1", 0, 0),
            Monitor(@"\\.\DISPLAY0", 0, 0),
        ];

        var result = DisplayTopologyBuilder.Build(monitors, []);

        Assert.Equal(
            [@"\\.\DISPLAY2", @"\\.\DISPLAY0", @"\\.\DISPLAY1", @"\\.\DISPLAY3"],
            result.Select(display => display.Name));
    }

    [Fact]
    public void Build_OmitsInvalidMonitorFramesWithoutDiscardingValidMonitors()
    {
        MonitorRecord[] monitors =
        [
            new("empty", "Empty", new RectD(0, 0, 0, 100), new RectD(0, 0, 0, 90)),
            new("negative", "Negative", new RectD(0, 0, -1, 100), new RectD(0, 0, 1, 90)),
            Monitor("valid", -100, 20),
        ];

        var result = DisplayTopologyBuilder.Build(monitors, []);

        Assert.Equal("valid", Assert.Single(result).Name);
    }

    [Fact]
    public void Build_UsesGdiLabelForDiagnosticsWithoutAllowingNameFallback()
    {
        var monitor = new MonitorRecord(
            @"\\.\DISPLAY4",
            string.Empty,
            new RectD(0, 0, 1920, 1080),
            new RectD(0, 0, 1920, 1040));

        var display = Assert.Single(DisplayTopologyBuilder.Build([monitor], []));
        var saved = new ScreenFix.Core.Configuration.DisplayIdentity(
            "missing",
            @"\\.\DISPLAY4",
            1920,
            1080);

        Assert.Equal(@"\\.\DISPLAY4", display.Name);
        Assert.Null(DisplayMatcher.Find(saved, [display]));
    }

    [Fact]
    public void Build_AmbiguousClonedSourceDoesNotGuessStableId()
    {
        var monitor = Monitor(@"\\.\DISPLAY1", 0, 0) with { FallbackName = "Independent" };
        ActivePathRecord[] paths =
        [
            new(@"\\.\DISPLAY1", "target-a", "Target A"),
            new(@"\\.\DISPLAY1", "target-b", "Target B"),
        ];

        var display = Assert.Single(DisplayTopologyBuilder.Build([monitor], paths));

        Assert.Null(display.StableId);
        Assert.Equal("Independent", display.Name);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Build_PreservesIndependentFallbackAcrossDisplayConfigFailure(bool partialFailure)
    {
        var monitor = Monitor(@"\\.\DISPLAY1", -1920, -100) with
        {
            FallbackName = "Ultrawide",
            FullBounds = new RectD(-1920, -100, 1920, 1080),
        };
        ActivePathRecord[] paths = partialFailure
            ? [new ActivePathRecord(@"\\.\DISPLAY1", null, null)]
            : [];

        var display = Assert.Single(DisplayTopologyBuilder.Build([monitor], paths));
        var saved = new ScreenFix.Core.Configuration.DisplayIdentity(
            "unavailable-target",
            "Ultrawide",
            1920,
            1080);

        Assert.Null(display.StableId);
        Assert.Equal(-1920, display.FullBounds.X);
        Assert.Same(display, DisplayMatcher.Find(saved, [display]));
    }

    [Fact]
    public void Build_ReturnsOneDisplayPerMonitorAndIgnoresUnmatchedPaths()
    {
        MonitorRecord[] monitors =
        [
            Monitor(@"\\.\DISPLAY1", 0, 0),
            Monitor(@"\\.\DISPLAY2", 100, 0),
        ];
        ActivePathRecord[] paths =
        [
            new(@"\\.\DISPLAY1", "target-one", "One"),
            new(@"\\.\INACTIVE", "inactive-target", "Inactive"),
        ];

        var result = DisplayTopologyBuilder.Build(monitors, paths);

        Assert.Equal(2, result.Count);
        Assert.DoesNotContain(result, display => display.StableId == "inactive-target");
    }

    private static MonitorRecord Monitor(string gdiName, int x, int y) =>
        new(gdiName, gdiName, new RectD(x, y, 100, 100), new RectD(x, y, 100, 90));
}
