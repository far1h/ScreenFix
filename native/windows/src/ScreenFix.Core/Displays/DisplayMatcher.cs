using ScreenFix.Core.Configuration;

namespace ScreenFix.Core.Displays;

public static class DisplayMatcher
{
    public static ConnectedDisplay? Find(
        DisplayIdentity saved,
        IReadOnlyList<ConnectedDisplay> connected)
    {
        ArgumentNullException.ThrowIfNull(saved);
        ArgumentNullException.ThrowIfNull(connected);

        var stableMatches = connected.Where(display =>
            !string.IsNullOrWhiteSpace(display.StableId) &&
            StringComparer.OrdinalIgnoreCase.Equals(display.StableId, saved.StableId)).ToArray();
        if (stableMatches.Length > 0)
        {
            return stableMatches.Length == 1 ? stableMatches[0] : null;
        }

        var fallbackMatches = connected.Where(display =>
            display.SupportsNameFallback &&
            StringComparer.Ordinal.Equals(display.Name, saved.Name) &&
            display.Width == saved.Width &&
            display.Height == saved.Height).ToArray();
        return fallbackMatches.Length == 1 ? fallbackMatches[0] : null;
    }
}
