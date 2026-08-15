using ScreenFix.Core.Geometry;

namespace ScreenFix.Core.Guard;

public sealed record WindowFacts(
    long Key,
    RectD VisibleFrame,
    bool IsVisible,
    bool IsMinimized,
    bool IsRootTopLevel,
    bool IsOwned,
    bool IsScreenFixOwned,
    bool IsPlatformOwned,
    bool IsToolOrMenu,
    bool IsMovable,
    bool IsBorderlessFullScreen,
    bool IsOnSelectedDisplay);
