using System.Text.Json.Serialization;
using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Configuration;

public sealed record DisplayIdentity(
    [property: JsonRequired, JsonPropertyName("stableId")] string StableId,
    [property: JsonRequired, JsonPropertyName("name")] string Name,
    [property: JsonRequired, JsonPropertyName("width")] double Width,
    [property: JsonRequired, JsonPropertyName("height")] double Height);

public sealed record ScreenFixConfig(
    [property: JsonRequired, JsonPropertyName("schemaVersion")] int SchemaVersion,
    [property: JsonRequired, JsonPropertyName("enabled")] bool Enabled,
    [property: JsonRequired, JsonPropertyName("display")] DisplayIdentity Display,
    [property: JsonRequired, JsonPropertyName("bands")] IReadOnlyList<RectD> Bands);
