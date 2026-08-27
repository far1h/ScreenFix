# Windows Icons and Maximize Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Windows tray and executable the approved Screen Patch icon, and make ordinary maximized windows restore into ScreenFix's existing safe frame without changing full-screen policy.

**Architecture:** Correct the `WINDOWPLACEMENT` ABI at its interop boundary and leave correction policy unchanged. Generate one committed, validated nine-frame ICO from the approved SVG; use that exact file as both the apphost icon and a stable managed resource, then verify those two publication paths independently in the final single-file executable.

**Tech Stack:** .NET 10.0.100, C# 14, WinForms, source-generated Win32 interop, xUnit, PowerShell 7, Bash 3.2, macOS `sips`, Python 3 standard library, GitHub Actions `windows-latest`.

---

## Implementation constraints

- Follow `docs/superpowers/specs/2026-08-27-windows-icons-maximize-design.md` exactly.
- Identify and preserve the current policy boundary: ordinary zoomed windows are corrected; borderless, exclusive, and F11 full-screen windows remain excluded by existing eligibility code.
- Do not change mask geometry, side selection, calibration, macOS behavior, or release layout.
- Treat each task below as a separate worker ownership boundary. A worker changes only the files listed for its task, does not revert concurrent edits, and commits before handoff.
- Capture RED evidence before each production change. Do not weaken a success-oriented test to make it pass.
- The local system `dotnet` lacks the pinned .NET 10 SDK and local `pwsh` is unavailable. Where present, `/private/tmp/screenfix-dotnet10.469wuK/sdk/dotnet` is an environment example only; never commit that path or depend on it in scripts.
- Use ordinary Windows paths in the workflow (`native\windows\...`) and repository-relative paths in cross-platform shell commands.

## File map and ownership

| Area | Files | Responsibility |
| --- | --- | --- |
| Placement regressions and CI | `.github/workflows/windows-native.yml`, `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`, `native/windows/tests/ScreenFix.App.Tests/NativeWindowPlacementTests.cs`, `native/windows/tests/ScreenFix.Windows.Tests/WindowNativePlacementTests.cs` | Prove the 60-byte ABI defect portably and prove the real cross-thread Windows restore path on a message-pumping STA thread. |
| Placement fix | `native/windows/src/ScreenFix.App/Interop/NativeTypes.cs`, `native/windows/src/ScreenFix.App/Interop/WindowNative.cs`, `native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs`, `native/windows/tests/ScreenFix.App.Tests/WindowCorrectorTests.cs` | Remove only the non-Windows `DeviceRectangle` field and mappings. |
| Icon source and tooling | `native/windows/src/ScreenFix.App/Resources/ScreenFixAppIcon.svg`, `native/windows/src/ScreenFix.App/Resources/ScreenFix.ico`, `native/windows/scripts/build-app-icon.sh`, `native/windows/scripts/icon_ico.py`, `native/windows/scripts/test-build-app-icon.sh` | Generate, pack, inspect, and validate the canonical nine-frame ICO. |
| Runtime icon use | `native/windows/src/ScreenFix.App/ScreenFix.App.csproj`, `native/windows/src/ScreenFix.App/Runtime/TrayIconLoader.cs`, `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`, `native/windows/tests/ScreenFix.Windows.Tests/TrayIconLoaderTests.cs` | Feed one ICO to MSBuild and the tray, preserve resource lifetime, and dispose in order. |
| Package assertions | `native/windows/scripts/assert-win-x64-package.ps1`, `native/windows/scripts/test-assert-win-x64-package.ps1`, `native/windows/scripts/test-windows-native.ps1`, `native/windows/scripts/publish-win-x64.ps1`, `native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs` | Check the managed ICO bytes and native PE icon resources independently after single-file publish. |
| Collaborator docs | `README.md` | Add only the new Windows verification and icon-regeneration commands. |

## Task 1: Land success-oriented placement regressions and Windows CI

**Owner:** One test/CI worker owns only the four files below. It must not edit production placement code.

**Files:**
- Create: `.github/workflows/windows-native.yml`
- Modify: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.App.Tests/NativeWindowPlacementTests.cs`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/WindowNativePlacementTests.cs`

- [ ] **Step 1: Link only the native placement types into the portable app test assembly**

Add this item to `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj` beside the existing linked production sources:

```xml
<Compile Include="../../src/ScreenFix.App/Interop/NativeTypes.cs" Link="Interop/NativeTypes.cs" />
```

Do not link `WindowNative.cs`; the portable test needs the ABI declaration, not Windows calls.

- [ ] **Step 2: Add the portable ABI success test**

Create `native/windows/tests/ScreenFix.App.Tests/NativeWindowPlacementTests.cs`:

```csharp
using System.Runtime.InteropServices;
using ScreenFix.App.Interop;

namespace ScreenFix.App.Tests;

public sealed class NativeWindowPlacementTests
{
    [Fact]
    public void WindowsAbiIsExactlyFortyFourBytes()
    {
        Assert.Equal(44, Marshal.SizeOf<NativeWindowPlacement>());
    }
}
```

