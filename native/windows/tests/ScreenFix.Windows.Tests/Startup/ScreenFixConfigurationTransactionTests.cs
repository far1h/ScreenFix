using ScreenFix.App;

namespace ScreenFix.Windows.Tests.Startup;

public sealed class ScreenFixConfigurationTransactionTests
{
    [Fact]
    public void ProcessStartInfoOverridesExtractionOnlyForTheChild()
    {
        const string variable = "DOTNET_BUNDLE_EXTRACT_BASE_DIR";
        var original = Environment.GetEnvironmentVariable(variable);
        var inheritedName = "SCREENFIX_STARTUP_INHERITED_" + Guid.NewGuid().ToString("N");
        var inheritedOriginal = Environment.GetEnvironmentVariable(inheritedName);
        var childExtraction = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        try
        {
            Environment.SetEnvironmentVariable(variable, "parent-extraction");
            Environment.SetEnvironmentVariable(inheritedName, "inherited-value");

            var startInfo = SystemConfigurationProcessFactory.CreateStartInfo(
                new ConfigurationLaunchRequest(
                    Path.Combine(Path.GetTempPath(), "ScreenFix.exe"),
                    childExtraction));

            Assert.Equal(childExtraction, startInfo.Environment[variable]);
            Assert.Equal("inherited-value", startInfo.Environment[inheritedName]);
            Assert.Equal("parent-extraction", Environment.GetEnvironmentVariable(variable));
        }
        finally
        {
            Environment.SetEnvironmentVariable(variable, original);
            Environment.SetEnvironmentVariable(inheritedName, inheritedOriginal);
        }
    }

    [Fact]
    public void TypedLaunchReturnsTheMeasuredInputIdleEndpoint()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Process.StartAction = () =>
            fixture.Clock.Advance(TimeSpan.FromMilliseconds(321));
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        var request = new ConfigurationLaunchRequest(fixture.Executable, fixture.Root);

        var elapsed = transaction.RunLaunch(request, TimeSpan.FromSeconds(10));

