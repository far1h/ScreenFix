using ScreenFix.App;

namespace ScreenFix.Windows.Tests.Startup;

public sealed class ScreenFixConfigurationTransactionTests
{
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

        transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10));

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

        transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10));
        transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10));

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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Contains("before creating the production mutex", error.Message);
        AssertOrdered(fixture.Events, "wait-exit", "acquire-gate", "restore-directory");
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
        transaction.Dispose();

        Assert.Equal("observer failed", error.Message);
        AssertOrdered(fixture.Events, "observe-mutex", "kill-child", "wait-exit", "restore-directory");
        Assert.Equal([1], File.ReadAllBytes(fixture.ConfigFile));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            transaction.RunLaunch(fixture.Executable, TimeSpan.FromSeconds(10)));
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
            Dependencies = new ScreenFixConfigurationTransactionDependencies(
                LocalAppData,
                ConfigFile,
                AcquireGate,
                FileSystem,
                new FakeProcessFactory(Process, Events),
                Observer);
        }

        public string Root { get; }

        public string LocalAppData { get; }

        public string ConfigDirectory { get; }

        public string ConfigFile { get; }

        public string Executable { get; }

        public List<string> Events { get; } = [];

        public int GateAcquireCount => gateAcquireCount;

        public RecordingFileSystem FileSystem { get; }

        public FakeProcess Process { get; }

        public FakeMutexObserver Observer { get; }

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
        public IConfigurationProcess Start(string executable)
        {
            events.Add("start-child");
            process.StartAction?.Invoke();
            return process;
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

        public bool HasExited => HasExitedValue;

        public bool WaitForInputIdle(TimeSpan timeout)
        {
            events.Add("wait-input-idle");
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
            if (WaitForExitError is not null)
            {
                throw WaitForExitError;
            }

            return WaitForExitResult;
        }

        public void Dispose()
        {
            events.Add("dispose-child");
        }
    }

    private sealed class FakeMutexObserver(List<string> events) : IConfigurationMutexObserver
    {
        public bool Result { get; set; } = true;

        public Exception? Error { get; set; }

        public bool WaitUntilCreated(
            IConfigurationProcess process,
            string mutexName,
            TimeSpan timeout)
        {
            events.Add("observe-mutex");
            if (Error is not null)
            {
                throw Error;
            }

            return Result;
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
            new UnusedMutexObserver());

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
        public IConfigurationProcess Start(string executable) =>
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
