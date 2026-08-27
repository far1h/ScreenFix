namespace ScreenFix.Windows.Tests.Startup;

public sealed class BundleExtractionTransactionTests
{
    [Fact]
    public void ConstructorRefusesWithoutAuthorizationBeforeFilesystemAccess()
    {
        using var fixture = ExtractionFixture.Create();

        var error = Assert.Throws<InvalidOperationException>(() =>
            new BundleExtractionTransaction(false, fixture.RunnerTemp, fixture.Dependencies));

        Assert.Equal(
            "Bundle extraction requires explicit disposable-account opt-in.",
            error.Message);
        Assert.Equal(0, fixture.FileSystem.OperationCount);
    }

    [Fact]
    public void SuccessfulCleanupRemovesOnlyTheOwnedRoot()
    {
        using var fixture = ExtractionFixture.Create();
        var sentinel = Path.Combine(fixture.RunnerTemp, "sentinel.txt");
        File.WriteAllText(sentinel, "preserve");
        string ownedRoot;

        using (var transaction = fixture.CreateTransaction())
        {
            ownedRoot = transaction.RootPath;
            var child = transaction.CreateFirstExtractionPath("compressed", 0);
            File.WriteAllText(Path.Combine(child, "payload.bin"), "test");
            transaction.RecordChildStarted();
            transaction.RecordChildExitProven();
        }

        Assert.False(Directory.Exists(ownedRoot));
        Assert.Equal("preserve", File.ReadAllText(sentinel));
    }

    [Fact]
    public void HandoffClosesMarkerWhileKeepingThePhysicalRootAnchorHeld()
    {
        using var fixture = ExtractionFixture.Create();
        fixture.Deletion.RequireClosedIdentityBeforeHandoff = true;
        var transaction = fixture.CreateTransaction();

        transaction.Dispose();

        Assert.True(fixture.Deletion.IdentityWasClosedBeforeHandoff);
        Assert.True(fixture.Deletion.PhysicalAnchorWasHeldDuringHandoff);
        Assert.False(Directory.Exists(transaction.RootPath));
    }

    [Fact]
    public void WindowsOpenChildMarkerBlocksParentRenameEvenWithDeleteSharing()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        using var fixture = ExtractionFixture.Create();
        var source = Path.Combine(fixture.RunnerTemp, "native-rename-source");
        var destination = Path.Combine(fixture.RunnerTemp, "native-rename-destination");
        Directory.CreateDirectory(source);
        var markerPath = Path.Combine(source, "marker");
        File.WriteAllText(markerPath, "marker");
        using var marker = new FileStream(
            markerPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read | FileShare.Delete);

        var error = Record.Exception(() => Directory.Move(source, destination));