        Assert.Equal(TimeSpan.FromMilliseconds(321), elapsed);
        Assert.True(transaction.CanCleanExternalState);
    }

    [Fact]
    public void CumulativeDeadlineLimitsInputIdleToTimeRemainingAfterMutexObservation()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.WaitAction = _ => fixture.Clock.Advance(TimeSpan.FromSeconds(6));
        fixture.Process.InputIdleAction = () =>
            fixture.Clock.Advance(fixture.Process.LastInputIdleTimeout!.Value);
        fixture.Process.InputIdleResult = false;
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Contains("input-idle", error.Message);
        Assert.Equal(TimeSpan.FromSeconds(10), fixture.Observer.LastTimeout);
        Assert.Equal(TimeSpan.FromSeconds(4), fixture.Process.LastInputIdleTimeout);
        Assert.Equal(TimeSpan.FromSeconds(10), fixture.Clock.Elapsed);
    }

    [Fact]
    public void ProcessStartTimeReducesTheMutexObservationBudget()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Process.StartAction = () => fixture.Clock.Advance(TimeSpan.FromSeconds(2));
        fixture.Observer.Result = false;
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Equal(TimeSpan.FromSeconds(8), fixture.Observer.LastTimeout);
    }

    [Fact]
    public void ProcessStartAtDeadlineDoesNotPassZeroToMutexObservation()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Process.StartAction = () => fixture.Clock.Advance(TimeSpan.FromSeconds(10));
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Contains("before mutex observation", error.Message);
        Assert.Null(fixture.Observer.LastTimeout);
    }

    [Fact]
    public void MutexObservationAtDeadlineDoesNotPassZeroToInputIdle()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.WaitAction = _ => fixture.Clock.Advance(TimeSpan.FromSeconds(10));
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Contains("before input-idle", error.Message);
        Assert.Equal(TimeSpan.FromSeconds(10), fixture.Observer.LastTimeout);
        Assert.Null(fixture.Process.LastInputIdleTimeout);
    }

    [Fact]
    public void CumulativeDeadlineRejectsInputIdleAtTheExactRemainingBoundary()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.WaitAction = _ => fixture.Clock.Advance(TimeSpan.FromSeconds(9));
        fixture.Process.InputIdleAction = () => fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Contains("cumulative startup deadline", error.Message);
        Assert.Equal(TimeSpan.FromSeconds(1), fixture.Process.LastInputIdleTimeout);
    }

    [Fact]
    public void InputIdleEndpointBeyondTheCumulativeDeadlineFails()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.WaitAction = _ => fixture.Clock.Advance(TimeSpan.FromSeconds(9));
        fixture.Process.InputIdleAction = () =>
            fixture.Clock.Advance(TimeSpan.FromMilliseconds(1_001));
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Contains("cumulative startup deadline", error.Message);
        Assert.Equal(TimeSpan.FromSeconds(1), fixture.Process.LastInputIdleTimeout);
    }

    [Fact]
    public void ConstructorRefusesWithoutExplicitOptInBeforeGateOrFilesystem()
    {
        using var fixture = ConfigurationFixture.Create();

        var error = Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(
                allowDisposableAccountMutation: false,
                fixture.Dependencies));

        Assert.Contains("explicit disposable-account opt-in", error.Message);
        Assert.Equal(0, fixture.GateAcquireCount);
        Assert.Equal(0, fixture.FileSystem.OperationCount);
    }

    [Fact]
    public void ConstructorRefusesExistingObjectBeforeFilesystemMutation()
    {
        using var fixture = ConfigurationFixture.Create(gateAvailable: false);
        var original = new byte[] { 1, 2, 3, 4 };
        fixture.CreateConfiguration(original);

        var error = Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(
                allowDisposableAccountMutation: true,
                fixture.Dependencies));

        Assert.Contains("fresh production mutex", error.Message);
        Assert.Equal(0, fixture.FileSystem.OperationCount);
        Assert.Equal(original, File.ReadAllBytes(fixture.ConfigFile));
        Assert.Empty(Directory.GetDirectories(fixture.LocalAppData, "ScreenFix.backup-*"));
    }

    [Fact]
    public void ConstructorRejectsConfigDirectoryEqualToLocalAppDataRoot()
    {
        using var fixture = ConfigurationFixture.Create(configDirectoryAtRoot: true);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void ConstructorRejectsConfigDirectoryOutsideLocalAppData()
    {
        using var fixture = ConfigurationFixture.Create(configDirectoryOutsideRoot: true);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void ConstructorRejectsReparseConfigDirectory()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([7]);
        fixture.FileSystem.ReparsePaths.Add(fixture.ConfigDirectory);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void ConstructorRejectsBrokenReparseConfigDirectory()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.FileSystem.ReparsePaths.Add(fixture.ConfigDirectory);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void ConstructorRejectsReparseAncestor()
    {
        using var fixture = ConfigurationFixture.Create(nestedConfigDirectory: true);
        fixture.CreateConfiguration([7]);
        var ancestor = Directory.GetParent(fixture.ConfigDirectory)!.FullName;
        fixture.FileSystem.ReparsePaths.Add(ancestor);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void ConstructorRejectsReparseAncestorAboveLocalAppData()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([7]);
        fixture.FileSystem.ReparsePaths.Add(fixture.Root);

        Assert.Throws<InvalidOperationException>(() =>
            new ScreenFixConfigurationTransaction(true, fixture.Dependencies));

        Assert.Equal(0, fixture.FileSystem.MoveCount);
    }

    [Fact]
    public void MissingConfigurationLeavesNoTestOrBackupDirectory()
    {
        using var fixture = ConfigurationFixture.Create();

        using (var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies))
        {
            Assert.False(Directory.Exists(fixture.ConfigDirectory));
            Assert.False(Directory.Exists(transaction.BackupDirectory));
        }

        Assert.False(Directory.Exists(fixture.ConfigDirectory));
        Assert.Empty(Directory.GetDirectories(fixture.LocalAppData, "ScreenFix.backup-*"));
    }

    [Fact]
    public void ExistingConfigurationIsRestoredByteForByte()
    {
        using var fixture = ConfigurationFixture.Create();
        var original = Enumerable.Range(0, 256).Select(value => (byte)value).ToArray();
        fixture.CreateConfiguration(original);
        string backup;

        using (var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies))
        {
            backup = transaction.BackupDirectory;
            Assert.False(Directory.Exists(fixture.ConfigDirectory));
            Assert.True(Directory.Exists(backup));
            fixture.CreateConfiguration([99]);
        }

        Assert.Equal(original, File.ReadAllBytes(fixture.ConfigFile));
        Assert.False(Directory.Exists(backup));
    }

    [Fact]
    public void SuccessfulLaunchDisposesGateBeforeStartAndCleansPerLaunchConfiguration()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Process.StartAction = () => fixture.CreateConfiguration([42]);
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10));

        Assert.False(Directory.Exists(fixture.ConfigDirectory));
        AssertOrdered(
            fixture.Events,
            "dispose-gate",
            "start-child",
            "observe-mutex",
            "wait-input-idle",
            "kill-child",
            "wait-exit",
            "dispose-child",
            "acquire-gate",
            "delete-directory");
    }

    [Fact]
    public void RepeatedLaunchesCleanConfigurationBeforeTheNextChildStarts()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Process.StartAction = () =>
        {
            fixture.Process.HasExitedValue = false;
            fixture.CreateConfiguration([42]);
        };
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10));
        transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10));

        Assert.Equal(2, fixture.Events.Count(item => item == "start-child"));
        Assert.Equal(2, fixture.Events.Count(item => item == "delete-directory"));
        Assert.False(Directory.Exists(fixture.ConfigDirectory));
    }

    [Fact]
    public void ChildExitBeforeMutexIsTerminatedBeforeCleanupAndRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () =>
        {
            fixture.CreateConfiguration([2]);
            fixture.Process.HasExitedValue = true;
        };
        fixture.Observer.Result = false;
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Contains("before creating the production mutex", error.Message);
        AssertOrdered(fixture.Events, "wait-exit", "acquire-gate", "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
    }

    [Fact]
    public void StillRunningChildWithoutMutexIsKilledAndWaitedBeforeCleanupAndRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Observer.Result = false;
        var timeout = TimeSpan.FromSeconds(10);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, timeout));
        transaction.Dispose();

        Assert.Contains("before creating the production mutex", error.Message);
        Assert.Equal(timeout, fixture.Observer.LastTimeout);
        Assert.Equal(timeout, fixture.Process.LastExitTimeout);
        AssertOrdered(
            fixture.Events,
            "observe-mutex",
            "kill-child",
            "wait-exit",
            "dispose-child",
            "acquire-gate",
            "delete-directory",
            "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
    }

    [Fact]
    public void InputIdleTimeoutTerminatesChildBeforeCleanupAndRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Process.InputIdleResult = false;
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<TimeoutException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Contains("input-idle", error.Message);
        AssertOrdered(
            fixture.Events,
            "observe-mutex",
            "wait-input-idle",
            "kill-child",
            "wait-exit",
            "acquire-gate",
            "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
    }

    [Fact]
    public void ObserverFailureTerminatesChildBeforeRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Observer.Error = new InvalidOperationException("observer failed");
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        Assert.True(transaction.CanCleanExternalState);
        transaction.Dispose();

        Assert.Equal("observer failed", error.Message);
        AssertOrdered(fixture.Events, "observe-mutex", "kill-child", "wait-exit", "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
    }

    [Fact]
    public void ChildDisposalFailureIsCombinedWithThePriorObserverFailure()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.Error = new InvalidOperationException("observer failed");
        fixture.Process.DisposeError = new IOException("dispose failed");
        using var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<AggregateException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));

        Assert.Collection(
            error.InnerExceptions,
            item => Assert.Equal("observer failed", item.Message),
            item => Assert.Equal("dispose failed", item.Message));
        AssertOrdered(fixture.Events, "observe-mutex", "wait-exit", "dispose-child", "acquire-gate");
    }

    [Fact]
    public void ExitBeforeInputIdleIsTerminatedBeforeRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Process.InputIdleAction = () => fixture.Process.HasExitedValue = true;
        fixture.Process.InputIdleResult = false;
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        AssertOrdered(fixture.Events, "wait-input-idle", "wait-exit", "acquire-gate", "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
    }

    [Fact]
    public void LeakedObserverPreservesOriginalAndTestPathsWhenFreshCreationFails()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        fixture.RefuseNextGate = true;

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        Assert.False(transaction.CanCleanExternalState);
        transaction.Dispose();

        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal([1], File.ReadAllBytes(Path.Combine(transaction.BackupDirectory, "config.json")));
        Assert.DoesNotContain("delete-directory", fixture.Events);
        Assert.DoesNotContain("restore-directory", fixture.Events);
    }

    [Fact]
    public void ThrowingGateFactoryPreservesBothPathsAndWrapsTheFailure()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        fixture.GateAcquireError = new InvalidOperationException("gate factory failed");

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        Assert.False(transaction.CanCleanExternalState);
        transaction.Dispose();

        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.Equal("gate factory failed", error.InnerException?.Message);
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal([1], File.ReadAllBytes(Path.Combine(transaction.BackupDirectory, "config.json")));
        Assert.DoesNotContain("delete-directory", fixture.Events);
        Assert.DoesNotContain("restore-directory", fixture.Events);
    }

    [Fact]
    public void TerminationFailurePreservesBothPathsWithoutReacquiringGate()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Process.WaitForExitResult = false;
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        var acquisitionsBeforeLaunch = fixture.GateAcquireCount;

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        Assert.False(transaction.CanCleanExternalState);
        transaction.Dispose();

        Assert.Contains("termination could not be proven", error.Message);
        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.Equal(acquisitionsBeforeLaunch, fixture.GateAcquireCount);
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal([1], File.ReadAllBytes(Path.Combine(transaction.BackupDirectory, "config.json")));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void TerminationExceptionIsRetainedInRecoveryDiagnostic(bool failKill)
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        var expected = failKill ? "kill failed" : "wait failed";
        if (failKill)
        {
            fixture.Process.KillError = new InvalidOperationException(expected);
            fixture.Process.WaitForExitResult = false;
        }
        else
        {
            fixture.Process.WaitForExitError = new InvalidOperationException(expected);
        }

        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        var error = Assert.Throws<InvalidOperationException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Contains("termination could not be proven", error.Message);
        Assert.Contains(expected, error.ToString());
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal([1], File.ReadAllBytes(Path.Combine(transaction.BackupDirectory, "config.json")));
    }

    [Fact]
    public void CleanupFailureIsRetriedBeforeOriginalRestore()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.FileSystem.DeleteFailuresRemaining = 1;
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);

        Assert.Throws<IOException>(() =>
            transaction.RunLaunch(fixture.Request, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Empty(Directory.GetDirectories(fixture.LocalAppData, "ScreenFix.backup-*"));
    }

    [Fact]
    public void RestoreFailurePreservesBackupAndReportsRecoveryPaths()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        fixture.FileSystem.FailRestore = true;

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.False(Directory.Exists(fixture.ConfigDirectory));
        Assert.Equal([1], File.ReadAllBytes(Path.Combine(transaction.BackupDirectory, "config.json")));
    }

    [Fact]
    public void MissingBackupPreservesCurrentConfigurationBeforeThrowing()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        Directory.Delete(transaction.BackupDirectory, recursive: true);
        fixture.CreateConfiguration([2]);

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.DoesNotContain("delete-directory", fixture.Events);
    }

    [Fact]
    public void ReparseBackupPreservesCurrentAndReplacementBeforeThrowing()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        var transaction = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        Directory.Delete(transaction.BackupDirectory, recursive: true);
        Directory.CreateDirectory(transaction.BackupDirectory);
        var replacementFile = Path.Combine(transaction.BackupDirectory, "replacement.txt");
        File.WriteAllBytes(replacementFile, [9]);
        fixture.FileSystem.ReparsePaths.Add(transaction.BackupDirectory);
        fixture.CreateConfiguration([2]);

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Contains(fixture.ConfigDirectory, error.Message);
        Assert.Contains(transaction.BackupDirectory, error.Message);
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal([9], File.ReadAllBytes(replacementFile));
        Assert.DoesNotContain("delete-directory", fixture.Events);
    }

    [Theory]
    [InlineData("mutex-timeout")]
    [InlineData("observer-error")]
    [InlineData("input-idle-timeout")]
    public void IntegratedProvenLaunchFailureCleansExtractionAfterExitAndRestoresConfiguration(
        string failureMode)
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        switch (failureMode)
        {
            case "mutex-timeout":
                fixture.Observer.Result = false;
                break;
            case "observer-error":
                fixture.Observer.Error = new InvalidOperationException("observer failed");
                break;
            case "input-idle-timeout":
                fixture.Process.InputIdleResult = false;
                break;
        }

        var configuration = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        var backup = configuration.BackupDirectory;
        var extractionFixture = IntegratedExtractionFixture.Create(fixture.Root, fixture.Events);
        var extraction = extractionFixture.CreateTransaction();
        var extractionRoot = extraction.RootPath;
        var extractionPath = extraction.CreateWarmExtractionPath("compressed");
        var coordinator = new StartupLaunchCoordinator(configuration, extraction);

        var failure = Record.Exception(() => coordinator.Run(
            fixture.Executable,
            extractionPath,
            TimeSpan.FromSeconds(10)));
        failure = CompleteIntegratedTransactions(configuration, extraction, failure);

        Assert.NotNull(failure);
        switch (failureMode)
        {
            case "mutex-timeout":
                Assert.Contains("before creating the production mutex", failure.Message);
                break;
            case "observer-error":
                Assert.Equal("observer failed", failure.Message);
                break;
            case "input-idle-timeout":
                Assert.IsType<TimeoutException>(failure);
                Assert.Contains("input-idle", failure.Message);
                Assert.Contains("wait-input-idle", fixture.Events);
                break;
        }

        Assert.False(Directory.Exists(extractionRoot));
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
        Assert.False(Directory.Exists(backup));
        AssertOrdered(
            fixture.Events,
            "observe-mutex",
            "kill-child",
            "wait-exit",
            "dispose-child",
            "acquire-gate",
            "delete-directory",
            "delete-extraction-root",
            "restore-directory");
    }

    [Fact]
    public void IntegratedTerminationFailurePreservesEveryRecoveryPath()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        fixture.Process.WaitForExitResult = false;
        var configuration = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        var extractionFixture = IntegratedExtractionFixture.Create(fixture.Root, fixture.Events);
        var extraction = extractionFixture.CreateTransaction();
        var extractionRoot = extraction.RootPath;
        var extractionPath = extraction.CreateWarmExtractionPath("compressed");
        var coordinator = new StartupLaunchCoordinator(configuration, extraction);

        var failure = Record.Exception(() => coordinator.Run(
            fixture.Executable,
            extractionPath,
            TimeSpan.FromSeconds(10)));
        failure = CompleteIntegratedTransactions(configuration, extraction, failure);

        Assert.NotNull(failure);
        Assert.Contains("termination could not be proven", failure.ToString());
        Assert.Contains(extractionRoot, failure.ToString());
        Assert.Contains(fixture.ConfigDirectory, failure.ToString());
        Assert.Contains(configuration.BackupDirectory, failure.ToString());
        Assert.True(Directory.Exists(extractionRoot));
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal(
            [1],
            File.ReadAllBytes(Path.Combine(configuration.BackupDirectory, "config.json")));
        Assert.DoesNotContain("delete-extraction-root", fixture.Events);
        Assert.DoesNotContain("delete-directory", fixture.Events);
        Assert.DoesNotContain("restore-directory", fixture.Events);
    }

    [Fact]
    public void IntegratedLeakedObserverFreshGateFailurePreservesEveryRecoveryPath()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.CreateConfiguration([1]);
        fixture.Process.StartAction = () => fixture.CreateConfiguration([2]);
        var configuration = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        fixture.RefuseNextGate = true;
        var extractionFixture = IntegratedExtractionFixture.Create(fixture.Root, fixture.Events);
        var extraction = extractionFixture.CreateTransaction();
        var extractionRoot = extraction.RootPath;
        var extractionPath = extraction.CreateWarmExtractionPath("compressed");
        var coordinator = new StartupLaunchCoordinator(configuration, extraction);

        var failure = Record.Exception(() => coordinator.Run(
            fixture.Executable,
            extractionPath,
            TimeSpan.FromSeconds(10)));
        failure = CompleteIntegratedTransactions(configuration, extraction, failure);

        Assert.NotNull(failure);
        Assert.Contains("fresh production mutex", failure.ToString());
        Assert.Contains(extractionRoot, failure.ToString());
        Assert.Contains(fixture.ConfigDirectory, failure.ToString());
        Assert.Contains(configuration.BackupDirectory, failure.ToString());
        Assert.True(Directory.Exists(extractionRoot));
        Assert.Equal([2], File.ReadAllBytes(fixture.ConfigFile));
        Assert.Equal(
            [1],
            File.ReadAllBytes(Path.Combine(configuration.BackupDirectory, "config.json")));
        AssertOrdered(fixture.Events, "wait-exit", "acquire-gate");
        Assert.DoesNotContain("delete-extraction-root", fixture.Events);
        Assert.DoesNotContain("delete-directory", fixture.Events);
        Assert.DoesNotContain("restore-directory", fixture.Events);
    }

    [Fact]
    public void WarmSeedAtCumulativeDeadlineFailsBeforeAnyMeasuredLaunch()
    {
        using var fixture = ConfigurationFixture.Create();
        fixture.Observer.WaitAction = _ => fixture.Clock.Advance(TimeSpan.FromSeconds(9));
        fixture.Process.InputIdleAction = () =>
            fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        var configuration = new ScreenFixConfigurationTransaction(true, fixture.Dependencies);
        var extractionFixture = IntegratedExtractionFixture.Create(fixture.Root, fixture.Events);
        var extraction = extractionFixture.CreateTransaction();
        var coordinator = new StartupLaunchCoordinator(configuration, extraction);

        var failure = Record.Exception(() => StartupMeasurementPlan.MeasureWarm(
            (_, extractionPath) => coordinator.Run(
                fixture.Executable,
                extractionPath,
                TimeSpan.FromSeconds(10)),
            extraction.CreateWarmExtractionPath));
        failure = CompleteIntegratedTransactions(configuration, extraction, failure);

        Assert.NotNull(failure);
        Assert.Contains("cumulative startup deadline", failure.ToString());
        Assert.Equal(1, fixture.Events.Count(item => item == "start-child"));
        Assert.False(Directory.Exists(extraction.RootPath));
    }

    private static Exception? CompleteIntegratedTransactions(
        ScreenFixConfigurationTransaction configuration,
        BundleExtractionTransaction extraction,
        Exception? failure)
    {
        failure = StartupTransactionCleanup.DisposeAndCombine(extraction, failure);
        return StartupTransactionCleanup.DisposeAndCombine(configuration, failure);
    }

    private static void AssertOrdered(IReadOnlyList<string> events, params string[] expected)
    {
        var previous = -1;
        foreach (var item in expected)
        {
            var index = -1;
            for (var candidate = previous + 1; candidate < events.Count; candidate++)
            {
                if (events[candidate] == item)
                {
                    index = candidate;
                    break;
                }
            }

            Assert.True(index > previous, $"Expected '{item}' after index {previous}: {string.Join(", ", events)}");
            previous = index;
        }
    }

    private sealed class ConfigurationFixture : IDisposable
    {
        private readonly Queue<IDisposable?> gates;
        private int gateAcquireCount;

        private ConfigurationFixture(
            string root,
            string localAppData,
            string configDirectory,
            Queue<IDisposable?> gates)
        {
            Root = root;
            LocalAppData = localAppData;
            ConfigDirectory = configDirectory;
            ConfigFile = Path.Combine(configDirectory, "config.json");
            Executable = Path.Combine(root, "ScreenFix.exe");
            File.WriteAllBytes(Executable, [1]);
            this.gates = gates;
            FileSystem = new RecordingFileSystem(Events, ConfigDirectory);
            Process = new FakeProcess(Events);
            Observer = new FakeMutexObserver(Events);
            Clock = new FakeMonotonicClock();
            Dependencies = new ScreenFixConfigurationTransactionDependencies(
                LocalAppData,
                ConfigFile,
                AcquireGate,
                FileSystem,
                new FakeProcessFactory(Process, Events),
                Observer,
                Clock);
        }

        public string Root { get; }

        public string LocalAppData { get; }

        public string ConfigDirectory { get; }

        public string ConfigFile { get; }

        public string Executable { get; }

        public ConfigurationLaunchRequest Request => new(Executable, Root);

        public List<string> Events { get; } = [];

        public int GateAcquireCount => gateAcquireCount;

        public RecordingFileSystem FileSystem { get; }

        public FakeProcess Process { get; }

        public FakeMutexObserver Observer { get; }

        public FakeMonotonicClock Clock { get; }

        public bool RefuseNextGate { get; set; }

        public Exception? GateAcquireError { get; set; }

        public ScreenFixConfigurationTransactionDependencies Dependencies { get; }

        public static ConfigurationFixture Create(
            bool gateAvailable = true,
            bool configDirectoryAtRoot = false,
            bool configDirectoryOutsideRoot = false,
            bool nestedConfigDirectory = false)
        {
            var root = Path.Combine(
                Path.GetTempPath(),
                "ScreenFix.Configuration.Tests",
                Guid.NewGuid().ToString("N"));
            var localAppData = Path.Combine(root, "LocalAppData");
            Directory.CreateDirectory(localAppData);
            var configDirectory = configDirectoryAtRoot
                ? localAppData
                : configDirectoryOutsideRoot
                    ? Path.Combine(root, "Outside", "ScreenFix")
                    : nestedConfigDirectory
                        ? Path.Combine(localAppData, "Nested", "ScreenFix")
                        : Path.Combine(localAppData, "ScreenFix");
            var gates = new Queue<IDisposable?>();
            gates.Enqueue(gateAvailable ? new TrackingGate() : null);
            return new ConfigurationFixture(root, localAppData, configDirectory, gates);
        }

        public void CreateConfiguration(byte[] content)
        {
            Directory.CreateDirectory(ConfigDirectory);
            File.WriteAllBytes(ConfigFile, content);
        }

        public void Dispose()
        {
            Directory.Delete(Root, recursive: true);
        }

        private IDisposable? AcquireGate()
        {
            gateAcquireCount++;
            Events.Add("acquire-gate");
            if (GateAcquireError is not null)
            {
                var error = GateAcquireError;
                GateAcquireError = null;
                throw error;
            }

            if (RefuseNextGate)
            {
                RefuseNextGate = false;
                return null;
            }

            var gate = gates.Count == 0 ? new TrackingGate(Events) : gates.Dequeue();
            return gate is TrackingGate ? new TrackingGate(Events) : gate;
        }
    }

    private sealed class TrackingGate(List<string>? events = null) : IDisposable
    {
        public void Dispose()
        {
            events?.Add("dispose-gate");
        }
    }

    private sealed class IntegratedExtractionFixture
    {
        private IntegratedExtractionFixture(
            string runnerTemp,
            string candidate,
            IntegratedExtractionFileSystem fileSystem)
        {
            RunnerTemp = runnerTemp;
            Candidate = candidate;
            var deletion = new IntegratedDeletionAdapter(fileSystem);
            Dependencies = new BundleExtractionTransactionDependencies(
                fileSystem,
                _ => candidate,
                () => [4, 3, 2, 1],
                deletion);
        }

        public string RunnerTemp { get; }

        public string Candidate { get; }

        public BundleExtractionTransactionDependencies Dependencies { get; }

        public static IntegratedExtractionFixture Create(string root, List<string> events)
        {
            var runnerTemp = Path.Combine(root, "runner-temp");
            Directory.CreateDirectory(runnerTemp);
            return new IntegratedExtractionFixture(
                runnerTemp,
                Path.Combine(runnerTemp, "screenfix-integrated-extraction"),
                new IntegratedExtractionFileSystem(events));
        }

        public BundleExtractionTransaction CreateTransaction() =>
            new(true, RunnerTemp, Dependencies);
    }

    private sealed class IntegratedDeletionAdapter(
        IntegratedExtractionFileSystem fileSystem) : IBundleExtractionDeletionAdapter
    {
        public IBundleExtractionRootAnchor CreateAnchor(string rootPath) =>
            new IntegratedRootAnchor(fileSystem);

        private sealed class IntegratedRootAnchor(
            IntegratedExtractionFileSystem fileSystem) : IBundleExtractionRootAnchor
        {
            private string? ownedPath;

            public void VerifyOwnedPath(string path)
            {
                var normalized = Path.GetFullPath(path);
                ownedPath ??= normalized;
                if (!ownedPath.Equals(normalized, StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException(
                        $"Extraction path does not reference the anchored directory: {path}.");
                }
            }

            public void DeleteOwnedRoot(
                string rootPath,
                Action<string> validateOwnedRoot,
                Action releaseIdentityAnchor)
            {
                var quarantine = rootPath + ".delete-quarantine";
                releaseIdentityAnchor();
                Directory.Move(rootPath, quarantine);
                ownedPath = Path.GetFullPath(quarantine);
                validateOwnedRoot(quarantine);
                fileSystem.DeleteDirectory(quarantine);
            }

            public void Dispose()
            {
            }
        }
    }

    private sealed class IntegratedExtractionFileSystem(
        List<string> events) : IBundleExtractionFileSystem
    {
        public FileAttributes GetAttributes(string path) =>
            File.GetAttributes(path) & ~FileAttributes.ReparsePoint;

        public void CreateDirectory(string path) => Directory.CreateDirectory(path);

        public Stream CreateIdentityFile(string path, byte[] identity)
        {
            using (var writer = new FileStream(
                       path,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None))
            {
                writer.Write(identity);
                writer.Flush(flushToDisk: true);
            }

            return new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete);
        }

        public byte[] ReadIdentityFile(string path)
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            using var content = new MemoryStream();
            stream.CopyTo(content);
            return content.ToArray();
        }

        public IEnumerable<string> EnumerateEntries(string path) =>
            Directory.EnumerateFileSystemEntries(path);

        public void DeleteDirectory(string path)
        {
            events.Add("delete-extraction-root");
            Directory.Delete(path, recursive: true);
        }
    }

    private sealed class RecordingFileSystem : IConfigurationFileSystem
    {
        private readonly List<string> events;
        private readonly string configDirectory;

        public RecordingFileSystem(List<string> events, string configDirectory)
        {
            this.events = events;
            this.configDirectory = Path.GetFullPath(configDirectory);
        }

        public HashSet<string> ReparsePaths { get; } = new(StringComparer.OrdinalIgnoreCase);

        public int OperationCount { get; private set; }

        public int MoveCount { get; private set; }

        public int DeleteFailuresRemaining { get; set; }

        public bool FailRestore { get; set; }

        public bool DirectoryExists(string path)
        {
            OperationCount++;
            return Directory.Exists(path);
        }

        public bool FileExists(string path)
        {
            OperationCount++;
            return File.Exists(path);
        }

        public FileAttributes GetAttributes(string path)
        {
            OperationCount++;
            if (ReparsePaths.Contains(Path.GetFullPath(path)))
            {
                return FileAttributes.Directory | FileAttributes.ReparsePoint;
            }

            var attributes = File.GetAttributes(path);
            return attributes & ~FileAttributes.ReparsePoint;
        }

        public void MoveDirectory(string source, string destination)
        {
            OperationCount++;
            MoveCount++;
            if (FailRestore && Path.GetFullPath(destination) == configDirectory)
            {
                throw new IOException("restore failed");
            }

            events.Add(Path.GetFullPath(destination) == configDirectory
                ? "restore-directory"
                : "backup-directory");
            Directory.Move(source, destination);
        }

        public void DeleteDirectory(string path)
        {
            OperationCount++;
            if (DeleteFailuresRemaining > 0)
            {
                DeleteFailuresRemaining--;
                throw new IOException("cleanup failed");
            }

            events.Add("delete-directory");
            Directory.Delete(path, recursive: true);
        }
    }

    private sealed class FakeProcessFactory(
        FakeProcess process,
        List<string> events) : IConfigurationProcessFactory
    {
        public ConfigurationProcessLaunch Start(
            ConfigurationLaunchRequest request,
            IConfigurationMonotonicClock clock)
        {
            var startingTimestamp = clock.GetTimestamp();
            events.Add("start-child");
            process.StartAction?.Invoke();
            return new ConfigurationProcessLaunch(process, startingTimestamp);
        }
    }

    private sealed class FakeProcess(List<string> events) : IConfigurationProcess
    {
        public Action? StartAction { get; set; }

        public Action? InputIdleAction { get; set; }

        public bool HasExitedValue { get; set; }

        public bool InputIdleResult { get; set; } = true;

        public bool WaitForExitResult { get; set; } = true;

        public Exception? KillError { get; set; }

        public Exception? WaitForExitError { get; set; }

        public Exception? DisposeError { get; set; }

        public TimeSpan? LastExitTimeout { get; private set; }

        public TimeSpan? LastInputIdleTimeout { get; private set; }

        public bool HasExited => HasExitedValue;

        public bool WaitForInputIdle(TimeSpan timeout)
        {
            events.Add("wait-input-idle");
            LastInputIdleTimeout = timeout;
            InputIdleAction?.Invoke();
            return InputIdleResult;
        }

        public void Kill()
        {
            events.Add("kill-child");
            if (KillError is not null)
            {
                throw KillError;
            }

            if (WaitForExitResult)
            {
                HasExitedValue = true;
            }
        }

        public bool WaitForExit(TimeSpan timeout)
        {
            events.Add("wait-exit");
            LastExitTimeout = timeout;
            if (WaitForExitError is not null)
            {
                throw WaitForExitError;
            }

            return WaitForExitResult;
        }

        public void Dispose()
        {
            events.Add("dispose-child");
            if (DisposeError is not null)
            {
                throw DisposeError;
            }
        }
    }

    private sealed class FakeMutexObserver(List<string> events) : IConfigurationMutexObserver
    {
        public bool Result { get; set; } = true;

        public Exception? Error { get; set; }

        public TimeSpan? LastTimeout { get; private set; }

        public Action<TimeSpan>? WaitAction { get; set; }

        public bool WaitUntilCreated(
            IConfigurationProcess process,
            string mutexName,
            TimeSpan timeout)
        {
            events.Add("observe-mutex");
            LastTimeout = timeout;
            WaitAction?.Invoke(timeout);
            if (Error is not null)
            {
                throw Error;
            }

            return Result;
        }
    }

    private sealed class FakeMonotonicClock : IConfigurationMonotonicClock
    {
        private long timestamp;

        public TimeSpan Elapsed => TimeSpan.FromTicks(timestamp);

        public long GetTimestamp() => timestamp;

        public TimeSpan GetElapsedTime(long startingTimestamp) =>
            TimeSpan.FromTicks(timestamp - startingTimestamp);

        public void Advance(TimeSpan elapsed)
        {
            if (elapsed < TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(nameof(elapsed));
            }

            timestamp = checked(timestamp + elapsed.Ticks);
        }
    }
}

