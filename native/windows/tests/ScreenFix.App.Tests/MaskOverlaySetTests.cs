using ScreenFix.App.Overlays;
using ScreenFix.Core.Geometry;

namespace ScreenFix.App.Tests;

public sealed class MaskOverlaySetTests
{
    [Fact]
    public void Replace_PreparesAndShowsThreeCandidatesBeforeRetiringOldSurfaces()
    {
        var events = new List<string>();
        var factory = new FakeFactory(events);
        using var overlays = new MaskOverlaySet(factory);

        Assert.True(overlays.Replace(Frames(0)).IsSuccess);
        events.Clear();

        Assert.True(overlays.Replace(Frames(100)).IsSuccess);

        Assert.Equal(
            [
                "create:4", "prepare:4", "create:5", "prepare:5", "create:6", "prepare:6",
                "show:4", "show:5", "show:6", "ready:4", "ready:5", "ready:6",
                "dispose:1", "dispose:2", "dispose:3",
            ],
            events);
    }

    [Theory]
    [InlineData(FailurePoint.Create)]
    [InlineData(FailurePoint.Prepare)]
    [InlineData(FailurePoint.Show)]
    [InlineData(FailurePoint.Ready)]
    public void Replace_FailureDisposesCandidatesAndPreservesCommittedSurfaces(
        FailurePoint failure)
    {
        var events = new List<string>();
        var factory = new FakeFactory(events);
        using var overlays = new MaskOverlaySet(factory);
        Assert.True(overlays.Replace(Frames(0)).IsSuccess);
        events.Clear();
        factory.Failure = failure;
        factory.FailureId = 5;

        var failed = overlays.Replace(Frames(100));

        Assert.False(failed.IsSuccess);
        Assert.DoesNotContain("dispose:1", events);
        Assert.DoesNotContain("dispose:2", events);
        Assert.DoesNotContain("dispose:3", events);
        Assert.Contains("dispose:4", events);

        factory.Failure = FailurePoint.None;
        events.Clear();
        Assert.True(overlays.Replace(Frames(200)).IsSuccess);
        Assert.Contains("dispose:1", events);
        Assert.Contains("dispose:2", events);
        Assert.Contains("dispose:3", events);
    }

    [Fact]
    public void Replace_ValidatesExactlyThreeFramesBeforeAllocating()
    {
        var events = new List<string>();
        using var overlays = new MaskOverlaySet(new FakeFactory(events));

        var result = overlays.Replace([new RectD(0, 0, 10, 10)]);

        Assert.False(result.IsSuccess);
        Assert.Empty(events);
    }

    [Fact]
    public void ClearAndDispose_AreIdempotentAndReplacementAfterDisposeIsRejected()
    {
        var events = new List<string>();
        var overlays = new MaskOverlaySet(new FakeFactory(events));
        Assert.True(overlays.Replace(Frames(0)).IsSuccess);
        events.Clear();

        overlays.Clear();
        overlays.Clear();
        overlays.Dispose();
        overlays.Dispose();
        var result = overlays.Replace(Frames(100));

        Assert.Equal(["dispose:1", "dispose:2", "dispose:3"], events);
        Assert.False(result.IsSuccess);
    }

    private static RectD[] Frames(int offset) =>
    [
        new RectD(offset, 0, 10, 10),
        new RectD(offset, 10, 10, 10),
        new RectD(offset, 20, 10, 10),
    ];

    private sealed class FakeFactory(List<string> events) : IMaskSurfaceFactory
    {
        private int nextId;

        public FailurePoint Failure { get; set; }

        public int FailureId { get; set; }

        public IMaskSurface Create()
        {
            nextId++;
            events.Add($"create:{nextId}");
            ThrowIf(FailurePoint.Create, nextId);
            return new FakeSurface(this, nextId, events);
        }

        public void ThrowIf(FailurePoint point, int id)
        {
            if (Failure == point && FailureId == id)
            {
                throw new InvalidOperationException($"{point} failed");
            }
        }
    }

    private sealed class FakeSurface(FakeFactory factory, int id, List<string> events) : IMaskSurface
    {
        public bool IsReady
        {
            get
            {
                events.Add($"ready:{id}");
                if (factory.Failure == FailurePoint.Ready && factory.FailureId == id)
                {
                    return false;
                }

                return true;
            }
        }

        public void Prepare(RectD nativeBounds)
        {
            events.Add($"prepare:{id}");
            factory.ThrowIf(FailurePoint.Prepare, id);
        }

        public void ShowNoActivate()
        {
            events.Add($"show:{id}");
            factory.ThrowIf(FailurePoint.Show, id);
        }

        public void Dispose() => events.Add($"dispose:{id}");
    }

    public enum FailurePoint
    {
        None,
        Create,
        Prepare,
        Show,
        Ready,
    }
}
