using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Guard;

public static class WindowEligibility
{
    public static bool IsEligible(
        WindowFacts facts,
        IReadOnlyList<RectD> maskBands) =>
        facts.IsVisible &&
        !facts.IsMinimized &&
        facts.IsRootTopLevel &&
        !facts.IsOwned &&
        !facts.IsScreenFixOwned &&
        !facts.IsPlatformOwned &&
        !facts.IsToolOrMenu &&
        facts.IsMovable &&
        !facts.IsBorderlessFullScreen &&
        facts.IsOnSelectedDisplay &&
        IsValid(facts.VisibleFrame) &&
        maskBands.Any(mask => IsValid(mask) && facts.VisibleFrame.Intersects(mask));

    private static bool IsValid(RectD rectangle) =>
        double.IsFinite(rectangle.X) &&
        double.IsFinite(rectangle.Y) &&
        double.IsFinite(rectangle.Width) &&
        double.IsFinite(rectangle.Height) &&
        double.IsFinite(rectangle.Right) &&
        double.IsFinite(rectangle.Bottom) &&
        rectangle.Width > 0 &&
        rectangle.Height > 0;
}
