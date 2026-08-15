using ScreenFix.Core.Geometry;
using ScreenFix.Core.Guard;

namespace ScreenFix.Core.Tests;

public sealed class GuardMemoryTests
{
    [Fact]
    public void ShouldSuppressRecent_SuppressesNearTargetBeforeExpiry()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(17, target, now);

        var result = memory.ShouldSuppressRecent(
            17,
            new RectD(99, 201, 301, 398),
            now.AddMilliseconds(249));

        Assert.True(result);
    }

    [Fact]
    public void ShouldSuppressRecent_NonNearEventClearsTarget()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(17, target, now);

        Assert.False(memory.ShouldSuppressRecent(
            17,
            target with { X = 102 },
            now.AddMilliseconds(100)));
        Assert.False(memory.ShouldSuppressRecent(
            17,
            target,
            now.AddMilliseconds(101)));
    }

    [Fact]
    public void ShouldSuppressRecent_ExpiresAtExactly250Milliseconds()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(17, target, now);

        var result = memory.ShouldSuppressRecent(
            17,
            target,
            now.AddMilliseconds(250));

        Assert.False(result);
    }

    [Fact]
    public void IsRefused_BlocksBeforeOneSecondAndExpiresAtOneSecond()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        memory.RecordRefusal(17, now);

        Assert.True(memory.IsRefused(17, now.AddMilliseconds(999)));
        Assert.False(memory.IsRefused(17, now.AddSeconds(1)));
    }

    [Fact]
    public void Forget_RemovesSuccessAndRefusalForOnlyOneKey()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(17, target, now);
        memory.RecordRefusal(17, now);
        memory.RecordSuccess(23, target, now);
        memory.RecordRefusal(23, now);

        memory.Forget(17);

        Assert.False(memory.ShouldSuppressRecent(17, target, now));
        Assert.False(memory.IsRefused(17, now));
        Assert.True(memory.ShouldSuppressRecent(23, target, now));
        Assert.True(memory.IsRefused(23, now));
    }

    [Fact]
    public void Clear_RemovesAllState()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(17, target, now);
        memory.RecordRefusal(23, now);

        memory.Clear();

        Assert.False(memory.ShouldSuppressRecent(17, target, now));
        Assert.False(memory.IsRefused(23, now));
    }

    [Fact]
    public void Prune_RemovesExpiredEntriesWithoutChangingLiveEntries()
    {
        var memory = new GuardMemory();
        var now = DateTimeOffset.UnixEpoch;
        var target = new RectD(100, 200, 300, 400);
        memory.RecordSuccess(11, target, now);
        memory.RecordSuccess(12, target, now.AddMilliseconds(400));
        memory.RecordRefusal(21, now.AddMilliseconds(-600));
        memory.RecordRefusal(22, now.AddMilliseconds(400));

        memory.Prune(now.AddMilliseconds(500));

        Assert.False(memory.ShouldSuppressRecent(11, target, now.AddMilliseconds(500)));
        Assert.True(memory.ShouldSuppressRecent(12, target, now.AddMilliseconds(500)));
        Assert.False(memory.IsRefused(21, now.AddMilliseconds(500)));
        Assert.True(memory.IsRefused(22, now.AddMilliseconds(500)));
    }
}