[Collection(ProductionMutexCollection.Name)]
public sealed class ProductionConfigurationTransactionRefusalTests
{
    [Fact]
    [Trait("ScreenFixCategory", "DisposableAccount")]
    public void OwnedProductionObjectRefusesBeforeAnyFilesystemAccess()
    {
        VerifyExistingProductionObjectRefuses(initiallyOwned: true);
    }

    [Fact]
    [Trait("ScreenFixCategory", "DisposableAccount")]
    public void UnownedProductionObjectRefusesBeforeAnyFilesystemAccess()
    {
        VerifyExistingProductionObjectRefuses(initiallyOwned: false);
    }

    private static void VerifyExistingProductionObjectRefuses(bool initiallyOwned)
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var configDirectory = Path.Combine(root, "ScreenFix");
        var configFile = Path.Combine(configDirectory, "config.json");
        Directory.CreateDirectory(configDirectory);
        File.WriteAllBytes(configFile, [1, 2, 3]);
        using var existing = new Mutex(
            initiallyOwned,
            ScreenFixApplicationIdentity.SingleInstanceMutexName,
            out var createdNew);
        Assert.True(createdNew);
        var fileSystem = new RefusingFileSystem();
        var dependencies = new ScreenFixConfigurationTransactionDependencies(
            root,
            configFile,
            ScreenFixApplicationIdentity.TryAcquire,
            fileSystem,
            new UnusedProcessFactory(),
            new UnusedMutexObserver(),
            new StopwatchConfigurationClock());

