using ScreenFix.Core.Configuration;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Tests;

public sealed class ConfigValidatorTests
{
    [Fact]
    public void Validate_AcceptsPermanentDefaults()
    {
        var result = ConfigValidator.Validate(ValidConfiguration());

        Assert.True(result.IsValid);
        Assert.Null(result.Error);
    }

    [Fact]
    public void Validate_RejectsNullConfiguration()
    {
        AssertInvalid("configuration is required", null);
    }

    [Fact]
    public void Validate_RejectsUnknownSchema()
    {
        AssertInvalid(
            "schema version must be 1",
            ValidConfiguration() with { SchemaVersion = 2 });
    }

    [Fact]
    public void Validate_RejectsMissingDisplay()
    {
        AssertInvalid(
            "display is required",
            ValidConfiguration() with { Display = null! });
    }

    [Fact]
    public void Validate_RejectsEmptyStableId()
    {
        var config = ValidConfiguration();

        AssertInvalid(
            "display stable ID is required",
            config with { Display = config.Display with { StableId = " " } });
    }

    [Fact]
    public void Validate_RejectsEmptyDisplayName()
    {
        var config = ValidConfiguration();

        AssertInvalid(
            "display name is required",
            config with { Display = config.Display with { Name = string.Empty } });
    }

    [Fact]
    public void Validate_RejectsNonPositiveDisplayDimensions()
    {
        var config = ValidConfiguration();

        AssertInvalid(
            "display dimensions must be finite and positive",
            config with { Display = config.Display with { Width = 0 } });
        AssertInvalid(
            "display dimensions must be finite and positive",
            config with { Display = config.Display with { Height = -1 } });
    }

    [Fact]
    public void Validate_RejectsNonFiniteDisplayDimensions()
    {
        var config = ValidConfiguration();

        AssertInvalid(
            "display dimensions must be finite and positive",
            config with { Display = config.Display with { Width = double.NaN } });
        AssertInvalid(
            "display dimensions must be finite and positive",
            config with { Display = config.Display with { Height = double.PositiveInfinity } });
    }

    [Fact]
    public void Validate_RequiresExactlyThreeBands()
    {
        AssertInvalid(
            "exactly three bands are required",
            ValidConfiguration() with { Bands = [] });
        AssertInvalid(
            "exactly three bands are required",
            ValidConfiguration() with { Bands = null! });
    }

    [Fact]
    public void Validate_RejectsNonFiniteBandValues()
    {
        AssertInvalid(
            "band values must be finite",
            WithFirstBand(new RectD(double.NaN, 0, 0.2, 0.3)));
        AssertInvalid(
            "band values must be finite",
            WithFirstBand(new RectD(0.2, 0, double.NegativeInfinity, 0.3)));
    }

    [Fact]
    public void Validate_RejectsNonPositiveBandSize()
    {
        AssertInvalid(
            "band size must be positive",
            WithFirstBand(new RectD(0.2, 0, 0, 0.3)));
        AssertInvalid(
            "band size must be positive",
            WithFirstBand(new RectD(0.2, 0, 0.2, -0.1)));
    }

    [Fact]
    public void Validate_RejectsNegativeBandOrigin()
    {
        AssertInvalid(
            "band origin must be non-negative",
            WithFirstBand(new RectD(-0.01, 0, 0.2, 0.3)));
        AssertInvalid(
            "band origin must be non-negative",
            WithFirstBand(new RectD(0.2, -0.01, 0.2, 0.3)));
    }

    [Fact]
    public void Validate_RejectsBandBoundsAboveOne()
    {
        AssertInvalid(
            "band bounds must not exceed 1",
            WithFirstBand(new RectD(0.9, 0, 0.2, 0.3)));
        AssertInvalid(
            "band bounds must not exceed 1",
            WithFirstBand(new RectD(0.2, 0.9, 0.2, 0.2)));
    }

    private static ScreenFixConfig ValidConfiguration() => DefaultConfiguration.Create(
        new DisplayIdentity("display-1", "Ultrawide", 3440, 1440));

    private static ScreenFixConfig WithFirstBand(RectD band)
    {
        var config = ValidConfiguration();
        RectD[] bands = [band, config.Bands[1], config.Bands[2]];
        return config with { Bands = bands };
    }

    private static void AssertInvalid(string error, ScreenFixConfig? config)
    {
        var result = ConfigValidator.Validate(config);

        Assert.False(result.IsValid);
        Assert.Equal(error, result.Error);
    }
}