- [ ] **Step 3: Run the portable test and record the root-cause RED**

Run with any available pinned SDK, for example:

```bash
SCREENFIX_DOTNET=/private/tmp/screenfix-dotnet10.469wuK/sdk/dotnet
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~NativeWindowPlacementTests
```

Expected: FAIL, with expected `44` and actual `60`. This is the portable proof that the trailing field breaks the Windows ABI.

- [ ] **Step 4: Add the Windows-native round-trip test without changing its success expectation later**

Create `native/windows/tests/ScreenFix.Windows.Tests/WindowNativePlacementTests.cs` with one focused test named `MaximizedWindow_RestoresAndMovesAcrossThreads`. Implement these exact behaviors:

1. Start a dedicated `Thread`, call `SetApartmentState(ApartmentState.STA)`, construct a normal resizable top-level WinForms `Form`, show it, and keep `Application.Run(form)` pumping messages until teardown.
2. Publish the handle through a `TaskCompletionSource<nint>` and bound every wait to 15 seconds so CI cannot hang.
3. On the owner thread, maximize the probe with `WindowState = FormWindowState.Maximized`; from the xUnit thread, wait until `((IWindowNativeQuery)native).IsZoomed(handle)` is true.
4. Call production `WindowNative.TryGetThreadProcessId`, create the current `WindowIdentity`, and then exercise production `TryGetPlacement`, `TrySetPlacement`, and `TrySetFrame` from the xUnit thread.
5. Restore by copying the returned placement with `AsyncWindowPlacement` and `ShowNoActivate`, exactly as `WindowCorrector` does. Apply a known integer `NativeWindowFrame` wholly inside `Screen.PrimaryScreen.WorkingArea` with `NoActivate | NoZOrder | NoOwnerZOrder | AsyncWindowPosition`.
6. Immediately after each false production call, capture `Marshal.GetLastPInvokeError()` and include the operation name and error in the `Assert.True` message. Do not assert that a particular get or set call must fail, and do not assert a fixed Win32 error number.
7. Poll until the window is no longer zoomed and `TryGetOuterFrame` equals the target exactly. Report the last observed zoom state and rectangle on timeout.
8. In `finally`, post teardown to the owner thread, let `Application.Run` exit, join the thread with a timeout, and surface any owner-thread exception.

Use a small private `StaProbeWindow` helper in this test file only. Do not add test hooks to production.

- [ ] **Step 5: Compile the Windows-native test on macOS**

Run:

```bash
"$SCREENFIX_DOTNET" build native/windows/tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj -c Release
```

Expected: build succeeds with zero warnings and zero errors. Execution is intentionally deferred to Windows.

- [ ] **Step 6: Add the minimal Windows workflow before fixing production**

Create `.github/workflows/windows-native.yml` with this baseline. Keep the invocation of `test-windows-native.ps1` unchanged after the ABI fix so the same success-oriented native test changes from RED to GREEN:

```yaml
name: Windows native

on:
  push:
    paths:
      - ".github/workflows/windows-native.yml"
      - "global.json"
      - "native/windows/**"
  pull_request:
    paths:
      - ".github/workflows/windows-native.yml"
      - "global.json"
      - "native/windows/**"
  workflow_dispatch:

permissions: {}

concurrency:
  group: windows-native-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: windows-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-dotnet@v6
        with:
          dotnet-version: 10.0.100
      - name: Restore
        run: dotnet restore native\windows\ScreenFix.slnx
      - name: Run Windows native tests
        shell: pwsh
        run: native\windows\scripts\test-windows-native.ps1
      - name: Run portable Windows tests
        run: dotnet test native\windows\ScreenFix.slnx -c Release --no-restore
      - name: Run package assertion regressions
        shell: pwsh
        run: native\windows\scripts\test-assert-win-x64-package.ps1
      - name: Publish and assert win-x64 package
        shell: pwsh
        run: native\windows\scripts\publish-win-x64.ps1
```

The workflow deliberately runs the native test before other expected failures so the Windows log captures the actual production placement boundary that refused the operation.

- [ ] **Step 7: Commit and push the RED regressions**

```bash
git add .github/workflows/windows-native.yml \
  native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj \
  native/windows/tests/ScreenFix.App.Tests/NativeWindowPlacementTests.cs \
  native/windows/tests/ScreenFix.Windows.Tests/WindowNativePlacementTests.cs
git commit -m "test: reproduce Windows maximize placement failure"
git push -u origin fix/windows-icons-maximize
```

- [ ] **Step 8: Observe the real Windows RED before touching production**

```bash
SCREENFIX_RUN_ID="$(gh run list --workflow windows-native.yml --branch fix/windows-icons-maximize --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$SCREENFIX_RUN_ID" --exit-status
```

