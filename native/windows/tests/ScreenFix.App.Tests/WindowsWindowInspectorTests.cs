using ScreenFix.App.Guard;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Tests;

public sealed class WindowsWindowInspectorTests
{
    [Fact]
    public void TryInspect_MapsOrdinaryWindowAndDwmFrameOffsets()
    {
        var query = new FakeWindowNativeQuery
        {
            IsZoomedResult = true,
            Styles = new WindowStyleData(
                (long)(NativeWindowStyle.Caption | NativeWindowStyle.ThickFrame),
                0),
            ProcessId = 200,
            Root = new nint(17),
            OuterFrame = new RectD(90, 80, 420, 340),
            ExtendedFrame = new RectD(100, 100, 400, 300),
            Monitor = new nint(77),
        };
        var inspector = new WindowsWindowInspector(query, screenFixProcessId: 100);

        var result = inspector.TryInspect(
            Identity(query),
            new SelectedMonitor(
                new nint(77),
                new RectD(0, 0, 1920, 1080),
                new RectD(0, 0, 1920, 1040)));

        var inspection = Assert.IsType<WindowInspection>(result);
        Assert.Equal(new RectD(90, 80, 420, 340), inspection.OuterFrame);
        Assert.Equal(new RectD(100, 100, 400, 300), inspection.Facts.VisibleFrame);
        Assert.Equal(new WindowFrameOffsets(10, 20, 10, 20), inspection.FrameOffsets);
        Assert.True(inspection.IsZoomed);
        Assert.Equal(17, inspection.Facts.Key);
        Assert.True(inspection.Facts.IsVisible);
        Assert.False(inspection.Facts.IsMinimized);
        Assert.True(inspection.Facts.IsRootTopLevel);
        Assert.False(inspection.Facts.IsOwned);
        Assert.False(inspection.Facts.IsScreenFixOwned);
        Assert.False(inspection.Facts.IsPlatformOwned);
        Assert.False(inspection.Facts.IsToolOrMenu);
        Assert.True(inspection.Facts.IsMovable);
        Assert.False(inspection.Facts.IsBorderlessFullScreen);
        Assert.True(inspection.Facts.IsOnSelectedDisplay);
    }

    [Fact]
    public void TryInspect_MapsHiddenAndMinimizedState()
    {
        var query = OrdinaryQuery() with
        {
            IsVisibleResult = false,
            IsIconicResult = true,
        };

        var inspection = Inspect(query);

        Assert.False(inspection.Facts.IsVisible);
        Assert.True(inspection.Facts.IsMinimized);
    }

    [Fact]
    public void TryInspect_MapsNonRootAndOwnedState()
    {
        var query = OrdinaryQuery() with
        {
            Root = new nint(99),
            Owner = new nint(42),
        };

        var inspection = Inspect(query);

        Assert.False(inspection.Facts.IsRootTopLevel);
        Assert.True(inspection.Facts.IsOwned);
    }

    [Fact]
    public void TryInspect_MapsScreenFixProcessOwnership()
    {
        var query = OrdinaryQuery() with { ProcessId = 100 };

        var inspection = Inspect(query);

        Assert.True(inspection.Facts.IsScreenFixOwned);
    }

    [Theory]
    [InlineData(true, false, false)]
    [InlineData(false, true, false)]
    [InlineData(false, false, true)]
    public void TryInspect_ClassifiesToolMenuAndPopupOnlyStyles(
        bool toolStyle,
        bool menuClass,
        bool popupOnly)
    {
        var query = OrdinaryQuery() with
        {
            Styles = new WindowStyleData(
                popupOnly ? (long)NativeWindowStyle.Popup : (long)NativeWindowStyle.Caption,
                toolStyle ? (long)NativeWindowExtendedStyle.ToolWindow : 0),
            ClassName = menuClass ? "#32768" : "OrdinaryWindow",
        };

        var inspection = Inspect(query);

        Assert.True(inspection.Facts.IsToolOrMenu);
    }

    [Fact]
    public void TryInspect_RequiresCaptionOrThickFrameForMovableWindow()
    {
        var query = OrdinaryQuery() with { Styles = new WindowStyleData(0, 0) };

        var inspection = Inspect(query);

        Assert.False(inspection.Facts.IsMovable);
    }

    [Fact]
    public void TryInspect_MapsDocumentedShellHandleAsPlatformOwned()
    {
        var query = OrdinaryQuery() with { ShellWindow = new nint(17) };

        var inspection = Inspect(query);

        Assert.True(inspection.Facts.IsPlatformOwned);
    }

    [Fact]
    public void TryInspect_MapsDifferentMonitorAsOutsideSelection()
    {
        var query = OrdinaryQuery() with { Monitor = new nint(88) };

        var inspection = Inspect(query);

        Assert.False(inspection.Facts.IsOnSelectedDisplay);
    }

    [Fact]
    public void TryInspect_ClassifiesOnlyUnframedFullBoundsAsBorderlessFullScreen()
    {
        var fullBounds = new RectD(0, 0, 1920, 1080);
        var borderless = OrdinaryQuery() with
        {
            Styles = new WindowStyleData(0, 0),
            OuterFrame = new RectD(1, -1, 1920, 1080),
            ExtendedFrame = new RectD(1, -1, 1920, 1080),
        };
        var maximizedOrdinary = borderless with
        {
            Styles = new WindowStyleData((long)NativeWindowStyle.Caption, 0),
        };

        var borderlessInspection = Inspect(borderless, fullBounds);
        var ordinaryInspection = Inspect(maximizedOrdinary, fullBounds);

        Assert.True(borderlessInspection.Facts.IsBorderlessFullScreen);
        Assert.False(ordinaryInspection.Facts.IsBorderlessFullScreen);
        Assert.True(ordinaryInspection.Facts.IsMovable);
    }

