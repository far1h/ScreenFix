using ScreenFix.App;
using ScreenFix.App.Lifecycle;

namespace ScreenFix.Windows.Tests.Startup;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ProductionMutexCollection
{
    public const string Name = "ScreenFix production mutex";
}

public sealed class MutexObjectLifetimeTests
{
    [Fact]
    public void FinalOwnerDisposalAllowsFreshCreation()
    {
        var name = UniqueName();
        var owner = SingleInstanceGate.TryAcquire(name);
        Assert.NotNull(owner);

        owner.Dispose();
        using var next = SingleInstanceGate.TryAcquire(name);

        Assert.NotNull(next);
    }

    [Fact]
    public void ClosedObserverDoesNotPreventFreshCreation()
    {
        var name = UniqueName();
        var owner = SingleInstanceGate.TryAcquire(name);
        Assert.NotNull(owner);
        Assert.True(Mutex.TryOpenExisting(name, out var observer));

        observer.Dispose();
        owner.Dispose();
        using var next = SingleInstanceGate.TryAcquire(name);

        Assert.NotNull(next);
    }

    [Fact]
    public void OpenObserverKeepsAbandonedObjectFromFreshCreation()
    {
        var name = UniqueName();
        using var ownerReady = new ManualResetEventSlim();
        using var releaseOwnerThread = new ManualResetEventSlim();
        Exception? ownerError = null;
        var ownerThread = new Thread(() =>
        {
            try
            {
                using var owner = new Mutex(initiallyOwned: true, name, out var createdNew);
                Assert.True(createdNew);
                ownerReady.Set();
                releaseOwnerThread.Wait();
            }
            catch (Exception error)
            {
                ownerError = error;
                ownerReady.Set();
            }
        });

        ownerThread.Start();
        try
        {
            Assert.True(ownerReady.Wait(TimeSpan.FromSeconds(10)));
            Assert.Null(ownerError);
            Assert.True(Mutex.TryOpenExisting(name, out var observer));
            using (observer)
            {
                releaseOwnerThread.Set();
                Assert.True(ownerThread.Join(TimeSpan.FromSeconds(10)));
                Assert.Null(ownerError);

                using var refused = SingleInstanceGate.TryAcquire(name);
                Assert.Null(refused);
            }
        }
        finally
        {
            releaseOwnerThread.Set();
            Assert.True(ownerThread.Join(TimeSpan.FromSeconds(10)));
        }
    }

    private static string UniqueName()
    {
        return @"Local\ScreenFix.Tests." + Guid.NewGuid().ToString("N");
    }
}

[Collection(ProductionMutexCollection.Name)]
public sealed class ProductionMutexObjectLifetimeTests
{
    [Fact]
    [Trait("ScreenFixCategory", "DisposableAccount")]
    public void OwnedProductionObjectRefusesAcquisition()
    {
        using var existing = new Mutex(
            initiallyOwned: true,
            ScreenFixApplicationIdentity.SingleInstanceMutexName,
            out var createdNew);
        Assert.True(createdNew);
        try
        {
            using var refused = ScreenFixApplicationIdentity.TryAcquire();

            Assert.Null(refused);
        }
        finally
        {
            existing.ReleaseMutex();
        }
    }

    [Fact]
    [Trait("ScreenFixCategory", "DisposableAccount")]
    public void UnownedProductionObjectRefusesAcquisition()
    {
        using var existing = new Mutex(
            initiallyOwned: false,
            ScreenFixApplicationIdentity.SingleInstanceMutexName,
            out var createdNew);
        Assert.True(createdNew);

        using var refused = ScreenFixApplicationIdentity.TryAcquire();

        Assert.Null(refused);
    }
}