Expected: workflow fails in `Run Windows native tests`. Preserve the log showing which production operation returned false and its last P/Invoke error. The test expectation remains full success; do not edit it in Task 2.

## Task 2: Correct the `WINDOWPLACEMENT` ABI and nothing else

**Owner:** One interop worker owns only the four files below. It must not change workflow or success-test expectations.

**Files:**
- Modify: `native/windows/src/ScreenFix.App/Interop/NativeTypes.cs`
- Modify: `native/windows/src/ScreenFix.App/Interop/WindowNative.cs`
- Modify: `native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/WindowCorrectorTests.cs`

- [ ] **Step 1: Confirm the only non-native field and its managed copies**

Run:

```bash
rg -n "DeviceRectangle" native/windows
```

Expected: occurrences only in `NativeTypes.cs`, `WindowNative.cs`, `WindowCorrector.cs`, and the one placement fixture in `WindowCorrectorTests.cs`. If any new occurrence exists, stop and account for it before editing.

- [ ] **Step 2: Remove the trailing native field**

Change `NativeWindowPlacement` so it ends at `NormalPosition`:

```csharp
[StructLayout(LayoutKind.Sequential)]
internal struct NativeWindowPlacement
{
    internal uint Length;
    internal uint Flags;
    internal uint ShowCommand;
    internal NativePoint MinimizedPosition;
    internal NativePoint MaximizedPosition;
    internal NativeRect NormalPosition;
}
```

Keep both `Length = (uint)Marshal.SizeOf<NativeWindowPlacement>()` assignments unchanged.

- [ ] **Step 3: Remove the field from the managed DTO, mappings, and fixture**

Make `WindowPlacementData` end at `NormalPosition`:

```csharp
public readonly record struct WindowPlacementData(
    uint Flags,
    uint ShowCommand,
    NativeWindowPoint MinimizedPosition,
    NativeWindowPoint MaximizedPosition,
    NativeWindowRectangle NormalPosition);
```

Delete only the `DeviceRectangle` argument in `ToPlacementData`, the `DeviceRectangle` initializer in `ToNativePlacement`, and the last rectangle supplied by `Maximized_RestoresWithoutActivationBeforeScreenCoordinateWrite`. Do not alter `TryRestoreWithoutActivation`, eligibility, frame calculation, or write flags.

- [ ] **Step 4: Prove the portable ABI and correction policy are GREEN**

Run one focused test at a time:

```bash
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~NativeWindowPlacementTests
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowCorrectorTests.Maximized
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter "FullyQualifiedName~WindowEligibilityTests.IsEligible_RejectsBorderlessFullScreenWindow|FullyQualifiedName~WindowEligibilityTests.IsEligible_AcceptsMaximizedOrdinaryWindowFacts"
```

Expected: all pass; the ABI test now reports exactly 44 bytes. The full-screen policy tests pass without production policy edits.

- [ ] **Step 5: Prove the complete local portable suites remain GREEN**

```bash
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release
"$SCREENFIX_DOTNET" build native/windows/tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj -c Release
```

Expected: both test projects pass and the Windows-only tests compile cleanly.

- [ ] **Step 6: Commit the minimal ABI fix**

```bash
git add native/windows/src/ScreenFix.App/Interop/NativeTypes.cs \
  native/windows/src/ScreenFix.App/Interop/WindowNative.cs \
  native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs \
  native/windows/tests/ScreenFix.App.Tests/WindowCorrectorTests.cs
git commit -m "fix: correct Windows placement ABI"
git push
```

- [ ] **Step 7: Observe the unchanged Windows regression turn GREEN**

```bash
SCREENFIX_RUN_ID="$(gh run list --workflow windows-native.yml --branch fix/windows-icons-maximize --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$SCREENFIX_RUN_ID" --exit-status
```

Expected: the workflow passes, including the unchanged `MaximizedWindow_RestoresAndMovesAcrossThreads` test. Save the run URL as Windows-native proof.

## Task 3: Generate and validate the canonical Screen Patch ICO

**Owner:** One asset-tooling worker owns only the five files below. It must not edit project files or application runtime code.

**Files:**
- Create: `native/windows/src/ScreenFix.App/Resources/ScreenFixAppIcon.svg`
- Create: `native/windows/src/ScreenFix.App/Resources/ScreenFix.ico`
- Create: `native/windows/scripts/build-app-icon.sh`
- Create: `native/windows/scripts/icon_ico.py`
- Create: `native/windows/scripts/test-build-app-icon.sh`

- [ ] **Step 1: Write a failing black-box generator regression**

Create executable `native/windows/scripts/test-build-app-icon.sh`. It must:

