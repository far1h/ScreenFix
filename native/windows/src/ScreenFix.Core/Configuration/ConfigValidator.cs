using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Configuration;

public readonly record struct ValidationResult(bool IsValid, string? Error);

public static class ConfigValidator
{
    public static ValidationResult Validate(ScreenFixConfig? value)
    {
        if (value is null)
        {
            return Invalid("configuration is required");
        }

        if (value.SchemaVersion != 1)
        {
            return Invalid("schema version must be 1");
        }

        if (value.Display is null)
        {
            return Invalid("display is required");
        }

        if (string.IsNullOrWhiteSpace(value.Display.StableId))
        {
            return Invalid("display stable ID is required");
        }

        if (string.IsNullOrWhiteSpace(value.Display.Name))
        {
            return Invalid("display name is required");
        }

        if (!IsPositiveFinite(value.Display.Width) || !IsPositiveFinite(value.Display.Height))
        {
            return Invalid("display dimensions must be finite and positive");
        }

        if (value.Bands is null || value.Bands.Count != 3)
        {
            return Invalid("exactly three bands are required");
        }

        foreach (var band in value.Bands)
        {
            var result = ValidateBand(band);
            if (!result.IsValid)
            {
                return result;
            }
        }

        return new ValidationResult(true, null);
    }

    private static ValidationResult ValidateBand(RectD band)
    {
        if (!double.IsFinite(band.X) ||
            !double.IsFinite(band.Y) ||
            !double.IsFinite(band.Width) ||
            !double.IsFinite(band.Height))
        {
            return Invalid("band values must be finite");
        }

        if (band.Width <= 0 || band.Height <= 0)
        {
            return Invalid("band size must be positive");
        }

        if (band.X < 0 || band.Y < 0)
        {
            return Invalid("band origin must be non-negative");
        }

        if (band.Right > 1 || band.Bottom > 1)
        {
            return Invalid("band bounds must not exceed 1");
        }

        return new ValidationResult(true, null);
    }

    private static bool IsPositiveFinite(double value) => double.IsFinite(value) && value > 0;

    private static ValidationResult Invalid(string error) => new(false, error);
}
