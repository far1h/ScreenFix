using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;

namespace ScreenFix.App.Runtime;

public sealed record RuntimeState(
    ScreenFixConfig? Configuration,
    ConnectedDisplay? ConnectedDisplay,
    bool InvalidConfiguration,
    bool MaskRenderingFailed,
    bool IsEditing,
    bool IsStopped,
    long Generation);
