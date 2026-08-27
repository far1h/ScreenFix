# Windows Single-File Compression Design

**Date:** 2026-08-27  
**Status:** Approved direction; implementation pending  
**Target:** Windows x64 package only

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

1. Keep one self-contained Windows x64 executable.
2. Require no separate .NET or Windows Desktop Runtime installation.
3. Reduce the executable by at least 20 percent against an uncompressed build from the same commit and SDK.
4. Preserve all ScreenFix behavior, including:
   - notification-area and executable icons;
   - monitor selection, calibration, Save, Cancel, and persisted settings;
   - ordinary window correction after snap, Windows-key-Up, and the maximize button;
   - exclusion of borderless and F11 full-screen windows.
5. Preserve exact package verification for both the managed tray icon and native PE icon resources.

## Non-goals

- Requiring users to preinstall .NET.
- Publishing a second framework-dependent download.
- Enabling `PublishTrimmed` for WinForms.
- Migrating to Native AOT.
- Rewriting the Windows app in C++, Rust, or raw Win32.
- Changing application logic, UI, calibration, correction policy, persistence, icons, or supported Windows architecture.
- Claiming a one-megabyte result. A self-contained .NET Desktop runtime has a much higher practical floor.

## Approaches considered

### 1. Compress the existing self-contained single-file bundle

Set `EnableCompressionInSingleFile=true` while retaining the other deployment properties. This is the selected approach because it reduces download size without changing installation requirements or production logic.

Trade-off: .NET must decompress bundled files into memory during startup. The size improvement and startup behavior must be measured before acceptance.

### 2. Publish framework-dependent

This would make the ScreenFix download much smaller, but every user would need a compatible .NET 10 Windows Desktop Runtime. That violates the accepted no-install requirement.

### 3. Rewrite as a native Windows application

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

The final production publish uses the compressed configuration only after this comparison passes. The test reports both byte counts and the percentage reduction.

The comparison is pinned operationally to .NET SDK 10.0.100 and its .NET 10.0.0 self-contained runtime packs. The repository `global.json` allows `latestFeature` roll-forward for ordinary development, so the package scripts cannot rely on repository-root SDK selection.

Each package script creates a temporary SDK-selection directory containing a minimal `global.json` with version `10.0.100`, `rollForward: "disable"`, and `allowPrerelease: false`. It changes to that directory before invoking the absolute project path, requires `dotnet --version` to equal `10.0.100`, and logs `dotnet --info`. Baseline, candidate, production publish, and their restore steps all run through this exact selector.

After restore, the script reads each isolated `project.assets.json` and requires the resolved `Microsoft.NETCore.App.Runtime.win-x64` and `Microsoft.WindowsDesktop.App.Runtime.win-x64` packages to be exactly `10.0.0`, with no conflicting `Microsoft.*.App.Runtime.win-x64` version. It also requires baseline and candidate runtime-pack sets to be identical. A missing, additional, or different runtime pack fails before size comparison. An SDK or runtime-pack update requires an explicit design/test update and a new same-commit baseline.

### Publish configuration

The production publish changes only `EnableCompressionInSingleFile` from `false` to `true`.

These properties remain unchanged:

- `SelfContained=true`
- `PublishSingleFile=true`
- `IncludeNativeLibrariesForSelfExtract=true`
- `PublishTrimmed=false`
- `DebugType=None`
- `DebugSymbols=false`
- `UseAppHost=true`

No production C# behavior changes are part of this work.

One behavior-neutral refactor is permitted for safe test isolation: move the existing `Environment.GetFolderPath(LocalApplicationData)` plus `ScreenFix/config.json` computation into an internal `ScreenFixPaths.ConfigFile` member. `ScreenFixApplicationContext` and the Windows startup harness both use that exact member. The existing `InternalsVisibleTo("ScreenFix.Windows.Tests")` access remains sufficient; no environment override or user-facing configuration option is added.

