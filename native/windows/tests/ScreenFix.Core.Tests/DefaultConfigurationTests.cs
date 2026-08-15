using ScreenFix.Core.Configuration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class DefaultConfigurationTests
{
    [Fact]
    public void Create_UsesPermanentThreeBandDefaults()
    {
        var display = new DisplayIdentity("display-1", "Ultrawide", 3440, 1440);

        var config = DefaultConfiguration.Create(display);

        Assert.Equal(1, config.SchemaVersion);
        Assert.True(config.Enabled);
        Assert.Same(display, config.Display);
        Assert.Equal(3, config.Bands.Count);
        Assert.All(config.Bands, band => Assert.Equal(1215d / 3440d, band.X));
        Assert.All(config.Bands, band => Assert.Equal((1920d - 1215d) / 3440d, band.Width));
        Assert.Equal(new[] { 0d, 0.34d, 0.73d }, config.Bands.Select(band => band.Y));
        Assert.Equal(new[] { 0.34d, 0.39d, 0.27d }, config.Bands.Select(band => band.Height));
    }

    [Fact]
    public void Create_ConvertsEveryDefaultToExactDamagedDisplayBounds()
    {
        var config = DefaultConfiguration.Create(
            new DisplayIdentity("display-1", "Ultrawide", 3440, 1440));
        var fullFrame = new RectD(0, 0, 3440, 1440);

        var absoluteBands = config.Bands.Select(band => band.ToAbsolute(fullFrame));

        Assert.All(absoluteBands, band => Assert.Equal(1215, band.X));
        Assert.All(absoluteBands, band => Assert.Equal(1920, band.Right));
    }
}
