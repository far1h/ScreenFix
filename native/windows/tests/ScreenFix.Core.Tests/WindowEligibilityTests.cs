using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.Core.Tests;

public sealed class WindowEligibilityTests
{
    [Fact]
    public void IsEligible_AcceptsIntersectingOrdinaryWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [new RectD(600, 0, 200, 800)]);

        Assert.True(result);
    }

    [Fact]
    public void IsEligible_RejectsHiddenWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsVisible = false },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsMinimizedWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsMinimized = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsNonRootWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsRootTopLevel = false },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsOwnedPopup()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsOwned = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsScreenFixOwnedWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsScreenFixOwned = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsPlatformOwnedWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsPlatformOwned = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsToolOrMenuWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsToolOrMenu = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsNonMovableWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsMovable = false },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsBorderlessFullScreenWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsBorderlessFullScreen = true },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsWindowOnAnotherDisplay()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { IsOnSelectedDisplay = false },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsNonIntersectingWindow()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [new RectD(700, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_TreatsTouchingEdgesAsNonIntersecting()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [new RectD(700, 100, 200, 300)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsNonFiniteWindowFrame()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with
            {
                VisibleFrame = new RectD(300, 100, double.PositiveInfinity, 300),
            },
            [new RectD(600, 0, 200, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_RejectsNonFiniteMaskFrame()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [new RectD(600, 0, double.PositiveInfinity, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_AcceptsOverlapWhenAnotherMaskOnlyTouchesEdge()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [
                new RectD(700, 100, 200, 300),
                new RectD(650, 100, 200, 300),
            ]);

        Assert.True(result);
    }

    [Theory]
    [InlineData(0, 300)]
    [InlineData(400, -1)]
    public void IsEligible_RejectsNonPositiveWindowSize(double width, double height)
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts() with { VisibleFrame = new RectD(300, 100, width, height) },
            [new RectD(300, 0, 500, 800)]);

        Assert.False(result);
    }

    [Fact]
    public void IsEligible_AcceptsMaximizedOrdinaryWindowFacts()
    {
        var result = WindowEligibility.IsEligible(
            OrdinaryFacts(),
            [new RectD(600, 0, 200, 800)]);

        Assert.True(result);
    }

    private static WindowFacts OrdinaryFacts() => new(
            Key: 17,
            VisibleFrame: new RectD(300, 100, 400, 300),
            IsVisible: true,
            IsMinimized: false,
            IsRootTopLevel: true,
            IsOwned: false,
            IsScreenFixOwned: false,
            IsPlatformOwned: false,
            IsToolOrMenu: false,
            IsMovable: true,
            IsBorderlessFullScreen: false,
            IsOnSelectedDisplay: true);
}
