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
- [.NET HostModel bundle compression](https://github.com/dotnet/runtime/blob/main/src/installer/managed/Microsoft.NET.HostModel/Bundle/Bundler.cs)

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

### Compressed-bundle verification

The current managed package assertion searches the final executable for the uncompressed canonical ICO byte sequence. Compression makes that representation invalid even when the resource is present and correct, so the assertion must understand the final bundle instead of being removed.

The Windows package test will:

1. locate the official .NET single-file bundle signature and header offset;
2. require the expected bundle major version;
3. enumerate the bundle manifest with strict bounds checks;
4. locate exactly one `ScreenFix.dll` assembly entry;
5. require the entry to be compressed;
6. decompress it with `DeflateStream` and require the declared uncompressed length;
7. use `PEReader` and `MetadataReader` to locate the stable `ScreenFix.App.Resources.ScreenFix.ico` manifest resource;
8. compare that resource byte-for-byte with the committed canonical ICO.

The parser is test/package infrastructure only. It rejects invalid offsets, negative or excessive sizes, duplicate application entries, unsupported bundle versions, malformed compressed data, missing resources, and trailing or truncated payloads with specific diagnostics.

The existing independent native PE validation remains unchanged: it enumerates `RT_GROUP_ICON`, requires a nine-frame icon group, and compares every referenced `RT_ICON` payload with the canonical ICO frames.

### Runtime behavior

At launch, the .NET host reads and decompresses bundled files before normal managed startup. After that boundary, the same `ScreenFix.dll`, resource loader, application context, tray icon, calibration code, and window-correction code execute.

Expected behavior is therefore identical. A small startup-time increase is acceptable; missing icons, new loose files, crashes, configuration changes, or different window behavior are not.

## Testing

Testing remains incremental and preserves the existing RED/GREEN evidence standard.

1. Add a regression that publishes a compressed candidate and proves the old raw-byte managed assertion fails for representational reasons.
2. Add focused malformed-bundle tests for signature, header, bounds, duplicate entry, compression, decompression length, managed PE, resource name, and resource bytes.
3. Prove the new parser accepts the real compressed package and rejects a candidate with a mutated managed ICO.
4. Keep the native PE icon negative control and exact payload comparison.
5. Run all Windows-native and portable Windows tests.
6. Run the existing macOS and Lua suites to prove the packaging-only change has no cross-platform regression.
7. Run the final Windows workflow twice at the exact commit: push and pull-request events.

## Acceptance criteria

The change is ready only when all of the following are true:

- the compressed executable is at most 80 percent of the same-commit uncompressed baseline;
- the published package remains one self-contained `ScreenFix.exe` with no runtime prerequisite;
- the managed tray ICO in the final compressed bundle exactly matches the committed ICO;
- the native executable icon still contains the exact nine canonical frames;
- all existing Windows behavior tests pass unchanged;
- package mutation and iconless negative controls fail for the intended reason;
- Windows, macOS, and Lua regression suites pass;
- interactive Windows checks confirm the tray icon, Explorer icon, calibration, settings, snap, ordinary maximize, and full-screen exclusion behavior;
- release notes report the measured size instead of estimating it.

If the 20 percent reduction is not achieved or behavior differs, the production publish setting remains uncompressed and no smaller release is claimed.