- create a temporary directory with `mktemp -d` and clean it with `trap`;
- invoke `build-app-icon.sh` with an explicit temporary output path;
- call `python3 icon_ico.py validate` on the result and require exactly `16 20 24 32 40 48 64 128 256`;
- require a regular nonempty result with mode `0644`;
- reject a directory target and a symbolic-link target without writing through either;
- extract 256-, 32-, and 16-pixel PNG frames with `icon_ico.py extract` and let `sips -g pixelWidth -g pixelHeight` assert their dimensions; and
- validate the committed `Resources/ScreenFix.ico` separately.

Use POSIX arrays only where Bash 3.2 supports them; do not use `mapfile`, associative arrays, GNU-only `stat`, or `readlink -f`.

- [ ] **Step 2: Run the test and verify it is RED**

```bash
native/windows/scripts/test-build-app-icon.sh
```

Expected: FAIL because `build-app-icon.sh`, `icon_ico.py`, or the canonical ICO does not yet exist. This is the generator regression, not a hand-authored fixture test.

- [ ] **Step 3: Add the exact approved SVG source**

Create the `Resources` directory and `ScreenFixAppIcon.svg` with transparent `viewBox="0 0 220 220"` artwork exactly matching the approved spec:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 220">
  <defs>
    <linearGradient id="background" gradientUnits="userSpaceOnUse" x1="28" y1="18" x2="192" y2="207">
      <stop offset="0" stop-color="#FFB23E"/>
      <stop offset="0.54" stop-color="#F46744"/>
      <stop offset="1" stop-color="#A92C4D"/>
    </linearGradient>
  </defs>
  <rect x="10" y="10" width="200" height="200" rx="45" fill="url(#background)"/>
  <rect x="38" y="54" width="144" height="103" rx="18" fill="#FFF7E8"/>
  <rect x="50" y="67" width="120" height="77" rx="9" fill="#FFD8A0"/>
  <path d="M57 77 L91 134" fill="none" stroke="#FF9F61" stroke-width="8" stroke-linecap="round" opacity="0.8"/>
  <path d="M133 77 L163 126" fill="none" stroke="#FF9F61" stroke-width="8" stroke-linecap="round" opacity="0.8"/>
  <rect x="96" y="54" width="28" height="103" rx="8" fill="#27212B"/>
  <path d="M88 172 H132" fill="none" stroke="#FFF5E5" stroke-width="10" stroke-linecap="round"/>
  <path d="M110 158 V172" fill="none" stroke="#FFF5E5" stroke-width="10" stroke-linecap="round"/>
  <g fill="none" stroke="#F7C46C" stroke-width="4" stroke-linecap="round">
    <path d="M103 75 H117"/><path d="M103 94 H117"/>
    <path d="M103 113 H117"/><path d="M103 132 H117"/>
  </g>
</svg>
```

- [ ] **Step 4: Implement the standard-library ICO packer and validator**

Create `native/windows/scripts/icon_ico.py` with three narrow commands:

```text
pack OUTPUT SIZE=PNG [SIZE=PNG ...]
validate ICO
extract ICO OUTPUT_DIRECTORY SIZE [SIZE ...]
```

Use only `argparse`, `pathlib`, `struct`, and other Python standard-library modules. The validator must parse `ICONDIR` and every 16-byte `ICONDIRENTRY`, then require:

- reserved `0`, type `1`, count `9`;
- ascending frames exactly `16, 20, 24, 32, 40, 48, 64, 128, 256` (`0` width/height encodes 256);
- planes `1`, bit count `32`;
- every offset and length fully inside the file and after the directory;
- no overlapping or duplicate payload ranges;
- a PNG signature for every payload; and
- IHDR width and height equal to the directory frame size.

`pack` must validate all input PNGs before writing the ICO and then validate its candidate output. `extract` must reuse the same parser rather than duplicate ICO parsing. On success, `validate` prints the space-separated size list so the shell regression can assert it exactly.

- [ ] **Step 5: Implement the Bash 3.2 generator with safe publication**

Create executable `native/windows/scripts/build-app-icon.sh` with this contract:

```text
build-app-icon.sh [OUTPUT]
```

Default `OUTPUT` is `native/windows/src/ScreenFix.App/Resources/ScreenFix.ico`. The script must:

1. resolve paths from `BASH_SOURCE[0]`, not the caller's directory;
2. require `sips` and `python3`;
3. reject an existing directory or symbolic link at `OUTPUT`;
4. use `mktemp -d` plus a cleanup trap;
5. call `sips -s format png --resampleHeightWidth 1024 1024` directly on the SVG;
6. create separate PNGs at 16, 20, 24, 32, 40, 48, 64, 128, and 256 with direct `sips` calls;
7. invoke `icon_ico.py pack` into a candidate file in the output directory;
8. invoke `icon_ico.py validate` and require the exact frame list;
9. set mode `0644`; and
10. atomically replace only a regular output file after every check succeeds.

Do not leave PNGs or candidate ICOs outside the temporary directory.

- [ ] **Step 6: Generate the committed ICO and make the regression GREEN**

```bash
native/windows/scripts/build-app-icon.sh
native/windows/scripts/test-build-app-icon.sh
python3 native/windows/scripts/icon_ico.py validate native/windows/src/ScreenFix.App/Resources/ScreenFix.ico
```

Expected: both scripts exit 0; validation prints `16 20 24 32 40 48 64 128 256`; the canonical ICO is a regular nonempty `0644` file.

- [ ] **Step 7: Inspect the small and large frames visually**

```bash
SCREENFIX_ICON_PREVIEW="$(mktemp -d)"
python3 native/windows/scripts/icon_ico.py extract \
  native/windows/src/ScreenFix.App/Resources/ScreenFix.ico \
  "$SCREENFIX_ICON_PREVIEW" 256 32 16