### Compressed-bundle verification

The current managed package assertion searches the final executable for the uncompressed canonical ICO byte sequence. Compression makes that representation invalid even when the resource is present and correct, so the assertion must understand the final bundle instead of being removed.

The Windows package test will:

1. locate the official .NET single-file bundle signature and header offset;
2. require bundle format 6.0 exactly, matching the pinned .NET 10 host;
3. enumerate the bundle manifest with strict checked bounds;
4. locate exactly one `ScreenFix.dll` assembly entry;
5. require the entry to be compressed;
6. decompress it with `DeflateStream` and require the declared uncompressed length;
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
- `ScreenFix.dll` is an `Assembly`, is no greater than 16 MiB uncompressed, and has a positive compressed size;
- the manifest is consumed exactly, with no truncated or trailing manifest data.

The decompressor receives a stream limited to exactly the entry's `CompressedSize` and a bounded output sink capped at the declared `Size`. It must consume the complete compressed span, produce exactly the declared number of bytes, reach a clean deflate end, and produce no extra byte. Short, oversized, truncated, corrupt, and trailing compressed payloads fail with distinct diagnostics.

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

Both must change together. The PowerShell assertion retains package shape, hash, MZ, PE32+, AMD64, and Windows GUI subsystem checks, but removes `ByteSearch` and the raw managed-ICO requirement. The C# published-executable test becomes the single shared bundle-aware managed-resource verifier described above and is renamed accordingly. `test-windows-native.ps1` continues to run the complete published-executable test class, so the production publish cannot pass without both managed and native icon verification. The PowerShell regression updates its positive and mutation controls to invoke that shared C# verifier rather than maintaining a second bundle parser.

The existing independent native PE validation remains unchanged: it enumerates `RT_GROUP_ICON`, requires a nine-frame icon group, and compares every referenced `RT_ICON` payload with the canonical ICO frames.

### Runtime behavior

At launch, the .NET host reads and decompresses managed bundle entries before normal managed startup. Because `IncludeNativeLibrariesForSelfExtract=true` remains enabled, bundled native libraries are decompressed into the bundle extraction cache; first and warm starts therefore have different costs. After that host boundary, the same `ScreenFix.dll`, resource loader, application context, tray icon, calibration code, and window-correction code execute.

Expected application behavior is therefore identical. Missing icons, new loose package files, crashes, configuration changes, or different window behavior are not acceptable.

### Startup measurement

The Windows package regression measures the exact baseline and candidate executables on the same runner. Each process receives an isolated `DOTNET_BUNDLE_EXTRACT_BASE_DIR`, so it cannot reuse the other variant's extraction cache.

Changing the `LOCALAPPDATA` environment variable is not sufficient because .NET resolves `SpecialFolder.LocalApplicationData` through the Windows known-folder API. The startup harness instead calls the same internal `ScreenFixPaths.ConfigFile` member used by production, derives the exact ScreenFix directory, and protects that real path for the complete measurement transaction:

1. require an absolute non-root path beneath the Windows Local AppData known folder;
2. reject a ScreenFix directory or parent represented by a reparse point;
3. choose a unique nonexistent sibling backup path;
4. atomically move an existing ScreenFix directory to that backup before any launch;
5. require the real ScreenFix directory to be absent before each measured process, then remove only test-created contents after that process exits;
6. in an outer `finally`, remove any remaining test-created ScreenFix directory and atomically restore the original backup;
7. fail the regression on backup, per-launch cleanup, or restoration errors after making every safe restoration attempt.

A focused test requires `ScreenFixApplicationContext` to consume `ScreenFixPaths.ConfigFile`, so the harness cannot silently protect a different path than production uses. Baseline and candidate launches alternate while the protected real directory remains empty; no persistent user configuration is read or written.

