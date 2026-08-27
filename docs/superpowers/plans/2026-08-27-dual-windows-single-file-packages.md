# Dual Windows Single-File Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ScreenFix 1.0.4 with a compressed self-contained Windows x64 executable as the recommended download and the unchanged uncompressed self-contained executable as a compatibility fallback, both built from the same source and verified for exact icons, behavior, size, startup, checksums, and release identity.

**Architecture:** Keep the Windows application logic unchanged and publish it twice from isolated intermediates, toggling only `EnableCompressionInSingleFile`. Add a small pure-.NET package-verifier tool that strictly parses .NET 10 bundle format 6.0 and verifies the managed ICO inside either bundle representation; retain the independent Win32 PE icon verifier. A Windows-only startup harness shares the production config path and mutex identity, protects configuration through exact mutex object-lifetime handoffs, and compares the two staged executables on a disposable CI account.

**Tech Stack:** .NET SDK 10.0.100, C# 14, WinForms, `System.Reflection.Metadata`, `System.Reflection.PortableExecutable`, `DeflateStream`, xUnit 2.9.3, PowerShell 7, GitHub Actions, Swift 5.7/macOS 13 packaging, GitHub CLI.

**Design:** `docs/superpowers/specs/2026-08-27-windows-single-file-compression-design.md`

**Pinned format source:** .NET runtime tag `v10.0.0`, `Microsoft.NET.HostModel.Bundle` (`Bundler`, `Manifest`, `FileEntry`, and `FileType`). Bundle version is 6.0; the 32-byte signature begins after an eight-byte header-offset slot; strings use `BinaryWriter`'s seven-bit UTF-8 length; v6 entries are `Offset`, `Size`, `CompressedSize`, `Type`, and relative path.

---

## File structure

New package-verifier files:

- `native/windows/tools/ScreenFix.PackageVerifier/ScreenFix.PackageVerifier.csproj` — cross-platform executable verifier with no third-party runtime dependency.
- `native/windows/tools/ScreenFix.PackageVerifier/Program.cs` — strict CLI parsing and exit codes.
- `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BundleCompressionMode.cs` — explicit compressed/uncompressed contract.
- `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BundleEntry.cs` — immutable validated manifest entry.
- `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BoundedReadStream.cs` — prevents deflate reads beyond one manifest span.
- `native/windows/tools/ScreenFix.PackageVerifier/Bundle/SingleFileBundleReader.cs` — format-6 manifest validation and bounded assembly extraction.
- `native/windows/tools/ScreenFix.PackageVerifier/Resources/ManagedIconResourceReader.cs` — checked CLR/PE managed-resource extraction.
- `native/windows/tools/ScreenFix.PackageVerifier/PackageIconVerifier.cs` — composes bundle and managed-resource checks.
- `native/windows/tools/ScreenFix.PackageVerifier/Properties/AssemblyInfo.cs` — test-only internals visibility.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj` — portable parser/verifier test project.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/BundleFixtureBuilder.cs` — deterministic valid and malformed v6 bundle fixtures.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/ManagedPeFixtureBuilder.cs` — deterministic managed PE/resource fixtures.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/SingleFileBundleReaderTests.cs` — bundle bounds, path, type, overlap, and compression tests.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/ManagedIconResourceReaderTests.cs` — metadata and managed-resource tests.
- `native/windows/tests/ScreenFix.PackageVerifier.Tests/PackageIconVerifierTests.cs` — exact icon and CLI composition tests.

New publishing and startup files:

- `native/windows/src/ScreenFix.App/ScreenFixApplicationIdentity.cs` — one production mutex-name constant and gate factory.
- `native/windows/src/ScreenFix.App/ScreenFixPaths.cs` — one production config path computation.
- `native/windows/tests/ScreenFix.Windows.Tests/Startup/MutexObjectLifetimeTests.cs` — real named-mutex creation/destruction regressions.
- `native/windows/tests/ScreenFix.Windows.Tests/Startup/ScreenFixConfigurationTransaction.cs` — config backup/restore guarded by a freshly created production mutex.
- `native/windows/tests/ScreenFix.Windows.Tests/Startup/ScreenFixConfigurationTransactionTests.cs` — refusal, restore, reparse, and non-destructive failure tests.
- `native/windows/tests/ScreenFix.Windows.Tests/Startup/PublishedExecutableStartupTests.cs` — alternating first/warm startup measurements and thresholds.
- `native/windows/scripts/assert-pinned-win-x64-toolchain.ps1` — exact CLI, MSBuild SDK, and runtime-pack assertions.
- `native/windows/scripts/test-assert-pinned-win-x64-toolchain.ps1` — toolchain assertion regressions.
- `native/windows/scripts/assert-win-x64-release.ps1` — exact staged names, count, hashes, sizes, and README-name contract.
- `native/windows/scripts/test-assert-win-x64-release.ps1` — release staging regressions.

Existing files changed:

- `native/windows/ScreenFix.slnx` — include verifier tool and portable verifier tests.
- `native/windows/src/ScreenFix.App/ScreenFix.App.csproj` — test-selectable managed resource path and v1.0.4 metadata.
- `native/windows/src/ScreenFix.App/Program.cs` — consume shared application identity.
- `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs` — consume shared config path.
- `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj` — link shared identity/path files.
- `native/windows/tests/ScreenFix.App.Tests/LifecycleTests.cs` — shared identity/path contract tests.
- `native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs` — retain only independent native PE icon verification.
- `native/windows/scripts/assert-win-x64-package.ps1` — retain structural PE/package checks and remove raw ICO search.
- `native/windows/scripts/test-assert-win-x64-package.ps1` — move managed-icon controls to the shared verifier and cover both publish modes.
- `native/windows/scripts/test-windows-native.ps1` — accept an absolute pinned `dotnet.exe`, run managed verifier, and pass both executables to startup tests.
- `native/windows/scripts/publish-win-x64.ps1` — isolated dual publish, verification, size gate, timing gate, and release staging.
- `.github/workflows/windows-native.yml` — private SDK, newer external SDK control, dual package tests, and exact two-file CI artifact.
- `README.md` — exact recommended/fallback Windows names and collaborator command changes.
- `native/macos/Resources/Info.plist` — v1.0.4.
- `native/macos/scripts/package-arm64.sh` — v1.0.4 assertion.

## Task 1: Add the portable package-verifier boundary

**Files:**
- Create: `native/windows/tools/ScreenFix.PackageVerifier/ScreenFix.PackageVerifier.csproj`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Program.cs`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BundleCompressionMode.cs`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Properties/AssemblyInfo.cs`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/PackageIconVerifierTests.cs`
- Modify: `native/windows/ScreenFix.slnx`

- [ ] **Step 1: Write the failing CLI contract tests**

Test argument rejection one case at a time: missing executable, missing canonical ICO, invalid `compressed|uncompressed` value, directory instead of regular file, reparse-point input, and unexpected option. Define the successful public entry point now:

```csharp
public enum BundleCompressionMode
{
    Compressed,
    Uncompressed,
}