open "$SCREENFIX_ICON_PREVIEW"
```

Expected: at 256, 32, and 16 pixels the center dark mask remains distinct, the display silhouette remains recognizable, and no background box was introduced around the rounded artwork. Remove only the printed temporary preview directory after inspection.

- [ ] **Step 8: Prove regeneration does not leave an unexplained asset diff**

Run the generator once more, then inspect:

```bash
native/windows/scripts/build-app-icon.sh
git diff --stat -- native/windows/src/ScreenFix.App/Resources/ScreenFix.ico
```

Expected: no diff when rerun on the same host/toolchain. Do not make byte identity across different macOS `sips` versions a CI requirement; the validator and frame checks are the cross-version contract.

- [ ] **Step 9: Commit the source, tooling, and generated asset together**

```bash
git add native/windows/src/ScreenFix.App/Resources/ScreenFixAppIcon.svg \
  native/windows/src/ScreenFix.App/Resources/ScreenFix.ico \
  native/windows/scripts/build-app-icon.sh \
  native/windows/scripts/icon_ico.py \
  native/windows/scripts/test-build-app-icon.sh
git commit -m "build: add Windows Screen Patch icon"
```

## Task 4: Use the same ICO for the apphost and tray

**Owner:** One runtime worker owns only the four production/test files below. It consumes Task 3's committed ICO and must not regenerate or replace it.

**Files:**
- Modify: `native/windows/src/ScreenFix.App/ScreenFix.App.csproj`
- Create: `native/windows/src/ScreenFix.App/Runtime/TrayIconLoader.cs`
- Modify: `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/TrayIconLoaderTests.cs`

- [ ] **Step 1: Write loader tests before adding the loader or resource metadata**

Create `TrayIconLoaderTests.cs` with three Windows tests:

```text
BrandedIcon_HasStableManifestNameAndRequestedSmallSize
BrandedIcon_RemainsUsableAfterResourceStreamAndSourceIconClose
MissingResource_ReturnsIndependentOwnedFallback
```

The first two call an internal overload that accepts a resource name and requested `Size(16, 16)` so selection is deterministic; assert `Width`, `Height`, and a nonzero `Handle` after the method has returned. Also require `typeof(TrayIconLoader).Assembly.GetManifestResourceNames()` to contain exactly `ScreenFix.App.Resources.ScreenFix.ico`.

The fallback test loads two missing resource names, disposes the first result, and proves the second still has a valid handle. This prevents returning the shared `SystemIcons.Application` instance directly.

- [ ] **Step 2: Run the tests and record the RED**

On Windows:

```powershell
dotnet test native\windows\tests\ScreenFix.Windows.Tests\ScreenFix.Windows.Tests.csproj -c Release --filter FullyQualifiedName~TrayIconLoaderTests
```

Expected: compile or test failure because `TrayIconLoader` and the stable resource do not exist.

- [ ] **Step 3: Configure one physical ICO for both consumers**

Add these properties/items to `ScreenFix.App.csproj`:

```xml
<ApplicationIcon>Resources\ScreenFix.ico</ApplicationIcon>
```

```xml
<EmbeddedResource Include="Resources\ScreenFix.ico" LogicalName="ScreenFix.App.Resources.ScreenFix.ico" />
```

Do not copy a second ICO and do not use a generated intermediate as either input.

- [ ] **Step 4: Implement the narrow tray loader**

Create `Runtime/TrayIconLoader.cs` as a short internal static class with:

```csharp
internal const string ResourceName = "ScreenFix.App.Resources.ScreenFix.ico";

internal static Icon Load() =>
    Load(ResourceName, SystemInformation.SmallIconSize);