    [Fact]
    public void TryInspect_DwmFailureFallsBackToOuterFrameAndZeroOffsets()
    {
        var query = OrdinaryQuery() with { ExtendedFrameSucceeds = false };

        var inspection = Inspect(query);

        Assert.Equal(query.OuterFrame, inspection.Facts.VisibleFrame);
        Assert.Equal(new WindowFrameOffsets(0, 0, 0, 0), inspection.FrameOffsets);
    }

    [Fact]
    public void TryInspect_NativeFailureReturnsNoPartialFacts()
    {
        var query = OrdinaryQuery() with { StylesSucceed = false };
        var inspector = new WindowsWindowInspector(query, screenFixProcessId: 100);

        var result = inspector.TryInspect(Identity(query), Selected());

        Assert.Null(result);
    }

    [Fact]
    public void TryInspect_OwnerQueryFailureReturnsNoPartialFacts()
    {
        var query = OrdinaryQuery() with { OwnerSucceeds = false };
        var inspector = new WindowsWindowInspector(query, screenFixProcessId: 100);

        var result = inspector.TryInspect(Identity(query), Selected());

        Assert.Null(result);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void TryInspect_RejectsRecycledIdentityBeforeReadingWindowFacts(
        bool changeProcess)
    {
        var query = OrdinaryQuery();
        var identity = Identity(query);
        if (changeProcess)
        {
            query.ProcessId++;
        }
        else
        {
            query.ThreadId++;
        }

        var result = new WindowsWindowInspector(query, screenFixProcessId: 100)
            .TryInspect(identity, Selected());

        Assert.Null(result);
    }

    private static WindowInspection Inspect(
        FakeWindowNativeQuery query,
        RectD? fullBounds = null)
    {
        var inspector = new WindowsWindowInspector(query, screenFixProcessId: 100);
        return Assert.IsType<WindowInspection>(inspector.TryInspect(
            Identity(query),
            Selected(fullBounds)));
    }

    private static WindowIdentity Identity(
        FakeWindowNativeQuery query,
        long incarnation = 17) => new(
            new nint(17),
            query.ProcessId,
            query.ThreadId,
            incarnation);

    private static SelectedMonitor Selected(RectD? fullBounds = null) => new(
        new nint(77),
        fullBounds ?? new RectD(0, 0, 1920, 1080),
        new RectD(0, 0, 1920, 1040));

    private static FakeWindowNativeQuery OrdinaryQuery() => new()
    {
        Styles = new WindowStyleData(
            (long)(NativeWindowStyle.Caption | NativeWindowStyle.ThickFrame),
            0),
        ProcessId = 200,
        Root = new nint(17),
        OuterFrame = new RectD(90, 80, 420, 340),
        ExtendedFrame = new RectD(100, 100, 400, 300),
        Monitor = new nint(77),
    };

    private sealed record FakeWindowNativeQuery : IWindowNativeQuery
    {
        public bool IsWindowResult { get; set; } = true;

        public bool IsVisibleResult { get; set; } = true;

        public bool IsIconicResult { get; set; }

        public bool IsZoomedResult { get; set; }

        public WindowStyleData Styles { get; set; }

        public bool StylesSucceed { get; set; } = true;

        public uint ProcessId { get; set; }

        public uint ThreadId { get; set; } = 300;

        public bool ProcessIdSucceeds { get; set; } = true;

        public nint Root { get; set; }

        public bool RootSucceeds { get; set; } = true;

        public nint Owner { get; set; }

        public bool OwnerSucceeds { get; set; } = true;

        public nint ShellWindow { get; set; } = new(1);

        public nint DesktopWindow { get; set; } = new(2);

        public string ClassName { get; set; } = "OrdinaryWindow";

        public bool ClassNameSucceeds { get; set; } = true;

        public RectD OuterFrame { get; set; }

        public bool OuterFrameSucceeds { get; set; } = true;

        public RectD ExtendedFrame { get; set; }

        public bool ExtendedFrameSucceeds { get; set; } = true;

        public nint Monitor { get; set; }

        public bool IsWindow(nint window) => IsWindowResult;

        public bool IsWindowVisible(nint window) => IsVisibleResult;

        public bool IsIconic(nint window) => IsIconicResult;

        public bool IsZoomed(nint window) => IsZoomedResult;

        public bool TryGetStyles(nint window, out WindowStyleData styles)
        {
            styles = Styles;
            return StylesSucceed;
        }

        public bool TryGetThreadProcessId(
            nint window,
            out uint threadId,
            out uint processId)
        {
            threadId = ThreadId;
            processId = ProcessId;
            return ProcessIdSucceeds;
        }

        public bool TryGetRoot(nint window, out nint root)
        {
            root = Root;
            return RootSucceeds;
        }

        public bool TryGetOwner(nint window, out nint owner)
        {
            owner = Owner;
            return OwnerSucceeds;
        }

        public nint GetShellWindow() => ShellWindow;

        public nint GetDesktopWindow() => DesktopWindow;

        public bool TryGetClassName(nint window, out string className)
        {
            className = ClassName;
            return ClassNameSucceeds;
        }

        public bool TryGetOuterFrame(nint window, out RectD frame)
        {
            frame = OuterFrame;
            return OuterFrameSucceeds;
        }

        public bool TryGetExtendedFrame(nint window, out RectD frame)
        {
            frame = ExtendedFrame;
            return ExtendedFrameSucceeds;
        }

        public nint MonitorFromFrame(RectD frame) => Monitor;
    }
}