public sealed record PackageVerificationRequest(
    string Executable,
    string CanonicalIcon,
    BundleCompressionMode CompressionMode);
```

The CLI syntax is:

```text
ScreenFix.PackageVerifier --executable <path> --canonical-icon <path> --compression compressed|uncompressed
```

Use exit code `2` for invalid command input and `1` for a verification failure. Never print a stack trace for an expected invalid package.

- [ ] **Step 2: Run the focused test and prove RED**

Run:

```powershell
dotnet test native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj -c Release --filter FullyQualifiedName~PackageIconVerifierTests
```

Expected: FAIL because the verifier project and CLI contract do not exist.

- [ ] **Step 3: Create the minimal projects and CLI parser**

Target `net10.0`, enable nullable/implicit usings, and reference no NuGet package from the tool. Give the test project the same pinned test dependencies as the other xUnit projects and a project reference to the tool. Add:

```csharp
[assembly: InternalsVisibleTo("ScreenFix.PackageVerifier.Tests")]
```

Make `Program.Main` delegate to a short `Run(string[] args, TextWriter output, TextWriter error)` method so argument behavior is unit-testable without spawning a process. Do not implement bundle parsing yet; a valid request may fail with the single diagnostic `package verification is not implemented`.

- [ ] **Step 4: Run the CLI tests and solution build**

Run the focused test, then:

```powershell
dotnet build native/windows/ScreenFix.slnx -c Release
```

Expected: CLI validation tests PASS; the solution builds with zero warnings/errors.

- [ ] **Step 5: Commit the boundary**

```bash
git add native/windows/ScreenFix.slnx native/windows/tools/ScreenFix.PackageVerifier native/windows/tests/ScreenFix.PackageVerifier.Tests
git commit -m "test: establish Windows package verifier"
```

## Task 2: Parse and bound .NET 10 bundle manifests

**Files:**
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BundleEntry.cs`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Bundle/BoundedReadStream.cs`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Bundle/SingleFileBundleReader.cs`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/BundleFixtureBuilder.cs`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/SingleFileBundleReaderTests.cs`

- [ ] **Step 1: Build one valid synthetic v6 fixture and write the first failing test**

`BundleFixtureBuilder` must write one deterministic Windows-like byte array with one `ScreenFix.dll` assembly entry, the official 32-byte signature, an eight-byte little-endian header offset immediately before it, a 6.0 header, and one exact manifest entry. First test only the happy path and returned entry fields.

- [ ] **Step 2: Run only the happy-path test and prove RED**

```powershell
dotnet test native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj -c Release --filter FullyQualifiedName~SingleFileBundleReaderTests.Valid
```

Expected: FAIL because `SingleFileBundleReader` does not exist.

- [ ] **Step 3: Implement the smallest strict header/entry reader**

Use `FileStream`, checked arithmetic, `BinaryPrimitives`, and a strict UTF-8 decoder. Do not call `BinaryReader.ReadString`; read a maximum five-byte seven-bit encoded length, reject noncanonical/overflow values, cap path bytes at 1,024 before allocation, and reject invalid UTF-8.