internal static Icon Load(string resourceName, Size requestedSize)
```

In the overload, open `typeof(TrayIconLoader).Assembly.GetManifestResourceStream(resourceName)`, construct `new Icon(stream, requestedSize)`, clone it with `(Icon)source.Clone()`, then let both source and stream close before returning the clone. Catch only resource/icon load failures that justify the runtime fallback (`ArgumentException`, `ExternalException`, `IOException`, or a missing stream), and return `(Icon)SystemIcons.Application.Clone()`. Do not catch process-corruption or arbitrary application exceptions.

- [ ] **Step 5: Assign and dispose the owned icon in strict order**

In `ScreenFixApplicationContext.InitializeTrayAndRuntime`:

1. call `var ownedIcon = TrayIconLoader.Load()`;
2. assign `ownedIcon` to the new `NotifyIcon` instead of `SystemIcons.Application`; and
3. in the existing `OwnTrayIcon` cleanup action, set `Visible = false`, dispose the `NotifyIcon`, dispose `ownedIcon`, then dispose `uiBridge`.

Use nested `try/finally` inside the cleanup action so a failing earlier dispose cannot skip a later owned resource. Keep the existing application-lifetime order: menu cleanup runs before tray cleanup, and the `NotifyIcon` is destroyed before its icon handle.

- [ ] **Step 6: Make loader and existing lifetime tests GREEN**

On Windows:

```powershell
dotnet test native\windows\tests\ScreenFix.Windows.Tests\ScreenFix.Windows.Tests.csproj -c Release --filter FullyQualifiedName~TrayIconLoaderTests
dotnet test native\windows\tests\ScreenFix.App.Tests\ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~LifecycleTests
```

Expected: loader tests pass; existing lifecycle tests still prove menu cleanup precedes the combined tray cleanup. Review the application cleanup action to confirm `NotifyIcon.Dispose()` precedes `ownedIcon.Dispose()`.

- [ ] **Step 7: Verify the production call uses the Windows small-icon metric**

```bash
rg -n "SystemInformation.SmallIconSize|SystemIcons.Application|ApplicationIcon|LogicalName" native/windows/src/ScreenFix.App
```

Expected: production `Load()` requests `SystemInformation.SmallIconSize`; `SystemIcons.Application` appears only in the owned fallback; one csproj path supplies both `ApplicationIcon` and the stable embedded resource.

- [ ] **Step 8: Commit the runtime icon integration**

```bash
git add native/windows/src/ScreenFix.App/ScreenFix.App.csproj \
  native/windows/src/ScreenFix.App/Runtime/TrayIconLoader.cs \
  native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs \
  native/windows/tests/ScreenFix.Windows.Tests/TrayIconLoaderTests.cs
git commit -m "feat: brand Windows executable and tray"
```

## Task 5: Assert both icon publication paths in the single-file package

**Owner:** One packaging worker owns only the five files below. It must not change icon artwork, loader behavior, or placement code.

**Files:**
- Modify: `native/windows/scripts/assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/test-assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/test-windows-native.ps1`
- Modify: `native/windows/scripts/publish-win-x64.ps1`
- Create: `native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs`

- [ ] **Step 1: Add a RED managed-resource assertion regression**

Extend `test-assert-win-x64-package.ps1` to locate the canonical ICO at `../src/ScreenFix.App/Resources/ScreenFix.ico`. Preserve every existing DOS, PE, machine, subsystem, extra-file, and empty-file negative case.

Adapt the current synthetic positive PE fixture by appending the exact canonical ICO bytes after its structural PE bytes. Add a separate negative fixture that is otherwise identical but omits or mutates one canonical ICO byte. Run the assertion against that negative fixture before modifying the assertion script.

Expected RED: the iconless or mismatched synthetic package is accepted, proving the existing package assertion does not validate the managed tray resource.

- [ ] **Step 2: Require the exact canonical managed ICO byte sequence**

Update `assert-win-x64-package.ps1` to accept an optional `CanonicalIcon` path whose default resolves from `$PSScriptRoot`. Validate it is one regular nonempty file. Add a small exact byte-sequence matcher and require the full canonical ICO byte sequence to occur in `ScreenFix.exe`; a header-only or partial ICO match is insufficient.

If direct PowerShell byte scanning would become quadratic, compile a short in-memory C# helper with `Add-Type` whose only public method performs a linear exact byte-pattern search. Keep it local to this assertion script; do not add a portable PE parser.

Use one stable diagnostic for the negative test:

```text
executable does not contain the canonical managed ScreenFix icon
```

- [ ] **Step 3: Make the PowerShell assertion regressions GREEN on Windows**

```powershell
native\windows\scripts\test-assert-win-x64-package.ps1
```

Expected: `package assertion regression tests passed`. The synthetic positive still exercises DOS/PE/machine/subsystem parsing and now contains the canonical managed bytes; the independent negative proves those bytes are required.

- [ ] **Step 4: Add native PE resource tests in a separate class**

Create `PublishedExecutableIconTests.cs`; do not mix it into placement tests. Read the published executable path from a required `SCREENFIX_PUBLISHED_EXE` environment variable and the canonical ICO path from required `SCREENFIX_CANONICAL_ICO`.

Implement these focused tests:

```text
PublishedExecutable_ContainsCanonicalManagedIconBytes
PublishedExecutable_ContainsEveryNativeIconFrame
```

The first performs an exact full-byte-sequence search, independent of native resource enumeration. The second must:

1. call `LoadLibraryExW(executable, 0, LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE)`;
2. call `EnumResourceNamesW` for `RT_GROUP_ICON` (`MAKEINTRESOURCE(14)`) and retain every discovered string or integer name;
3. pass each discovered name unchanged to `FindResourceW`, rather than assuming resource ID `1`;
4. load and parse each compact `GRPICONDIR`/`GRPICONDIRENTRY` block;
5. require the union of group dimensions to equal `16, 20, 24, 32, 40, 48, 64, 128, 256`; and
6. for every group entry, call `FindResourceW` with its referenced icon ID and `RT_ICON` (`MAKEINTRESOURCE(3)`), requiring a nonempty resource.

Always call `FreeLibrary` in `finally`, retain the enumeration delegate with `GC.KeepAlive`, and include the executable path/resource name in assertion diagnostics. Parse the canonical ICO directory only to obtain expected dimensions; do not implement PE section/RVA parsing.

- [ ] **Step 5: Make the native resource test prove a meaningful negative control**

Publish once to a temporary directory while overriding the apphost icon:

```powershell
dotnet publish native\windows\src\ScreenFix.App\ScreenFix.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:PublishTrimmed=false -p:UseAppHost=true -p:ApplicationIcon= `
  -o $env:RUNNER_TEMP\screenfix-no-app-icon
```

