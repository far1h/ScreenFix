using System.Text.Json.Serialization;

namespace ScreenFix.Core.Geometry;

public readonly record struct RectD(
    [property: JsonRequired, JsonPropertyName("x")] double X,
    [property: JsonRequired, JsonPropertyName("y")] double Y,
    [property: JsonRequired, JsonPropertyName("w")] double Width,
    [property: JsonRequired, JsonPropertyName("h")] double Height)
{
    [JsonIgnore]
    public double Right => X + Width;

    [JsonIgnore]
    public double Bottom => Y + Height;

    public bool Intersects(RectD other) =>
        X < other.Right && other.X < Right && Y < other.Bottom && other.Y < Bottom;

    public RectD ToAbsolute(RectD fullFrame) => new(
        fullFrame.X + (X * fullFrame.Width),
        fullFrame.Y + (Y * fullFrame.Height),
        Width * fullFrame.Width,
        Height * fullFrame.Height);
}