        try
        {
            Assert.Throws<InvalidOperationException>(() =>
                new ScreenFixConfigurationTransaction(true, dependencies));

            Assert.Equal(0, fileSystem.OperationCount);
            Assert.Equal([1, 2, 3], File.ReadAllBytes(configFile));
        }
        finally
        {
            if (initiallyOwned)
            {
                existing.ReleaseMutex();
            }

            Directory.Delete(root, recursive: true);
        }
    }

    private sealed class RefusingFileSystem : IConfigurationFileSystem
    {
        public int OperationCount { get; private set; }

        public bool DirectoryExists(string path) => Access<bool>();

        public bool FileExists(string path) => Access<bool>();

        public FileAttributes GetAttributes(string path) => Access<FileAttributes>();

        public void MoveDirectory(string source, string destination) => Access<object>();

        public void DeleteDirectory(string path) => Access<object>();

        private T Access<T>()
        {
            OperationCount++;
            throw new InvalidOperationException("Filesystem must not be accessed.");
        }
    }

    private sealed class UnusedProcessFactory : IConfigurationProcessFactory
    {
        public ConfigurationProcessLaunch Start(
            ConfigurationLaunchRequest request,
            IConfigurationMonotonicClock clock) =>
            throw new InvalidOperationException("Process factory must not be used.");
    }

    private sealed class UnusedMutexObserver : IConfigurationMutexObserver
    {
        public bool WaitUntilCreated(
            IConfigurationProcess process,
            string mutexName,
            TimeSpan timeout) =>
            throw new InvalidOperationException("Mutex observer must not be used.");
    }
}
