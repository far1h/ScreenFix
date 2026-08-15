namespace ScreenFix.Core.Geometry;

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;

    public double Bottom => Y + Height;

    public bool Intersects(RectD other) =>
        X < other.Right && other.X < Right && Y < other.Bottom && other.Y < Bottom;

    public RectD ToAbsolute(RectD fullFrame) => new(
        fullFrame.X + (X * fullFrame.Width),
        fullFrame.Y + (Y * fullFrame.Height),
        Width * fullFrame.Width,
        Height * fullFrame.Height);
}