The endpoint is `Process.WaitForInputIdle`: ScreenFix creates and shows its `NotifyIcon` before entering the WinForms message loop, so the first idle state occurs after tray initialization. Each launch has a 10-second timeout, must remain alive through the endpoint, and is terminated by the measurement harness afterward.

Measurements alternate baseline and candidate to reduce runner drift:

- **First start:** five measured launches per variant, each with a fresh extraction directory and an empty protected ScreenFix configuration directory.
- **Warm start:** one unmeasured seed plus five measured launches per variant, reusing only that variant's extraction directory while resetting the protected ScreenFix configuration directory before every launch.

The script records every duration and each median. The candidate passes only when:

- first-start median is at most the baseline median plus the greater of 750 ms or 75 percent of the baseline, and is below 5 seconds; and
- warm-start median is at most the baseline median plus the greater of 250 ms or 50 percent of the baseline, and is below 2 seconds.

Timeouts, early process exits, failure to reach input-idle, configuration backup/restoration failures, extraction cleanup failures, or process-termination failures fail the regression. Interactive functional checks must launch the exact accepted candidate executable, not a later rebuild.

## Testing

Testing remains incremental and preserves the existing RED/GREEN evidence standard.

1. Add a regression that publishes a compressed candidate and proves both existing raw-byte managed assertions fail for representational reasons.
2. Add focused malformed-bundle tests for: missing/duplicate signature; 6.0 version mismatch; entry count; malformed, rooted, parent, duplicate, and oversized paths; unknown type; checked offset and size overflow; overlapping or out-of-manifest payloads; per-entry and cumulative caps; manifest truncation/trailing data; duplicate or wrong-type `ScreenFix.dll`; missing compression; corrupt, short, oversized, truncated, and trailing deflate data.
3. Add focused managed-resource tests for: invalid or missing CLR/resource directory; RVA mapping and overflow; missing/duplicate resource name; non-nil implementation; resource offset overflow; truncated length prefix; payload outside the directory; wrong length; and mutated bytes.
4. Prove the one shared C# verifier accepts the real compressed package and rejects a real candidate whose managed ICO is mutated before bundling.
5. Keep the native PE icon negative control and exact payload comparison unchanged.
6. Prove the package scripts reject an SDK other than 10.0.100 or runtime packs other than 10.0.0, and log the resolved SDK/runtime-pack set.
7. Add configuration-isolation tests for path identity, invalid/reparse paths, existing-directory backup, clean launch state, per-launch cleanup, restoration after success, and restoration after measurement failure.
8. Run the isolated same-commit size comparison and the first/warm startup measurements with their stated limits.
9. Run all Windows-native and portable Windows tests.
10. Run the existing macOS and Lua suites to prove the packaging-only change has no cross-platform regression.
11. Run the final Windows workflow twice at the exact commit: push and pull-request events.

## Acceptance criteria

The change is ready only when all of the following are true:

- the compressed executable is at most 80 percent of the same-commit uncompressed baseline;
- the published package remains one self-contained `ScreenFix.exe` with no runtime prerequisite;
- package logs prove SDK 10.0.100 and the exact .NET 10.0.0 win-x64 runtime-pack set;
- the managed tray ICO in the final compressed bundle exactly matches the committed ICO;
- the native executable icon still contains the exact nine canonical frames;
- all existing Windows behavior tests pass unchanged;
- package mutation and iconless negative controls fail for the intended reason;
- first-start and warm-start medians satisfy the documented relative and absolute limits;
- the pre-measurement ScreenFix configuration directory is restored byte-for-byte and no test directory remains;
- Windows, macOS, and Lua regression suites pass;
- interactive Windows checks use the exact accepted candidate and confirm the tray icon, Explorer icon, calibration, settings, snap, ordinary maximize, and full-screen exclusion behavior;
- release notes report the measured size instead of estimating it.

If the 20 percent reduction is not achieved or behavior differs, the production publish setting remains uncompressed and no smaller release is claimed.
