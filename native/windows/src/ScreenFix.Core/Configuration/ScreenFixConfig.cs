using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Configuration;

public sealed record DisplayIdentity(string StableId, string Name, double Width, double Height);

public sealed record ScreenFixConfig(
    int SchemaVersion,
    bool Enabled,
    DisplayIdentity Display,
    IReadOnlyList<RectD> Bands);