        Assert.NotNull(error);
        Assert.True(
            error is IOException or UnauthorizedAccessException,
            $"Unexpected rename exception: {error}");
        Assert.Contains(error.HResult & 0xffff, new[] { 5, 32 });
        marker.Dispose();
        Directory.Move(source, destination);
        Assert.True(Directory.Exists(destination));
    }

    [Fact]
    public void ProvenProcessFailureStillAllowsCleanup()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        var ownedRoot = transaction.RootPath;
        transaction.RecordChildStarted();
        transaction.RecordChildExitProven();

        transaction.Dispose();

        Assert.False(Directory.Exists(ownedRoot));
    }

    [Fact]
    public void CleanupErrorReportsAndRetainsTheExactRoot()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        var quarantine = transaction.RootPath + ".delete-quarantine";
        fixture.FileSystem.DeleteError = new IOException("synthetic delete failure");

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Equal(
            "Bundle extraction cleanup failed; owned recovery retained for " +
            $"original root: {transaction.RootPath}.",
            error.Message);
        Assert.Contains("synthetic delete failure", error.ToString());
        Assert.Contains(quarantine, error.ToString());
        Assert.False(Directory.Exists(transaction.RootPath));
        Assert.True(Directory.Exists(quarantine));
    }

    [Fact]
    public void IdentityCreationFailureReportsTheRetainedExactRootWithoutDeleting()
    {
        using var fixture = ExtractionFixture.Create();
        fixture.FileSystem.IdentityError = new IOException("identity failed");

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction initialization failed; retained extraction root: {fixture.Candidate}.",
            error.Message);
        Assert.Contains("identity failed", error.ToString());
        Assert.True(Directory.Exists(fixture.Candidate));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void IdentityCreationReplacementIsPreservedWithoutRecursiveDelete(bool reparse)
    {
        using var fixture = ExtractionFixture.Create();
        fixture.FileSystem.ReplaceRootDuringIdentityCreation = true;
        fixture.FileSystem.ReplacementIsReparse = reparse;

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction initialization failed; retained extraction root: {fixture.Candidate}.",
            error.Message);
        Assert.Contains("identity failed after replacement", error.ToString());
        Assert.True(Directory.Exists(fixture.Candidate));
        Assert.True(File.Exists(Path.Combine(fixture.Candidate, "replacement.txt")));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void ConstructorRejectsRunnerTempAtFilesystemRoot()
    {
        using var fixture = ExtractionFixture.Create();
        var root = Path.GetPathRoot(fixture.RunnerTemp)!;

        var error = Assert.Throws<InvalidOperationException>(() =>
            new BundleExtractionTransaction(true, root, fixture.Dependencies));

        Assert.Equal("RUNNER_TEMP must not be a filesystem root.", error.Message);
    }

    [Fact]
    public void ConstructorRejectsCandidateAtFilesystemRoot()
    {
        using var fixture = ExtractionFixture.Create(CandidateKind.FileSystemRoot);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            "bundle extraction root must not be a filesystem root.",
            error.Message);
    }

    [Theory]
    [InlineData(CandidateKind.RunnerTemp)]
    [InlineData(CandidateKind.Outside)]
    public void ConstructorRejectsRootThatIsNotStrictlyBeneathRunnerTemp(CandidateKind kind)
    {
        using var fixture = ExtractionFixture.Create(kind);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            "Bundle extraction root must be a strict child of RUNNER_TEMP.",
            error.Message);
    }

    [Fact]
    public void ConstructorRejectsPreexistingCandidate()
    {
        using var fixture = ExtractionFixture.Create(CandidateKind.Preexisting);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction root must be initially absent: {fixture.Candidate}.",
            error.Message);
    }

    [Fact]
    public void ConstructorRejectsReparseCandidate()
    {
        using var fixture = ExtractionFixture.Create(CandidateKind.Preexisting);
        fixture.FileSystem.ReparsePaths.Add(fixture.Candidate);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction path must not be a reparse point: {fixture.Candidate}.",
            error.Message);
    }

    [Fact]
    public void ConstructorRejectsReparseAncestor()
    {
        using var fixture = ExtractionFixture.Create();
        fixture.FileSystem.ReparsePaths.Add(fixture.RunnerTemp);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction path must not be a reparse point: {fixture.RunnerTemp}.",
            error.Message);
    }

    [Fact]
    public void ConstructorRejectsExistingNonDirectoryAncestor()
    {
        using var fixture = ExtractionFixture.Create();
        fixture.FileSystem.NonDirectoryPaths.Add(fixture.RunnerTemp);

        var error = Assert.Throws<InvalidOperationException>(() => fixture.CreateTransaction());

        Assert.Equal(
            $"Bundle extraction ancestor must be a directory: {fixture.RunnerTemp}.",
            error.Message);
    }

    [Fact]
    public void ReparseReplacementIsPreservedAndRejectedDuringCleanup()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        fixture.FileSystem.ReparsePaths.Add(transaction.RootPath);

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Equal(
            $"Bundle extraction root changed; retained extraction root: {transaction.RootPath}.",
            error.Message);
        Assert.True(Directory.Exists(transaction.RootPath));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void IdentityReplacementIsPreservedAndRejectedDuringCleanup()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        fixture.FileSystem.ReplacementIdentity = [9, 8, 7];

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Equal(
            $"Bundle extraction root changed; retained extraction root: {transaction.RootPath}.",
            error.Message);
        Assert.True(Directory.Exists(transaction.RootPath));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void NestedReparseReplacementIsPreservedAndRejectedDuringCleanup()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        var child = transaction.CreateWarmExtractionPath("compressed");
        fixture.FileSystem.ReparsePaths.Add(child);

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Equal(
            $"Bundle extraction root changed; retained extraction root: {transaction.RootPath}.",
            error.Message);
        Assert.True(Directory.Exists(transaction.RootPath));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void FinalDeleteBoundaryReplacementPreservesOwnedAndReplacementDirectories()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        File.WriteAllText(Path.Combine(transaction.RootPath, "owned.txt"), "owned");
        fixture.Deletion.ReplaceRootAtFinalHandoff = true;

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.NotNull(fixture.Deletion.OwnedRecoveryPath);
        Assert.NotNull(fixture.Deletion.ReplacementQuarantinePath);
        Assert.Contains(fixture.Deletion.OwnedRecoveryPath, error.ToString());
        Assert.Contains(fixture.Deletion.ReplacementQuarantinePath, error.ToString());
        Assert.Equal(
            "owned",
            File.ReadAllText(Path.Combine(fixture.Deletion.OwnedRecoveryPath, "owned.txt")));
        Assert.Equal(
            "replacement",
            File.ReadAllText(Path.Combine(
                fixture.Deletion.ReplacementQuarantinePath,
                "replacement.txt")));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void UnprovenChildExitPreservesTheRootWithRecoveryDiagnostic()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        transaction.RecordChildStarted();

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Equal(
            $"Exact-child exit was not proven; retained extraction root: {transaction.RootPath}.",
            error.Message);
        Assert.True(Directory.Exists(transaction.RootPath));
        Assert.Equal(0, fixture.FileSystem.DeleteCount);
    }

    [Fact]
    public void UnprovenChildRetainsConfigurationRecoveryDiagnostic()
    {
        using var fixture = ExtractionFixture.Create();
        var transaction = fixture.CreateTransaction();
        var configurationFailure = new InvalidOperationException(
            "Configuration paths were preserved. Test path: test. Backup path: backup.");
        transaction.RecordChildStarted();
        transaction.RecordRecoveryFailure(configurationFailure);

        var error = Assert.Throws<InvalidOperationException>(transaction.Dispose);

        Assert.Same(configurationFailure, error.InnerException);
        Assert.Contains("Test path: test", error.ToString());
        Assert.Contains("Backup path: backup", error.ToString());
        Assert.Contains(transaction.RootPath, error.Message);
    }

    [Fact]
    public void ChildPathsAreUniqueValidatedAndPhaseScoped()
    {
        using var fixture = ExtractionFixture.Create();
        using var transaction = fixture.CreateTransaction();

        var firstCompressed = transaction.CreateFirstExtractionPath("compressed", 0);
        var firstUncompressed = transaction.CreateFirstExtractionPath("uncompressed", 0);
        var warmCompressed = transaction.CreateWarmExtractionPath("compressed");
        var warmUncompressed = transaction.CreateWarmExtractionPath("uncompressed");

        Assert.Equal(4, new HashSet<string>(
            [firstCompressed, firstUncompressed, warmCompressed, warmUncompressed],
            StringComparer.OrdinalIgnoreCase).Count);
        Assert.All(
            new[] { firstCompressed, firstUncompressed, warmCompressed, warmUncompressed },
            path =>
            {
                Assert.True(Directory.Exists(path));
                Assert.StartsWith(
                    transaction.RootPath + Path.DirectorySeparatorChar,
                    path,
                    StringComparison.OrdinalIgnoreCase);
            });
        Assert.Throws<InvalidOperationException>(() =>
            transaction.CreateFirstExtractionPath("compressed", 0));
    }

    public enum CandidateKind
    {
        Valid,
        RunnerTemp,
        Outside,
        FileSystemRoot,
        Preexisting,
    }

    private sealed class ExtractionFixture : IDisposable
    {
        private ExtractionFixture(string root, CandidateKind candidateKind)
        {
            Root = root;
            RunnerTemp = Path.Combine(root, "runner-temp");
            Directory.CreateDirectory(RunnerTemp);
            Candidate = candidateKind switch
            {
                CandidateKind.RunnerTemp => RunnerTemp,
                CandidateKind.Outside => Path.Combine(root, "outside"),
                CandidateKind.FileSystemRoot => Path.GetPathRoot(root)!,
                _ => Path.Combine(RunnerTemp, "screenfix-extraction-fixed"),
            };
            if (candidateKind == CandidateKind.Preexisting)
            {
                Directory.CreateDirectory(Candidate);
            }

            FileSystem = new RecordingExtractionFileSystem();
            Deletion = new RecordingDeletionAdapter(FileSystem);
            Dependencies = new BundleExtractionTransactionDependencies(
                FileSystem,
                _ => Candidate,
                () => [1, 2, 3, 4],
                Deletion);
        }

        public string Root { get; }

        public string RunnerTemp { get; }

        public string Candidate { get; }

        public RecordingExtractionFileSystem FileSystem { get; }

        public RecordingDeletionAdapter Deletion { get; }

        public BundleExtractionTransactionDependencies Dependencies { get; }

        public static ExtractionFixture Create(CandidateKind candidateKind = CandidateKind.Valid)
        {
            var root = Path.Combine(
                Path.GetTempPath(),
                "ScreenFix.BundleExtraction.Tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return new ExtractionFixture(root, candidateKind);
        }

        public BundleExtractionTransaction CreateTransaction() =>
            new(true, RunnerTemp, Dependencies);

        public void Dispose()
        {
            if (Directory.Exists(Root))
            {
                Directory.Delete(Root, recursive: true);
            }
        }
    }

    private sealed class RecordingDeletionAdapter(
        RecordingExtractionFileSystem fileSystem) : IBundleExtractionDeletionAdapter
    {
        private readonly Dictionary<string, Guid> identities =
            new(StringComparer.OrdinalIgnoreCase);

        public bool ReplaceRootAtFinalHandoff { get; set; }

        public bool RequireClosedIdentityBeforeHandoff { get; set; }

        public bool IdentityWasClosedBeforeHandoff { get; private set; }

        public bool PhysicalAnchorWasHeldDuringHandoff { get; private set; }

        public string? OwnedRecoveryPath { get; private set; }

        public string? ReplacementQuarantinePath { get; private set; }

        public IBundleExtractionRootAnchor CreateAnchor(string rootPath)
        {
            var normalized = Path.GetFullPath(rootPath);
            var identity = Guid.NewGuid();
            identities.Add(normalized, identity);
            return new RecordingRootAnchor(this, fileSystem, identity);
        }

        private void MoveIdentity(string source, string destination)
        {
            var sourcePath = Path.GetFullPath(source);
            var destinationPath = Path.GetFullPath(destination);
            var identity = identities[sourcePath];
            identities.Remove(sourcePath);
            identities.Add(destinationPath, identity);
        }

        private sealed class RecordingRootAnchor(
            RecordingDeletionAdapter owner,
            RecordingExtractionFileSystem fileSystem,
            Guid identity) : IBundleExtractionRootAnchor
        {
            private bool disposed;

            public void VerifyOwnedPath(string path)
            {
                ObjectDisposedException.ThrowIf(disposed, this);
                var normalized = Path.GetFullPath(path);
                if (!owner.identities.TryGetValue(normalized, out var actual)
                    || actual != identity)
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
                ObjectDisposedException.ThrowIf(disposed, this);
                var quarantine = rootPath + ".delete-quarantine";
                try
                {
                    releaseIdentityAnchor();
                    if (owner.RequireClosedIdentityBeforeHandoff)
                    {
                        owner.IdentityWasClosedBeforeHandoff =
                            !fileSystem.IdentityHandleOpen;
                        owner.PhysicalAnchorWasHeldDuringHandoff = !disposed;
                        if (!owner.IdentityWasClosedBeforeHandoff)
                        {
                            throw new UnauthorizedAccessException(
                                "An open child marker blocks the directory handoff on Windows.");
                        }
                    }

                    if (owner.ReplaceRootAtFinalHandoff)
                    {
                        owner.OwnedRecoveryPath = rootPath + ".owned-recovery";
                        Directory.Move(rootPath, owner.OwnedRecoveryPath);
                        owner.MoveIdentity(rootPath, owner.OwnedRecoveryPath);
                        Directory.CreateDirectory(rootPath);
                        File.WriteAllText(
                            Path.Combine(rootPath, "replacement.txt"),
                            "replacement");
                        owner.identities.Add(Path.GetFullPath(rootPath), Guid.NewGuid());
                    }

                    Directory.Move(rootPath, quarantine);
                    owner.MoveIdentity(rootPath, quarantine);
                    if (owner.identities[Path.GetFullPath(quarantine)] != identity)
                    {
                        owner.ReplacementQuarantinePath = quarantine;
                        throw new IOException(
                            "Owned extraction directory changed during final handoff. " +
                            $"Owned recovery path: {owner.OwnedRecoveryPath}. " +
                            $"Replacement quarantine: {quarantine}.");
                    }

                    validateOwnedRoot(quarantine);
                    fileSystem.DeleteDirectory(quarantine);
                    owner.identities.Remove(Path.GetFullPath(quarantine));
                }
                catch (Exception error)
                {
                    throw new IOException(
                        $"Owned extraction deletion handoff failed. Quarantine path: {quarantine}.",
                        error);
                }
            }

            public void Dispose() => disposed = true;
        }
    }

    private sealed class RecordingExtractionFileSystem : IBundleExtractionFileSystem
    {
        public HashSet<string> ReparsePaths { get; } = new(StringComparer.OrdinalIgnoreCase);

        public HashSet<string> NonDirectoryPaths { get; } = new(StringComparer.OrdinalIgnoreCase);

        public Exception? DeleteError { get; set; }

        public Exception? IdentityError { get; set; }

        public bool ReplaceRootDuringIdentityCreation { get; set; }

        public bool ReplacementIsReparse { get; set; }

        public byte[]? ReplacementIdentity { get; set; }

        public int OperationCount { get; private set; }

        public int DeleteCount { get; private set; }

        public bool IdentityHandleOpen { get; private set; }

        public FileAttributes GetAttributes(string path)
        {
            OperationCount++;
            var fullPath = Path.GetFullPath(path);
            if (ReparsePaths.Contains(fullPath))
            {
                return FileAttributes.Directory | FileAttributes.ReparsePoint;
            }

            if (NonDirectoryPaths.Contains(fullPath))
            {
                return FileAttributes.Normal;
            }

            return File.GetAttributes(fullPath) & ~FileAttributes.ReparsePoint;
        }

        public void CreateDirectory(string path)
        {
            OperationCount++;
            Directory.CreateDirectory(path);
        }

        public Stream CreateIdentityFile(string path, byte[] identity)
        {
            OperationCount++;
            if (ReplaceRootDuringIdentityCreation)
            {
                var root = Path.GetDirectoryName(path)!;
                Directory.Delete(root, recursive: true);
                Directory.CreateDirectory(root);
                File.WriteAllText(Path.Combine(root, "replacement.txt"), "preserve");
                if (ReplacementIsReparse)
                {
                    ReparsePaths.Add(root);
                }

                throw new IOException("identity failed after replacement");
            }

            if (IdentityError is not null)
            {
                throw IdentityError;
            }

            using (var writer = new FileStream(
                       path,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None))
            {
                writer.Write(identity);
                writer.Flush(flushToDisk: true);
            }

            IdentityHandleOpen = true;
            return new TrackingIdentityStream(
                path,
                () => IdentityHandleOpen = false);
        }

        public byte[] ReadIdentityFile(string path)
        {
            OperationCount++;
            if (ReplacementIdentity is not null)
            {
                return ReplacementIdentity;
            }

            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            using var content = new MemoryStream();
            stream.CopyTo(content);
            return content.ToArray();
        }

        public IEnumerable<string> EnumerateEntries(string path)
        {
            OperationCount++;
            return Directory.EnumerateFileSystemEntries(path);
        }

        public void DeleteDirectory(string path)
        {
            OperationCount++;
            DeleteCount++;
            if (DeleteError is not null)
            {
                throw DeleteError;
            }

            Directory.Delete(path, recursive: true);
        }

        private sealed class TrackingIdentityStream(
            string path,
            Action onDisposed) : FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete)
        {
            private bool disposed;

            protected override void Dispose(bool disposing)
            {
                base.Dispose(disposing);
                if (!disposed)
                {
                    disposed = true;
                    onDisposed();
                }
            }
        }
    }
}