Define constants in one place:

```csharp
internal const long MaximumBundleBytes = 512L * 1024 * 1024;
internal const long MaximumEntryBytes = 256L * 1024 * 1024;
internal const long MaximumAppAssemblyBytes = 16L * 1024 * 1024;
internal const int MaximumEntries = 4096;
internal const int MaximumPathBytes = 1024;
internal const uint RequiredMajorVersion = 6;
internal const uint RequiredMinorVersion = 0;
```

Find exactly one signature, resolve its preceding offset, and require the manifest to end exactly at EOF. Recognize only file type bytes `0..5`. Require normalized forward-slash relative paths: no empty segment, `.`, `..`, root, drive prefix, backslash, duplicate, or platform normalization change.

- [ ] **Step 4: Add malformed manifest tests one invariant at a time**

Cover: empty/over-512 MiB file; missing/duplicate signature; header offset underflow/outside file; version mismatch; zero/negative/over-4096 count; malformed/noncanonical seven-bit length; invalid UTF-8; empty/rooted/drive/parent/dot/backslash/duplicate/over-1,024-byte path; unknown type; negative/overflowing offset, size, or compressed size; zero stored span; payload at/after manifest; overlapping spans; per-entry and cumulative caps; truncated and trailing manifest; missing/duplicate/wrong-type `ScreenFix.dll`; and app assembly over 16 MiB.

Every case must assert one stable diagnostic fragment so a bounds failure cannot pass for an unrelated reason.

- [ ] **Step 5: Implement entry-set validation and make each malformed case GREEN**

Calculate stored size as `CompressedSize > 0 ? CompressedSize : Size`. Sort spans by offset and require `previousEnd <= nextOffset <= manifestOffset`. Sum declared sizes with `checked`; reject before allocating. Require exactly one case-sensitive `ScreenFix.dll` of type `Assembly`.

- [ ] **Step 6: Add and implement bounded raw/deflate extraction**

Tests must cover both expected modes plus wrong mode, corrupt deflate, truncated deflate, declared output too short/long, trailing compressed bytes, incomplete compressed-span consumption, and raw span truncation. `BoundedReadStream` must expose at most the manifest's stored span and record exact consumption. The decompressed sink must stop at declared size plus one byte, require exactly declared output, require clean deflate end, and reject unread bytes inside the compressed span.

- [ ] **Step 7: Run focused and full portable tests**

```powershell
dotnet test native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj -c Release
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: all tests PASS with zero warnings.

- [ ] **Step 8: Commit the bundle reader**

```bash
git add native/windows/tools/ScreenFix.PackageVerifier/Bundle native/windows/tests/ScreenFix.PackageVerifier.Tests
git commit -m "test: validate dotnet single-file bundles"
```

## Task 3: Extract and compare the embedded managed ICO

**Files:**
- Create: `native/windows/tools/ScreenFix.PackageVerifier/Resources/ManagedIconResourceReader.cs`
- Create: `native/windows/tools/ScreenFix.PackageVerifier/PackageIconVerifier.cs`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/ManagedPeFixtureBuilder.cs`
- Create: `native/windows/tests/ScreenFix.PackageVerifier.Tests/ManagedIconResourceReaderTests.cs`
- Modify: `native/windows/tests/ScreenFix.PackageVerifier.Tests/PackageIconVerifierTests.cs`
- Modify: `native/windows/tools/ScreenFix.PackageVerifier/Program.cs`

- [ ] **Step 1: Write a valid managed-resource fixture test**

Use `MetadataBuilder`, `MetadataRootBuilder`, and `ManagedPEBuilder` to create a deterministic minimal managed PE with one embedded manifest resource named exactly `ScreenFix.App.Resources.ScreenFix.ico`. Its managed resource blob is a four-byte little-endian length followed by fixture ICO bytes.

- [ ] **Step 2: Run the valid fixture test and prove RED**

```powershell
dotnet test native/windows/tests/ScreenFix.PackageVerifier.Tests/ScreenFix.PackageVerifier.Tests.csproj -c Release --filter FullyQualifiedName~ManagedIconResourceReaderTests.Valid
```

Expected: FAIL because the managed-resource reader does not exist.

- [ ] **Step 3: Implement checked PE/resource lookup**

Use `PEReader` and `MetadataReader`. Require a CLR header and a nonempty managed-resources directory. Map the resource RVA through exactly one section whose raw data contains the complete directory; checked-add `PointerToRawData + (Rva - VirtualAddress)`. Enumerate all `ManifestResource` rows, require one exact case-sensitive name and `Implementation.IsNil`, checked-add its offset relative to the resource-directory start, then read a complete four-byte length prefix and payload wholly inside that directory.

- [ ] **Step 4: Add malformed resource fixtures and tests**

Build or mutate fixtures for invalid PE; missing CLR header; zero/out-of-section/overflowing/truncated resource directory; missing and duplicate stable names; non-nil `AssemblyFile` implementation; offset overflow; truncated four-byte prefix; declared payload outside the resource directory; wrong length; and one-byte-mutated ICO. Assert precise diagnostics.