Run `PublishedExecutableIconTests` with its two environment variables pointed at that executable and the canonical ICO.

Expected: the managed-byte test passes, while the native-resource test fails because no valid Screen Patch `RT_GROUP_ICON`/`RT_ICON` set exists. This distinguishes the tray resource from the Explorer resource without a synthetic PE resource writer.

- [ ] **Step 6: Teach the native test script to run published-executable tests only when requested**

Add an optional `PublishedExecutable` parameter to `test-windows-native.ps1`.

- Its baseline call continues to build and run all Windows tests except `PublishedExecutableIconTests`, preserving Task 1's workflow command.
- When `PublishedExecutable` is supplied, validate it as a file, set `SCREENFIX_PUBLISHED_EXE` and `SCREENFIX_CANONICAL_ICO` for a second filtered `dotnet test --no-build` invocation, then restore the caller's prior environment values in `finally`.
- The placement test invocation and expectations remain unchanged.

This separation prevents the early native step from depending on an executable that has not been published yet.

- [ ] **Step 7: Assert the real single-file publish through both paths**

After the existing `assert-win-x64-package.ps1` call in `publish-win-x64.ps1`, invoke:

```powershell
& (Join-Path $PSScriptRoot "test-windows-native.ps1") `
    -PublishedExecutable (Join-Path $output "ScreenFix.exe")
```

Keep `PublishSingleFile=true`, self-contained `win-x64`, `UseAppHost=true`, and the exactly-one-file package contract unchanged.

- [ ] **Step 8: Publish and make every package check GREEN on Windows**

```powershell
native\windows\scripts\test-assert-win-x64-package.ps1
native\windows\scripts\publish-win-x64.ps1
```

Expected: synthetic regressions pass; publish produces exactly one nonempty AMD64 GUI `ScreenFix.exe`; the full canonical ICO bytes are present; at least one enumerated `RT_GROUP_ICON` references all nine required nonempty `RT_ICON` frames.

- [ ] **Step 9: Commit package validation**

```bash
git add native/windows/scripts/assert-win-x64-package.ps1 \
  native/windows/scripts/test-assert-win-x64-package.ps1 \
  native/windows/scripts/test-windows-native.ps1 \
  native/windows/scripts/publish-win-x64.ps1 \
  native/windows/tests/ScreenFix.Windows.Tests/PublishedExecutableIconTests.cs
git commit -m "test: verify Windows icons in published executable"
git push
```

- [ ] **Step 10: Require the unchanged workflow entry points to pass**

```bash
SCREENFIX_RUN_ID="$(gh run list --workflow windows-native.yml --branch fix/windows-icons-maximize --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$SCREENFIX_RUN_ID" --exit-status
```

Expected: GREEN for native tests, portable tests, PowerShell assertion regressions, and final single-file publish/assert.

## Task 6: Document only the new collaborator commands

**Owner:** One documentation worker owns only `README.md`.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Confirm the command-discovery gap is real**

```bash
rg -n "publish-win-x64|test-windows-native|build-app-icon" README.md
```

Expected: no matches. This justifies a small documentation change; do not create a separate Windows README.

- [ ] **Step 2: Add concise Windows collaborator commands**

Under `## Collaborating`, add only:

````markdown
On Windows, run the native tests and publish the asserted single-file x64 app:

```powershell
native\windows\scripts\test-windows-native.ps1
native\windows\scripts\publish-win-x64.ps1
```

On macOS, regenerate and verify the committed Windows icon after editing its SVG:

```bash
native/windows/scripts/build-app-icon.sh
native/windows/scripts/test-build-app-icon.sh
```
````

Keep the existing macOS packaging and Lua commands. Do not add implementation history or repeat the artwork specification.

