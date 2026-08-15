using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class DisplayMatcherTests
{
    [Fact]
    public void Find_StableIdMatchWinsOverMatchingNameAndDimensions()
    {
        var saved = new DisplayIdentity("DISPLAY-PATH-A", "Ultrawide", 3440, 1440);
        ConnectedDisplay[] connected =
        [
            Display("display-path-b", "Ultrawide", 3440, 1440),
            Display("display-path-a", "Other", 1920, 1080),
        ];

        var result = DisplayMatcher.Find(saved, connected);

        Assert.Same(connected[1], result);
    }

    [Fact]
    public void Find_UniqueOrdinalNameAndDimensionsFallbackSucceeds()
    {
        var saved = new DisplayIdentity("missing", "Ultrawide", 3440, 1440);
        ConnectedDisplay[] connected =
        [
            Display(null, "ULTRAWIDE", 3440, 1440),
            Display(null, "Ultrawide", 3440, 1440),
        ];

        var result = DisplayMatcher.Find(saved, connected);

        Assert.Same(connected[1], result);
    }

    [Fact]
    public void Find_DuplicateStableIdsReturnNull()
    {
        var saved = new DisplayIdentity("display-path-a", "Ultrawide", 3440, 1440);
        ConnectedDisplay[] connected =
        [
            Display("DISPLAY-PATH-A", "First", 1920, 1080),
            Display("display-path-a", "Second", 2560, 1440),
        ];

        var result = DisplayMatcher.Find(saved, connected);

        Assert.Null(result);
    }

    [Fact]
    public void Find_NoFallbackCandidateReturnsNull()
    {
        var saved = new DisplayIdentity("missing", "Ultrawide", 3440, 1440);

        var result = DisplayMatcher.Find(
            saved,
            [Display(null, "Other", 3440, 1440)]);

        Assert.Null(result);
    }

    [Fact]
    public void Find_AmbiguousFallbackCandidatesReturnNull()
    {
        var saved = new DisplayIdentity("missing", "Ultrawide", 3440, 1440);
        ConnectedDisplay[] connected =
        [
            Display(null, "Ultrawide", 3440, 1440),
            Display(null, "Ultrawide", 3440, 1440),
        ];

        var result = DisplayMatcher.Find(saved, connected);

        Assert.Null(result);
    }

    private static ConnectedDisplay Display(string? stableId, string name, int width, int height) =>
        new(stableId, name, width, height, new RectD(0, 0, width, height), new RectD(0, 0, width, height));
}