- [ ] **Step 5: Compose the verifier and CLI**

`PackageIconVerifier.Verify` reads only the selected `ScreenFix.dll`, passes the requested mode to bundle extraction, reads the stable resource, and uses `SequenceEqual` against the complete canonical ICO. The CLI prints one success line containing mode, executable bytes, managed assembly declared/stored bytes, and icon bytes; it must not print file contents or environment values.

- [ ] **Step 6: Run all verifier tests twice**

Run the test project twice in fresh processes to catch static/shared-state assumptions. Expected: both runs PASS with identical fixture results.

- [ ] **Step 7: Commit exact managed icon verification**

```bash
git add native/windows/tools/ScreenFix.PackageVerifier native/windows/tests/ScreenFix.PackageVerifier.Tests
git commit -m "test: verify managed icon inside dotnet bundle"
```

## Task 4: Replace raw icon searches and verify both real bundle modes

**Files:**
- Modify: `native/windows/src/ScreenFix.App/ScreenFix.App.csproj`
- Modify: `native/windows/scripts/assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/test-assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/test-windows-native.ps1`
- Modify: `native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs`

- [ ] **Step 1: Capture the representational RED on a real compressed publish**

Publish once with `EnableCompressionInSingleFile=true` into a unique `--artifacts-path` and output directory. Run the current PowerShell raw-byte assertion and current managed raw-byte xUnit test. Record that the uncompressed publish passes while the compressed publish fails specifically because the canonical ICO is not raw in the executable. Do not weaken either assertion before this evidence exists.

- [ ] **Step 2: Add a test-selectable managed resource item**

In `ScreenFix.App.csproj`, define a default property whose production value remains `Resources\ScreenFix.ico`:

```xml
<ScreenFixManagedIcon Condition="'$(ScreenFixManagedIcon)' == ''">Resources\ScreenFix.ico</ScreenFixManagedIcon>
...
<EmbeddedResource Include="$(ScreenFixManagedIcon)"
                  LogicalName="ScreenFix.App.Resources.ScreenFix.ico" />
```

Keep `ApplicationIcon` pointed at the canonical committed icon. This property exists only to construct a real managed-resource mutation control; no runtime behavior or user setting changes.

- [ ] **Step 3: Migrate the PowerShell and xUnit assertions together**

Remove the `Add-Type` `ByteSearch` and raw ICO check from `assert-win-x64-package.ps1`, retaining exact one-file shape, regular/nonempty file, SHA-256, MZ, PE signature/offset bounds, AMD64, PE32+, and GUI subsystem checks. Remove `PublishedExecutable_ContainsCanonicalManagedIconBytes` from the Windows-native test file; retain the native `LoadLibraryExW`/`RT_GROUP_ICON`/`RT_ICON` test unchanged.

Add `-DotnetPath` and validated `-ExpectedCompression compressed|uncompressed` parameters to `test-windows-native.ps1`. Invoke the shared verifier tool through the absolute dotnet path, then execute native tests on Windows.

- [ ] **Step 4: Replace the synthetic raw-icon controls**

Keep the structural PE controls in `test-assert-win-x64-package.ps1`. Add isolated real publishes for both modes and require the shared verifier to accept each only in its declared mode. Publish a compressed candidate with a one-byte-mutated temporary ICO passed through `ScreenFixManagedIcon`; require the verifier to reject it for exact managed-icon mismatch. Publish iconless native apphosts in both modes; require the independent native PE test to reject both, then publish a normal package after each control to prove no shared apphost contamination.

Every publish gets a separate `--artifacts-path`; verify the shared RID apphost hash is unchanged by negative controls.

- [ ] **Step 5: Run portable checks locally and Windows checks in CI**

On macOS/Linux, run the package-verifier suite, PowerShell parser tests, and Windows cross-build. Push the focused commit to trigger `windows-latest`; require real compressed/uncompressed managed and native checks to pass.

- [ ] **Step 6: Commit the assertion migration**

```bash
git add native/windows/src/ScreenFix.App/ScreenFix.App.csproj native/windows/scripts native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs
git commit -m "test: verify icons in both Windows bundles"
```

## Task 5: Share production identity and protect startup configuration