- [ ] **Step 3: Inspect and commit the concise documentation diff**

```bash
git diff --check
git diff -- README.md
git add README.md
git commit -m "docs: add Windows verification commands"
```

Expected: only the four discoverability commands and their short introductions are added.

## Task 7: Full verification, manual acceptance, reviews, and pull request

**Owner:** The orchestrator owns verification and GitHub operations. No feature worker edits files during this task unless a reviewer identifies a concrete defect.

**Files:**
- Verify: all files changed by Tasks 1-6
- Do not create additional production files unless a failing check proves they are required

- [ ] **Step 1: Re-run the icon generator regression on macOS**

```bash
native/windows/scripts/test-build-app-icon.sh
native/windows/scripts/build-app-icon.sh
git diff --exit-code -- native/windows/src/ScreenFix.App/Resources/ScreenFix.ico
```

Expected: PASS and no regenerated ICO diff on the same host/toolchain.

- [ ] **Step 2: Run the full portable Windows test suites with the isolated SDK if available**

```bash
SCREENFIX_DOTNET=/private/tmp/screenfix-dotnet10.469wuK/sdk/dotnet
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release
"$SCREENFIX_DOTNET" test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release
"$SCREENFIX_DOTNET" build native/windows/tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj -c Release
```

Expected: all portable tests pass and Windows tests compile with zero warnings/errors. If that example SDK directory is absent, install/use the pinned `10.0.100` SDK elsewhere; do not edit `global.json` or commit a machine path.

- [ ] **Step 3: Run unrelated local regressions**

```bash
native/macos/scripts/run-tests.sh
lua tests/run.lua
```

Expected: the complete native macOS and Lua suites pass.

- [ ] **Step 4: Check scope and repository hygiene**

```bash
git diff --check main...HEAD
git status --short
git diff --stat main...HEAD
rg -n "DeviceRectangle|SystemIcons.Application" native/windows
```

Expected: no whitespace errors; no generated preview/publish/temp files; `DeviceRectangle` is absent; `SystemIcons.Application` appears only in the loader fallback; the diff is limited to the approved Windows feature, workflow, plan/spec, and concise README changes.

- [ ] **Step 5: Push and require the Windows workflow to pass at HEAD**

```bash
git push
SCREENFIX_RUN_ID="$(gh run list --workflow windows-native.yml --branch fix/windows-icons-maximize --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$SCREENFIX_RUN_ID" --exit-status
```

Expected: the final Windows run is GREEN. Record the run URL and confirm it used .NET `10.0.100`, `actions/checkout@v7`, and `actions/setup-dotnet@v6`.

- [ ] **Step 6: Perform Windows manual acceptance**

On a normal Windows x64 desktop, run the asserted `ScreenFix.exe` and check one item at a time:

1. The Screen Patch appears in the notification area at normal and high DPI.
2. Explorer and an executable shortcut show the same Screen Patch artwork.
3. An ordinary window crossing a mask settles entirely into the selected safe side after Windows-key-Up.
4. The same ordinary window settles into the safe side after the maximize button.
5. Windows-key-Left and Windows-key-Right still fit the same safe region.
6. Borderless or F11 full screen remains untouched.

Record Windows version, DPI, and pass/fail results in the PR. A visual icon check is not replaced by structural package tests.

- [ ] **Step 7: Request three independent reviews**

Use `superpowers:requesting-code-review` and dispatch focused reviewers for:

- correctness: Windows ABI, cross-thread message pumping, last-error capture, PE enumeration, and package assertions;
- maintainability: short loader/parser functions, resource ownership, Bash 3.2 compatibility, PowerShell failure behavior; and
- conventions/spec: exact artwork/frame sizes, unchanged policy, file scope, workflow permissions/concurrency/action versions.

Fix every confirmed Important or Critical finding in a small commit, then rerun the focused test plus the full affected suite. Re-request review of any corrected area.

- [ ] **Step 8: Run fresh completion evidence after all review fixes**

Repeat Steps 1-5 at the final commit. Do not rely on older output. Confirm `git status --short` is empty before opening the PR.

- [ ] **Step 9: Open the focused Windows pull request**

```bash
gh pr create \
  --base main \
  --head fix/windows-icons-maximize \
  --title "Fix Windows icons and maximized window correction" \
  --body-file /tmp/screenfix-windows-pr-body.md
```

The PR body must summarize the 44-byte ABI correction, the one-ICO dual use, and independent managed/native package checks. Include exact local commands, the GREEN Windows workflow URL, and manual acceptance results. Link the relevant GitHub issue if one exists; do not claim borderless/F11 behavior changed.

- [ ] **Step 10: Verify the remote handoff**

```bash
gh pr view --json number,url,state,headRefName,baseRefName,statusCheckRollup
git status --short
```

Expected: one OPEN PR from `fix/windows-icons-maximize` to `main`, all required checks successful, and a clean worktree.
