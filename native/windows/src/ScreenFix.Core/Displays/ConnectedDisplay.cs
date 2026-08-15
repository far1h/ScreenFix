using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Displays;

public sealed record ConnectedDisplay(
    string? StableId,
    string Name,
    int Width,
    int Height,
    RectD FullBounds,
    RectD WorkArea,
    bool SupportsNameFallback = true);