**Files:**
- Create: `native/windows/src/ScreenFix.App/ScreenFixApplicationIdentity.cs`
- Create: `native/windows/src/ScreenFix.App/ScreenFixPaths.cs`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/Startup/MutexObjectLifetimeTests.cs`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/Startup/ScreenFixConfigurationTransaction.cs`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/Startup/ScreenFixConfigurationTransactionTests.cs`
- Modify: `native/windows/src/ScreenFix.App/Program.cs`
- Modify: `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`
- Modify: `native/windows/tests/ScreenFix.App.Tests/LifecycleTests.cs`

- [ ] **Step 1: Write identity/path contract tests and prove RED**

Test the exact mutex value `Local\ScreenFix.Native`; config path equal to `Path.Combine(Environment.GetFolderPath(LocalApplicationData), "ScreenFix", "config.json")`; and idempotent gate disposal. Link the two new source files into `ScreenFix.App.Tests` as existing lifecycle sources are linked.

- [ ] **Step 2: Extract the behavior-neutral production members**

`ScreenFixApplicationIdentity.TryAcquire()` delegates to `SingleInstanceGate.TryAcquire(SingleInstanceMutexName)`. `Program` calls that method. `ScreenFixPaths.ConfigFile` performs the existing path computation, and `ScreenFixApplicationContext` passes it unchanged to `RuntimeConfigStore`.

Run portable app tests and a Windows cross-build. Expected: no behavior test changes and zero warnings.

- [ ] **Step 3: Write real mutex lifetime RED tests**

On Windows, cover one case per test using unique names first, then one serialized production-name test on the disposable runner:

- an owned existing object makes production `TryAcquire` return null;
- an existing but unowned object also returns null;
- disposing the final owning handle destroys the object so the next `TryAcquire` creates it;
- a short-lived `Mutex.TryOpenExisting` observer does not prevent later destruction;
- a deliberately leaked observer keeps the abandoned object alive and makes fresh creation fail.

Put fixed-name tests in a nonparallel xUnit collection. Do not use arbitrary sleeps; synchronize through process exit, handle disposal, and bounded polling only where the child creates a named object.

- [ ] **Step 4: Implement the configuration transaction incrementally**

The constructor requires an explicit `allowDisposableAccountMutation` boolean, creates/owns a fresh production gate before any filesystem operation, validates the absolute Local AppData child path and every existing ancestor for reparse points, chooses a unique nonexistent sibling backup, and atomically moves an existing directory.

Expose one operation that:

1. proves the real directory absent while holding the gate;
2. fully disposes the gate;
3. starts the exact child;
4. observes the child's production mutex with a bounded, immediately disposed handle;
5. waits for the requested startup endpoint;
6. closes all observers, terminates, and waits for the exact child;
7. calls production `TryAcquire` and requires fresh creation;
8. only then removes test-created configuration.

Outer disposal restores the original directory only while owning a freshly created gate. If fresh creation fails, preserve both paths and report them without moving/deleting either.

- [ ] **Step 5: Add refusal and restore tests one at a time**

Cover opt-in absent; owned and unowned production object refusal before backup creation; root/outside-Local-AppData path; reparse directory/ancestor; clean missing directory; byte-for-byte backup/restore; per-launch cleanup; child exits before mutex; child creates mutex but exits before input idle; leaked observer; cleanup failure; restore failure; and success leaving no backup/test directory.

- [ ] **Step 6: Run Windows tests twice**

Use the Windows workflow and require both attempts to pass. Inspect logs for no abandoned-mutex exception, no retained backup path on success, and the intended non-destructive diagnostic in injected failure cases.

- [ ] **Step 7: Commit safe startup isolation**

```bash
git add native/windows/src/ScreenFix.App native/windows/tests/ScreenFix.App.Tests native/windows/tests/ScreenFix.Windows.Tests/Startup
git commit -m "test: isolate Windows startup measurements"
```

## Task 6: Pin the actual CLI, MSBuild SDK, and runtime packs

**Files:**
- Create: `native/windows/scripts/assert-pinned-win-x64-toolchain.ps1`
- Create: `native/windows/scripts/test-assert-pinned-win-x64-toolchain.ps1`
- Modify: `native/windows/scripts/test-windows-native.ps1`
- Modify: `native/windows/scripts/test-assert-win-x64-package.ps1`
- Modify: `.github/workflows/windows-native.yml`

- [ ] **Step 1: Write PowerShell RED controls**

The test script creates temporary fake dotnet launchers/output fixtures and proves rejection for: missing/reparse/non-executable path, CLI version other than `10.0.100`, zero or multiple private SDK entries, private SDK path outside its root, MSBuild `NETCoreSdkVersion` mismatch, `MSBuildSDKsPath` outside the private root, absent newer external 10.x SDK, external root equal/nested with private root, runtime pack other than `10.0.0`, missing/additional conflicting runtime pack, and baseline/candidate pack-set mismatch.

- [ ] **Step 2: Implement the strict toolchain assertion**

Require absolute `DotnetPath`, `ExternalDotnetPath`, real app project, and later the two isolated `project.assets.json` paths. Execute:

```powershell
& $DotnetPath --version
& $DotnetPath --list-sdks
& $DotnetPath --info
& $DotnetPath msbuild $Project -nologo -getProperty:NETCoreSdkVersion
& $DotnetPath msbuild $Project -nologo -getProperty:MSBuildSDKsPath
```

Normalize paths with `GetFullPath`, use separator-aware descendant checks, and require the private root to contain only SDK `10.0.100`. Require the external launcher to report at least one stable `10.0.*` SDK unequal to `10.0.100`. Parse both assets files with `ConvertFrom-Json -AsHashtable`; require exactly `Microsoft.NETCore.App.Runtime.win-x64/10.0.0` and `Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0`, no other `Microsoft.*.App.Runtime.win-x64` version, and identical sets.

- [ ] **Step 3: Make every script use the absolute launcher**

Thread required `-DotnetPath` parameters through test and publish scripts. Replace every bare `dotnet` call. Repeat-safe scripts must restore all environment variables in `finally` and never rewrite `PATH`, `DOTNET_ROOT`, or user configuration.

- [ ] **Step 4: Configure isolated and external SDK roots in CI**

Run `actions/setup-dotnet@v6` once with step-scoped `DOTNET_INSTALL_DIR=${{ runner.temp }}\screenfix-external-dotnet` and `dotnet-version: 10.0.x`, then once with a fresh `DOTNET_INSTALL_DIR=${{ runner.temp }}\screenfix-dotnet-10.0.100` and exact `10.0.100`. Store both absolute `dotnet.exe` paths in dedicated `SCREENFIX_*` environment variables; all commands invoke the private path directly. The assertion must prove the external version is newer and ignored by the real ScreenFix project.

- [ ] **Step 5: Run parser tests locally and the exact workflow on Windows**

Expected: all synthetic rejection messages match, and CI logs CLI/MSBuild 10.0.100 plus both 10.0.0 packs even though another 10.x SDK is visible.

- [ ] **Step 6: Commit toolchain isolation**

```bash
git add native/windows/scripts .github/workflows/windows-native.yml
git commit -m "build: isolate Windows package toolchain"
```

## Task 7: Publish, compare, and stage both Windows executables

**Files:**
- Create: `native/windows/scripts/assert-win-x64-release.ps1`
- Create: `native/windows/scripts/test-assert-win-x64-release.ps1`
- Modify: `native/windows/scripts/publish-win-x64.ps1`
- Modify: `native/windows/scripts/assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/test-windows-native.ps1`
- Modify: `.github/workflows/windows-native.yml`

- [ ] **Step 1: Write release-staging RED tests**

Use temporary fixture files and README text to reject: missing either asset, legacy `ScreenFix.exe`, extra companion file, directory/reparse/empty file, swapped names, compressed size not smaller, candidate over 80 percent of baseline, absent/incorrect README names, obsolete `ScreenFix-windows-x64.zip`, and obsolete bare release instruction. Verify SHA-256 values are reported for both exact names.

- [ ] **Step 2: Refactor publishing into one mode-specific helper**

`publish-win-x64.ps1` accepts required private/external dotnet paths and a startup-measurement opt-in. Resolve and validate fixed repository-owned output roots before deleting only those roots. Publish twice with separate `--artifacts-path` and `-o` directories:

```text
artifacts/windows/build/uncompressed/ScreenFix.exe
artifacts/windows/build/compressed/ScreenFix.exe
artifacts/windows/obj/uncompressed/...
artifacts/windows/obj/compressed/...
```

Pass all existing properties identically and set only:

```text
-p:EnableCompressionInSingleFile=false
-p:EnableCompressionInSingleFile=true
```

Require exactly one regular nonempty output per publish.

- [ ] **Step 3: Verify before staging**

After both restores/publishes, locate exactly one app `project.assets.json` under each isolated artifacts root; run the toolchain/runtime-pack assertion; run structural package checks; run the shared managed verifier with the declared mode; and run independent native icon checks on both. Compare lengths and require `compressed <= floor(uncompressed * 0.80)`.

- [ ] **Step 4: Stage with approved public names**

Only after every prior gate passes, create a fresh staging directory containing exactly:

```text
native/windows/artifacts/windows/release/ScreenFix-Windows-x64.exe
native/windows/artifacts/windows/release/ScreenFix-Windows-x64-uncompressed.exe
```

Copy the compressed candidate to the first/recommended name and the baseline to the fallback name. Re-run structural, managed, and native checks against the renamed bytes and require source/staged SHA-256 equality.

- [ ] **Step 5: Assert staging and rerun deterministically**

Run `assert-win-x64-release.ps1`, record sizes/hashes/reduction, rerun the entire publish in fresh intermediates, and require identical bytes for each corresponding asset. If deterministic equality is not provided by the pinned toolchain, stop and identify the changing PE/bundle field rather than weakening the check.

- [ ] **Step 6: Upload the exact CI artifact**

Add `actions/upload-artifact@v7` after all tests with `if-no-files-found: error`, a commit-specific artifact name, and only the two staged executables. Download it in a later verification step and rerun the release assertion so upload packaging cannot rename or nest files unexpectedly.

- [ ] **Step 7: Commit dual publishing**

```bash
git add native/windows/scripts .github/workflows/windows-native.yml
git commit -m "build: publish dual Windows executables"
```

## Task 8: Measure exact first and warm startup behavior

**Files:**
- Create: `native/windows/tests/ScreenFix.Windows.Tests/Startup/PublishedExecutableStartupTests.cs`
- Modify: `native/windows/scripts/test-windows-native.ps1`
- Modify: `native/windows/scripts/publish-win-x64.ps1`
- Modify: `.github/workflows/windows-native.yml`

- [ ] **Step 1: Write failing median and threshold unit tests**

Extract pure helpers for median and limits. Cover odd/even samples, overflow-safe `TimeSpan` math, first limit `baseline + max(750 ms, 75%)` plus absolute `<5 s`, and warm limit `baseline + max(250 ms, 50%)` plus absolute `<2 s`.

- [ ] **Step 2: Write a one-launch Windows integration test**

Require two absolute staged executable paths and explicit disposable-runner opt-in from the filtered invocation. Start a stopwatch immediately before `Process.Start`; require the child-owned production mutex through a short-lived observer; call `WaitForInputIdle` with a 10-second timeout; require the child still alive; stop timing; then terminate, wait, freshly acquire the mutex, and clean config through `ScreenFixConfigurationTransaction`.

Use a unique `DOTNET_BUNDLE_EXTRACT_BASE_DIR` passed only to the child. Preserve and restore any inherited environment value.

- [ ] **Step 3: Prove the safety RED cases**

With a production mutex already existing, run the filtered measurement test and require refusal before any config path mutation. With an injected leaked observer, require non-destructive failure and exact recovery-path diagnostics. Run these before enabling the multi-launch benchmark.

- [ ] **Step 4: Implement alternating first-start measurements**

Create five fresh extraction directories per variant. Alternate baseline/candidate ordering for ten measured launches, reset config after each through owned-gate cleanup, record every duration, and calculate medians. Fail any timeout, early exit, missing mutex, cleanup failure, or threshold violation.

- [ ] **Step 5: Implement alternating warm-start measurements**

Use one extraction directory per variant, run one unmeasured seed each, then alternate five measured launches per variant while reusing only that variant's extraction directory. Reset protected config every time. Print samples, medians, relative deltas, and thresholds without user paths/config contents.

- [ ] **Step 6: Wire the exact staged files into publishing**

The publish script runs the startup filter only after staging and passes explicit opt-in on CI. The workflow must not run if a user ScreenFix instance owns the mutex. Interactive UAT launches the same staged bytes later without the measurement switch.

- [ ] **Step 7: Run the complete Windows workflow twice**

Require both attempts at the same commit to meet size and startup gates. A single timing failure is investigated from raw samples; do not add sleeps, retries, or relaxed thresholds as a workaround.

- [ ] **Step 8: Commit startup measurement**

```bash
git add native/windows/tests/ScreenFix.Windows.Tests/Startup native/windows/scripts .github/workflows/windows-native.yml
git commit -m "test: measure compressed Windows startup"
```

## Task 9: Update documentation, version, and release contracts

**Files:**
- Modify: `README.md`
- Modify: `native/windows/src/ScreenFix.App/ScreenFix.App.csproj`
- Modify: `native/macos/Resources/Info.plist`
- Modify: `native/macos/scripts/package-arm64.sh`
- Modify: `native/windows/scripts/test-assert-win-x64-release.ps1`

- [ ] **Step 1: Make the README-name regression RED**

Run the release assertion against the current README. Expected: FAIL because it names `ScreenFix-windows-x64.zip`/`ScreenFix.exe` instead of both staged assets.

- [ ] **Step 2: Update concise Windows install/collaboration instructions**

Name `ScreenFix-Windows-x64.exe` first as the recommended smaller self-contained download. Name `ScreenFix-Windows-x64-uncompressed.exe` as the behavior-identical fallback for startup/extraction trouble. State neither needs a separate .NET runtime, there is no ZIP to extract, and both target ordinary Intel/AMD x64 Windows. Update collaborator commands with required pinned launcher parameters or point to the exact workflow.

- [ ] **Step 3: Bump all native release metadata to 1.0.4**

Set Windows `Version`, `AssemblyVersion`, `FileVersion`, and `InformationalVersion` consistently to 1.0.4/1.0.4.0. Set macOS `CFBundleShortVersionString` to 1.0.4 and update the packaging assertion. Search the release-bearing source tree for stale `1.0.3`; allow it only in historical docs/spec context.

- [ ] **Step 4: Run cross-platform documentation/version checks**

Run the release assertion fixture tests, package-verifier tests, Windows cross-build, macOS native tests/package tests, and Lua suite. Expected: README names match staged names and every current package reports 1.0.4.

- [ ] **Step 5: Commit release metadata and docs**

```bash
git add README.md native/windows/src/ScreenFix.App/ScreenFix.App.csproj native/macos/Resources/Info.plist native/macos/scripts/package-arm64.sh native/windows/scripts/test-assert-win-x64-release.ps1
git commit -m "docs: prepare ScreenFix 1.0.4 downloads"
```

## Task 10: Final verification and reviews

**Files:**
- Review all files changed since `49713e7`
- Create verification evidence in PR/check logs; do not commit generated artifacts

- [ ] **Step 1: Run local macOS and portable verification from clean outputs**

```bash
native/windows/scripts/test-build-app-icon.sh
dotnet test native/windows/ScreenFix.slnx -c Release
native/macos/scripts/run-tests.sh
native/macos/scripts/test-package-arm64.sh
lua tests/run.lua
git diff --check
git status --short
```

Expected: every suite passes, the Windows projects cross-build warning-free, macOS ZIP is valid v1.0.4, Lua passes, and only intended source/docs changes remain tracked.

- [ ] **Step 2: Push the branch and capture exact Windows CI evidence**

Push `optimize/windows-single-file-size`. Locate the push run by exact `headSha`, wait for completion, and record the run ID, commit, two staged byte sizes/hashes, reduction percentage, runtime-pack set, and first/warm samples/medians.

- [ ] **Step 3: Open the PR and run the pull-request workflow**

Create a focused PR against `main` describing the two assets, measured size/startup trade-off, unchanged behavior, and fallback. Confirm the PR event run uses the exact PR head SHA and passes independently of the push run.

- [ ] **Step 4: Request independent reviews**

Run one spec-compliance review and one maintainability/safety review over the complete diff. Fix every Important/Critical finding with a focused regression and rerun both review scopes. Review specifically: bundle bounds, PE resource offsets, mutex/config safety, PowerShell path/deletion safety, exact SDK resolution, artifact naming, and release fallback.

- [ ] **Step 5: Perform Windows interactive UAT on both exact CI artifacts**

Download the exact two-file CI artifact without rebuilding. On normal and high-DPI Windows x64, run one asset at a time and verify: Explorer icon, tray icon, single-instance exit, monitor selection, calibration Save/Cancel, persisted settings, snap left/right, Win+Up, maximize button, black-area avoidance, and exclusion of borderless/F11 full-screen windows. Confirm both variants behave the same; record any startup impression separately from correctness.

- [ ] **Step 6: Re-run exact CI after the final fix**

If any review/UAT change is made, repeat push and PR workflows twice at the new exact SHA. Do not carry forward evidence from an older commit.

## Task 11: Merge, release v1.0.4, and clean up

**Files:**
- Release assets only; no generated artifact is committed

- [ ] **Step 1: Merge only after all required checks and reviews pass**

Inspect PR state/body/checks, merge through GitHub, fetch `origin/main`, and record the exact merge SHA. Confirm v1.0.4 does not already exist before creating anything.

- [ ] **Step 2: Produce Windows artifacts from the exact merge SHA**

Dispatch `windows-native.yml` on `main`, select the workflow-dispatch run whose `headSha` exactly equals the merge SHA, wait for green completion, and download its commit-specific two-file artifact. Rerun staged-name, size, SHA-256, PE structure, managed bundle icon, and native PE icon assertions without rebuilding.

- [ ] **Step 3: Produce the macOS artifact from the same merge SHA**

Create a temporary detached worktree at the merge SHA, run macOS native tests and `test-package-arm64.sh`, and copy only `ScreenFix-macos-arm64.zip` into a fresh release staging directory. Verify v1.0.4 metadata, arm64 architecture, macOS 13 minimum, code signature, ZIP contents, and SHA-256.

- [ ] **Step 4: Generate and verify the combined checksum file**

The release directory must contain exactly three binaries before checksums:

```text
ScreenFix-Windows-x64.exe
ScreenFix-Windows-x64-uncompressed.exe
ScreenFix-macos-arm64.zip
```

Generate `ScreenFix-v1.0.4-SHA256SUMS.txt` with lowercase SHA-256 and exact filenames in ordinal filename order. Verify every line against the bytes, then require exactly four final release files.

- [ ] **Step 5: Create the GitHub release with explicit labels**

Create tag/release `v1.0.4` targeting the exact merge SHA. Release notes report measured byte sizes and startup medians, say both Windows variants are behavior-identical/self-contained, name the compressed asset as recommended, and name the uncompressed asset as fallback. Upload with labels:

```text
ScreenFix-Windows-x64.exe#Windows x64 (recommended, self-contained)
ScreenFix-Windows-x64-uncompressed.exe#Windows x64 (uncompressed fallback)
ScreenFix-macos-arm64.zip#macOS Apple Silicon (macOS 13+)
ScreenFix-v1.0.4-SHA256SUMS.txt#SHA-256 checksums
```

- [ ] **Step 6: Audit the public release**

Use `gh release view v1.0.4 --json ...` and direct downloads to prove: tag target equals merge SHA; release is neither draft nor prerelease; exactly four assets exist; names/labels/sizes/digests match local staged files; checksum file verifies downloaded bytes; compressed Windows is at most 80 percent of uncompressed; and README links/instructions resolve to the new assets.

- [ ] **Step 7: Clean up recoverably**

Remove only the validated temporary release directory and detached worktree. Confirm no ScreenFix config backup/test directory remains on the Windows runner. After verifying `main` contains the merge and v1.0.4 is public, delete the merged remote feature branch if GitHub did not, switch the local workspace to updated `main`, and delete the local feature branch. Never remove source artifacts or user configuration.

- [ ] **Step 8: Complete the active goal**

Perform a requirement-by-requirement audit against the design and this plan. Only after every asset, check, PR, merge, release, checksum, UAT, and cleanup item has authoritative evidence, mark the goal complete and report the PR, release URL, exact sizes, reduction, startup medians, and hashes.
