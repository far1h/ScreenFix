using ScreenFix.App.Lifecycle;

namespace ScreenFix.App.Tests;

public sealed class LifecycleTests
{
    [Fact]
    public void ApplicationLifetime_CleansEveryResourceInRequiredOrder()
    {
        var calls = new List<string>();
        var lifetime = new ApplicationLifetime();
        lifetime.OwnGate(() => calls.Add("gate"));
        lifetime.OwnTrayIcon(() => calls.Add("icon"));
        lifetime.OwnMenu(() => calls.Add("menu"));
        lifetime.OwnMasks(() => calls.Add("masks"));
        lifetime.OwnEditor(() => calls.Add("editor"));
        lifetime.OwnSystemMessages(() => calls.Add("messages"));
        lifetime.OwnGuard(() => calls.Add("guard"));
        lifetime.OwnControllerCallbacks(() => calls.Add("callbacks"));

        lifetime.Dispose();

        Assert.Equal(
            ["callbacks", "guard", "messages", "editor", "masks", "menu", "icon", "gate"],
            calls);
    }

    [Fact]
    public void ApplicationLifetime_PartialConstructionContinuesAfterFailureExactlyOnce()
    {
        var calls = new List<string>();
        var lifetime = new ApplicationLifetime();
        lifetime.OwnGate(() => calls.Add("gate"));
        lifetime.OwnTrayIcon(() =>
        {
            calls.Add("icon");
            throw new InvalidOperationException("icon failed");
        });
        lifetime.OwnMenu(() => calls.Add("menu"));

        var error = Assert.Throws<AggregateException>(lifetime.Dispose);
        lifetime.Dispose();

        Assert.Equal(["menu", "icon", "gate"], calls);
        Assert.Equal("icon failed", Assert.Single(error.InnerExceptions).Message);
    }

    [Fact]
    public void SingleInstanceGate_FirstAcquisitionSucceedsAndSecondDoesNotBlock()
    {
        var name = "ScreenFix.Tests." + Guid.NewGuid().ToString("N");
        using var first = SingleInstanceGate.TryAcquire(name);

        var second = SingleInstanceGate.TryAcquire(name);

        Assert.NotNull(first);
        Assert.Null(second);
    }

    [Fact]
    public void SingleInstanceGate_DisposeIsIdempotentAndReleasesOwnership()
    {
        var name = "ScreenFix.Tests." + Guid.NewGuid().ToString("N");
        var first = SingleInstanceGate.TryAcquire(name);
        Assert.NotNull(first);

        first.Dispose();
        first.Dispose();
        using var later = SingleInstanceGate.TryAcquire(name);

        Assert.NotNull(later);
    }

    [Fact]
    public void ResourceOwner_CleansUpInReverseOrderExactlyOnce()
    {
        var calls = new List<int>();
        var owner = new ResourceOwner();
        owner.Register(() => calls.Add(1));
        owner.Register(() => calls.Add(2));
        owner.Register(() => calls.Add(3));

        owner.Dispose();
        owner.Dispose();

        Assert.Equal([3, 2, 1], calls);
    }

    [Fact]
    public void ResourceOwner_ContinuesCleanupBeforeSurfacingFailures()
    {
        var calls = new List<int>();
        var owner = new ResourceOwner();
        owner.Register(() => calls.Add(1));
        owner.Register(() =>
        {
            calls.Add(2);
            throw new InvalidOperationException("cleanup failed");
        });
        owner.Register(() => calls.Add(3));

        var error = Assert.Throws<AggregateException>(owner.Dispose);

        Assert.Equal([3, 2, 1], calls);
        Assert.Single(error.InnerExceptions);
        Assert.Equal("cleanup failed", error.InnerExceptions[0].Message);
    }

    [Fact]
    public void ResourceOwner_RejectsNullCleanup()
    {
        var owner = new ResourceOwner();

        Assert.Throws<ArgumentNullException>(() => owner.Register(null!));
    }
}
