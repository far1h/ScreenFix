# Windows Dual Single-File Packaging Design

**Date:** 2026-08-27  
**Status:** Approved direction; implementation pending  
**Target:** Windows x64 release assets only

## Context

ScreenFix 1.0.3 ships a 116,469,255-byte `ScreenFix.exe`. The Windows application and core C# sources total about 188 KB; most of the published executable is the self-contained .NET 10 runtime, Windows Desktop framework, and native runtime libraries.

The macOS ZIP is much smaller because its native Swift executable links to AppKit and other frameworks already supplied by macOS. The Windows package deliberately includes its runtime so a user can run one executable without installing .NET.

The current Windows publish has these relevant properties:

- `PublishSingleFile=true`
- `SelfContained=true`
- `IncludeNativeLibrariesForSelfExtract=true`
- `EnableCompressionInSingleFile=false`
- `PublishTrimmed=false`

.NET supports compressing files embedded in a single-file bundle. Microsoft documents a size benefit with a startup decompression cost and recommends measuring both. Windows Forms trimming is disabled by the .NET SDK, so trimming is not a safe alternative for ScreenFix.

References:

- [.NET single-file deployment](https://learn.microsoft.com/dotnet/core/deploying/single-file/overview)
- [.NET trimming incompatibilities](https://learn.microsoft.com/dotnet/core/deploying/trimming/incompatibilities#windows-forms)
- [.NET 10.0.0 HostModel bundle compression](https://github.com/dotnet/runtime/blob/v10.0.0/src/installer/managed/Microsoft.NET.HostModel/Bundle/Bundler.cs)

## Goals

1. Publish two self-contained Windows x64 executables from the same source commit.
2. Make the compressed executable the recommended Windows download.
3. Retain the current uncompressed executable as a compatibility fallback.
4. Require no separate .NET or Windows Desktop Runtime installation for either executable.
5. Reduce the compressed executable by at least 20 percent against the uncompressed build from the same commit and SDK.
6. Preserve all ScreenFix behavior, including:
   - notification-area and executable icons;
   - monitor selection, calibration, Save, Cancel, and persisted settings;
   - ordinary window correction after snap, Windows-key-Up, and the maximize button;
   - exclusion of borderless and F11 full-screen windows.
7. Preserve exact package verification for both the managed tray icon and native PE icon resources in both executables.

## Non-goals

- Requiring users to preinstall .NET.
- Publishing a framework-dependent download.
- Enabling `PublishTrimmed` for WinForms.
- Migrating to Native AOT.
- Rewriting the Windows app in C++, Rust, or raw Win32.
- Changing application logic, UI, calibration, correction policy, persistence, icons, or supported Windows architecture.
- Claiming a one-megabyte result. A self-contained .NET Desktop runtime has a much higher practical floor.

## Approaches considered

### 1. Publish compressed and uncompressed self-contained bundles

Publish the same application twice while retaining all deployment properties except `EnableCompressionInSingleFile`. The compressed build is the recommended download, and the uncompressed build is the compatibility fallback. This is the selected approach because it reduces the normal download size without removing the already proven package.

Trade-off: .NET must decompress bundled files into memory during compressed-app startup, and the release contains one additional Windows asset. The size improvement and startup behavior must be measured before acceptance.

### 2. Put both executables in one archive

This shortens the release asset list but forces every Windows user to download both variants and decide which executable to keep. It is less clear than two explicitly labelled downloads.

### 3. Publish framework-dependent

This would make the ScreenFix download much smaller, but every user would need a compatible .NET 10 Windows Desktop Runtime. That violates the accepted no-install requirement.

### 4. Rewrite as a native Windows application

A native rewrite could approach the macOS package size, but it would replace the tested WinForms implementation, duplicate platform behavior, and create substantial regression risk. It is outside this optimization.

## Design

### Controlled size comparison

The package regression will publish two isolated `win-x64` outputs from the same commit, configuration, and .NET 10 SDK:

1. an uncompressed self-contained single-file baseline;
2. a compressed self-contained single-file candidate.

The outputs must use separate `--artifacts-path` and publish directories so apphost or intermediate files cannot contaminate one another. The comparison fails unless:

- both publishes succeed;
- both outputs contain exactly the expected single executable;
- the candidate is smaller than the baseline;
- the candidate is no more than 80 percent of the baseline size.

Both accepted outputs proceed to release staging after the comparison passes. The test reports both byte counts and the percentage reduction.

The comparison is pinned operationally to .NET SDK 10.0.100 and its .NET 10.0.0 self-contained runtime packs. The repository `global.json` allows `latestFeature` roll-forward for ordinary development, so the package scripts cannot rely on repository-root SDK selection or only change the CLI working directory. MSBuild resolves the SDK relative to the project path and must be isolated too.

The packaging workflow installs SDK 10.0.100 into a fresh task-scoped directory that contains no other SDK. Every restore, build, test, baseline publish, candidate publish, and production staging command invokes that installation's absolute `dotnet.exe` path. It requires `dotnet --version` to equal `10.0.100`, requires `dotnet --list-sdks` to report only `10.0.100` from that private root, and logs `dotnet --info`. An MSBuild property probe against the real ScreenFix project must report `NETCoreSdkVersion=10.0.100` and an `MSBuildSDKsPath` beneath that same private root before publishing begins. The isolation regression also makes a newer .NET 10 SDK visible outside the private root and proves both the CLI and MSBuild project resolver ignore it.

After restore, the script reads each isolated `project.assets.json` and requires the resolved `Microsoft.NETCore.App.Runtime.win-x64` and `Microsoft.WindowsDesktop.App.Runtime.win-x64` packages to be exactly `10.0.0`, with no conflicting `Microsoft.*.App.Runtime.win-x64` version. It also requires baseline and candidate runtime-pack sets to be identical. A missing, additional, or different runtime pack fails before size comparison. An SDK or runtime-pack update requires an explicit design/test update and a new same-commit baseline.

### Publish configuration and release staging

The publish runs twice. The uncompressed variant retains `EnableCompressionInSingleFile=false`; the compressed variant changes only that property to `true`.

These properties remain unchanged:

- `SelfContained=true`
- `PublishSingleFile=true`
- `IncludeNativeLibrariesForSelfExtract=true`
- `PublishTrimmed=false`
- `DebugType=None`
- `DebugSymbols=false`
- `UseAppHost=true`

No production C# behavior changes are part of this work.

Each isolated publish output is first validated under its native `ScreenFix.exe` name. Only after validation does release staging copy the files to their user-facing names:

- `ScreenFix-Windows-x64.exe` — compressed, recommended;
- `ScreenFix-Windows-x64-uncompressed.exe` — uncompressed compatibility fallback.

The release staging directory contains exactly those two Windows executables. The versioned SHA-256 checksum file includes both exact names and digests alongside the macOS asset. Release notes identify the compressed asset as recommended, explain that both are self-contained and behavior-identical, report both measured sizes, and describe the uncompressed asset as the fallback for startup or extraction problems.

Two behavior-neutral extractions are permitted for safe test isolation:

- move the existing `Environment.GetFolderPath(LocalApplicationData)` plus `ScreenFix/config.json` computation into an internal `ScreenFixPaths.ConfigFile` member;
- move the existing `Local\\ScreenFix.Native` name into an internal `ScreenFixApplicationIdentity.SingleInstanceMutexName` constant.

Production and the Windows startup harness use those exact shared members. Focused tests require `Program` and `ScreenFixApplicationContext` to consume them, so test infrastructure cannot silently protect a different mutex or path. The existing `InternalsVisibleTo("ScreenFix.Windows.Tests")` access remains sufficient; no environment override or user-facing configuration option is added.

`README.md` changes with the package contract. Its Windows installation steps name `ScreenFix-Windows-x64.exe` as the recommended download, name `ScreenFix-Windows-x64-uncompressed.exe` as the compatibility fallback, state that neither requires a separate .NET installation, and remove the obsolete Windows ZIP and bare `ScreenFix.exe` release instructions.

### Compressed-bundle verification

The current managed package assertion searches the final executable for the uncompressed canonical ICO byte sequence. Compression makes that representation invalid even when the resource is present and correct, so the assertion must understand both final bundle representations instead of being removed.

The Windows package test accepts an explicit expected mode and will:

1. locate the official .NET single-file bundle signature and header offset;
2. require bundle format 6.0 exactly, matching the pinned .NET 10 host;
3. enumerate the bundle manifest with strict checked bounds;
4. locate exactly one `ScreenFix.dll` assembly entry;
5. require a positive compressed size for the compressed variant or a zero compressed size for the uncompressed variant;
6. either decompress the bounded payload with `DeflateStream` or read the bounded raw payload, then require the declared uncompressed length;
7. use `PEReader` and `MetadataReader` to locate the stable `ScreenFix.App.Resources.ScreenFix.ico` embedded manifest resource;
8. compare that resource byte-for-byte with the committed canonical ICO.

The parser is test/package infrastructure only. Before allocating or decompressing, it enforces all of these limits:

- bundle file length is positive and no greater than 512 MiB;
- exactly one valid bundle signature resolves to a header fully inside the file;
- bundle version is exactly 6.0;
- entry count is between 1 and 4096;
- every UTF-8 path is at most 1024 bytes, normalized, relative, and unique;
- every entry has a recognized file type;
- offset, declared size, compressed size, and every addition use checked arithmetic;
- stored payload spans are positive, disjoint, and entirely before the manifest;
- each declared uncompressed entry is no greater than 256 MiB and all entries total no more than 512 MiB;
- `ScreenFix.dll` is an `Assembly`, is no greater than 16 MiB uncompressed, and matches the caller's expected compression mode;
- the manifest is consumed exactly, with no truncated or trailing manifest data.

For a compressed entry, the decompressor receives a stream limited to exactly the entry's `CompressedSize` and a bounded output sink capped at the declared `Size`. It must consume the complete compressed span, produce exactly the declared number of bytes, reach a clean deflate end, and produce no extra byte. For an uncompressed entry, the reader consumes exactly `Size` bytes from the declared span without allocating beyond the same cap. Short, oversized, truncated, corrupt, trailing, or wrong-mode payloads fail with distinct diagnostics.

Managed resource extraction is also exact:

1. require a valid CLR header and nonempty COR managed-resources directory;
2. map `ResourcesDirectory.RelativeVirtualAddress` through the PE section table with checked file bounds;
3. require exactly one `ManifestResource` metadata row with the stable icon name;
4. require that row's `Implementation` handle to be nil so the resource is embedded in `ScreenFix.dll` rather than linked elsewhere;
5. treat the row's offset as relative to the managed-resources directory;
6. require a complete four-byte little-endian length prefix inside that directory;
7. require the length-prefixed payload to remain entirely inside that directory and to equal the canonical ICO length;
8. compare the payload byte-for-byte with the canonical ICO.

Duplicate names, linked resources, missing or invalid COR resource directories, RVA/offset overflow, truncated prefixes, and payloads outside the resource directory all fail explicitly.

### Existing raw-assertion migration

Two current checks depend on the canonical ICO appearing raw inside the uncompressed executable:

- the `ByteSearch` check in `assert-win-x64-package.ps1`;
- `PublishedExecutableIconTests.PublishedExecutable_ContainsCanonicalManagedIconBytes`, invoked through `test-windows-native.ps1`.

Both must change together. The PowerShell assertion retains package shape, hash, MZ, PE32+, AMD64, and Windows GUI subsystem checks, but removes `ByteSearch` and the raw managed-ICO requirement. The C# published-executable test becomes the single shared bundle-aware managed-resource verifier described above and is renamed accordingly. `test-windows-native.ps1` continues to run the complete published-executable test class for each variant, so neither release executable can pass without both managed and native icon verification. The PowerShell regression updates its positive and mutation controls to invoke that shared C# verifier rather than maintaining a second bundle parser.

The existing independent native PE validation remains unchanged: it enumerates `RT_GROUP_ICON`, requires a nine-frame icon group, and compares every referenced `RT_ICON` payload with the canonical ICO frames.

### Runtime behavior

At compressed-app launch, the .NET host reads and decompresses managed bundle entries before normal managed startup. Because `IncludeNativeLibrariesForSelfExtract=true` remains enabled, bundled native libraries are extracted into the bundle cache; first and warm starts therefore have different costs. The uncompressed fallback retains the existing host representation. After that host boundary, both variants execute the same `ScreenFix.dll`, resource loader, application context, tray icon, calibration code, and window-correction code.

Expected application behavior is therefore identical. Missing icons, new loose package files, crashes, configuration changes, or different window behavior are not acceptable.

### Startup measurement

The Windows package regression measures the exact baseline and candidate executables on the same disposable Windows runner account. Each process receives an isolated `DOTNET_BUNDLE_EXTRACT_BASE_DIR`, so it cannot reuse the other variant's extraction cache. The destructive configuration-isolation path is disabled by default and requires an explicit workflow-owned opt-in; interactive/local UAT never invokes it.

Changing the `LOCALAPPDATA` environment variable is not sufficient because .NET resolves `SpecialFolder.LocalApplicationData` through the Windows known-folder API. The startup harness instead calls the same internal `ScreenFixPaths.ConfigFile` and `ScreenFixApplicationIdentity.SingleInstanceMutexName` members used by production, derives the exact ScreenFix directory, and protects the mutex and real path for the complete measurement transaction:

1. call the exact production `SingleInstanceGate.TryAcquire` before any filesystem read, move, creation, or deletion; acquisition succeeds only when the harness creates and owns a new named mutex object, while an existing object is refused with no filesystem mutation even when it is currently unowned;
2. require an absolute non-root path beneath the Windows Local AppData known folder;
3. reject a ScreenFix directory or parent represented by a reparse point;
4. choose a unique nonexistent sibling backup path;
5. atomically move an existing ScreenFix directory to that backup before any launch;
6. while holding the gate, require the real ScreenFix directory to be absent, then call `SingleInstanceGate.Dispose` before launch so ownership is released and the harness's last handle is closed; retaining an unowned mutex handle is forbidden because production rejects any existing named object;
7. after starting one measured executable, use a bounded `Mutex.TryOpenExisting` probe to require that the child created the exact production mutex before accepting `WaitForInputIdle`; dispose every probe handle immediately and before process termination;
8. terminate and wait for that exact process only after all observer handles are closed, then call the production `SingleInstanceGate.TryAcquire` again and require it to create and own a fresh mutex object; an existing object, an abandoned object retained by another handle, or a leaked observation handle takes the non-destructive failure path;
9. only while holding that newly created gate remove the completed launch's test-created contents, then repeat the complete dispose/create/observe/close/terminate/recreate sequence for every launch;
10. in an outer `finally`, while holding the gate, remove any remaining test-created ScreenFix directory and atomically restore the original backup;
11. fail the regression on ownership, backup, per-launch cleanup, or restoration errors after making every safe restoration attempt. If the gate cannot be reacquired because an unexpected instance started, do not delete, overwrite, or move either the real directory or backup; fail with both exact recovery paths.

Baseline and candidate launches alternate while the protected real directory remains empty; no persistent user configuration is read or written. Focused mutex regressions cover an owned existing object, an existing but unowned object, a leaked observation handle that survives child termination, and successful destruction and fresh recreation around every launch. Both existing-object cases prove refusal before creating a backup path or changing any configuration byte. The leaked-handle case proves the harness neither waits on an abandoned mutex nor mutates configuration after fresh creation fails.

The endpoint is `Process.WaitForInputIdle`: ScreenFix creates and shows its `NotifyIcon` before entering the WinForms message loop, so the first idle state occurs after tray initialization. Each launch has a 10-second timeout, must remain alive through the endpoint, and is terminated by the measurement harness afterward.

Measurements alternate baseline and candidate to reduce runner drift:

- **First start:** five measured launches per variant, each with a fresh extraction directory and an empty protected ScreenFix configuration directory.
- **Warm start:** one unmeasured seed plus five measured launches per variant, reusing only that variant's extraction directory while resetting the protected ScreenFix configuration directory before every launch.

The script records every duration and each median. The candidate passes only when:

- first-start median is at most the baseline median plus the greater of 750 ms or 75 percent of the baseline, and is below 5 seconds; and
- warm-start median is at most the baseline median plus the greater of 250 ms or 50 percent of the baseline, and is below 2 seconds.

Timeouts, early process exits, failure to acquire the production mutex, failure to reach input-idle, configuration backup/restoration failures, extraction cleanup failures, or process-termination failures fail the regression. Interactive functional checks must launch the exact accepted staged executables, not later rebuilds, and do not use the destructive measurement harness.

## Testing

Testing remains incremental and preserves the existing RED/GREEN evidence standard.

1. Add a regression that publishes both variants and proves the existing raw-byte managed assertions fail only for the compressed representation.
2. Add focused malformed-bundle tests for: missing/duplicate signature; 6.0 version mismatch; entry count; malformed, rooted, parent, duplicate, and oversized paths; unknown type; checked offset and size overflow; overlapping or out-of-manifest payloads; per-entry and cumulative caps; manifest truncation/trailing data; duplicate or wrong-type `ScreenFix.dll`; missing compression; corrupt, short, oversized, truncated, and trailing deflate data.
3. Add focused managed-resource tests for: invalid or missing CLR/resource directory; RVA mapping and overflow; missing/duplicate resource name; non-nil implementation; resource offset overflow; truncated length prefix; payload outside the directory; wrong length; and mutated bytes.
4. Prove the one shared C# verifier accepts both real packages in their declared modes, rejects a mode mismatch, and rejects a real candidate whose managed ICO is mutated before bundling.
5. Run the native PE icon negative control and exact payload comparison unchanged against both real packages.
6. Prove the package scripts reject an SDK other than 10.0.100 or runtime packs other than 10.0.0, ignore a newer externally visible .NET 10 SDK, and log both CLI and MSBuild SDK resolution plus the runtime-pack set.
7. Add configuration-isolation tests for path and mutex identity; refusal without mutation for owned and unowned existing mutex objects; complete handle disposal before child creation; short-lived observation handles; leaked-handle/abandonment refusal; fresh mutex creation after exact-child exit; invalid/reparse paths; existing-directory backup; clean launch state; per-launch cleanup; restoration after success; and non-destructive failure when fresh creation cannot be regained.
8. Run the isolated same-commit size comparison and the first/warm startup measurements with their stated limits.
9. Prove release staging contains exactly the two named Windows assets, identifies the compressed one as recommended, emits matching SHA-256 entries for both, and matches the names in `README.md`.
10. Run all Windows-native and portable Windows tests.
11. Run the existing macOS and Lua suites to prove the packaging-only change has no cross-platform regression.
12. Run the final Windows workflow twice at the exact commit: push and pull-request events.

## Acceptance criteria

The change is ready only when all of the following are true:

- the compressed executable is at most 80 percent of the same-commit uncompressed baseline;
- both published executables remain self-contained single-file applications with no runtime prerequisite;
- release staging contains exactly `ScreenFix-Windows-x64.exe` and `ScreenFix-Windows-x64-uncompressed.exe` for Windows;
- the compressed executable is labelled as the recommended Windows download and the uncompressed executable as the compatibility fallback;
- package logs prove SDK 10.0.100 and the exact .NET 10.0.0 win-x64 runtime-pack set;
- package logs prove both the CLI and actual ScreenFix MSBuild project ignored externally installed newer SDKs;
- the managed tray ICO in each final bundle exactly matches the committed ICO;
- each native executable icon contains the exact nine canonical frames;
- all existing Windows behavior tests pass unchanged;
- package mutation and iconless negative controls fail for the intended reason;
- first-start and warm-start medians satisfy the documented relative and absolute limits;
- the startup harness runs only with explicit disposable-runner opt-in, refuses without mutation whenever the production mutex object already exists, disposes every handle before launching the child, and owns a freshly created production mutex whenever it moves or deletes configuration data;
- the pre-measurement ScreenFix configuration directory is restored byte-for-byte and no test directory remains after a successful measurement;
- Windows, macOS, and Lua regression suites pass;
- interactive Windows checks use both exact staged executables and confirm the tray icon, Explorer icon, calibration, settings, snap, ordinary maximize, and full-screen exclusion behavior;
- the versioned checksum file contains correct entries for both Windows assets and the macOS asset;
- the GitHub release contains both Windows assets with the approved names and labels;
- `README.md` identifies the compressed filename as recommended and the uncompressed filename as fallback, with no obsolete Windows ZIP or bare `ScreenFix.exe` release instruction;
- release notes report both measured sizes instead of estimating them.

If the 20 percent reduction is not achieved, startup limits fail, or behavior differs, the compressed executable is not released or recommended. The validated uncompressed executable remains the Windows download and no smaller release is claimed.
