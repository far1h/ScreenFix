using ScreenFix.App.Runtime;

namespace ScreenFix.Windows.Tests;

public sealed class TrayIconLoaderTests
{
    private static readonly Size RequestedSize = new(16, 16);

    [Fact]
    public void BrandedIcon_HasStableManifestNameAndRequestedSmallSize()
    {
        Assert.Equal(
            [TrayIconLoader.ResourceName],
            typeof(TrayIconLoader).Assembly.GetManifestResourceNames());

        using var icon = TrayIconLoader.Load(
            TrayIconLoader.ResourceName,
            RequestedSize);

        Assert.Equal(RequestedSize.Width, icon.Width);
        Assert.Equal(RequestedSize.Height, icon.Height);
        Assert.NotEqual(nint.Zero, icon.Handle);
    }

    [Fact]
    public void BrandedIcon_RemainsUsableAfterResourceStreamAndSourceIconClose()
    {
        using var icon = TrayIconLoader.Load(
            TrayIconLoader.ResourceName,
            RequestedSize);

        Assert.Equal(RequestedSize.Width, icon.Width);
        Assert.Equal(RequestedSize.Height, icon.Height);
        Assert.NotEqual(nint.Zero, icon.Handle);
    }

    [Fact]
    public void MissingResource_ReturnsIndependentOwnedFallback()
    {
        using var first = TrayIconLoader.Load(
            "ScreenFix.App.Resources.MissingOne.ico",
            RequestedSize);
        using var second = TrayIconLoader.Load(
            "ScreenFix.App.Resources.MissingTwo.ico",
            RequestedSize);

        first.Dispose();

        Assert.NotEqual(nint.Zero, second.Handle);
    }
}
