# Windows EXE Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compilable .NET 10 Windows foundation with tested ScreenFix geometry and configuration, a minimal tray process, and an asserted self-contained single `ScreenFix.exe` for `win-x64`.

**Architecture:** Keep deterministic behavior in a platform-independent `ScreenFix.Core` library and keep WinForms/Win32 dependencies in a thin `ScreenFix.App`. Phase 1 does not render masks or move windows; it locks the pure geometry, configuration, menu-state, and ownership portions of the shared contract into tests, proves the foundation tray lifecycle, and produces the exact package shape required by later phases.

**Tech Stack:** .NET 10 LTS, C# 14, WinForms, System.Text.Json, xUnit, PowerShell 7, `dotnet publish`

---

## Scope and file structure

Read first:

- `docs/screenfix-behavior-contract.md`
- `docs/superpowers/specs/2026-08-15-native-packaging-design.md`

Create only this Phase 1 structure:

```text
global.json
native/windows/
├── .gitignore
├── Directory.Build.props
├── ScreenFix.slnx
├── src/
│   ├── ScreenFix.Core/
│   │   ├── ScreenFix.Core.csproj
│   │   ├── Configuration/
│   │   │   ├── ConfigValidator.cs
│   │   │   ├── DefaultConfiguration.cs
│   │   │   ├── JsonConfigStore.cs
│   │   │   └── ScreenFixConfig.cs
│   │   ├── Geometry/
│   │   │   ├── CalibrationGeometry.cs
│   │   │   ├── GuardGeometry.cs
│   │   │   └── RectD.cs
│   │   └── Menu/
│   │       └── MenuState.cs
│   └── ScreenFix.App/
│       ├── Lifecycle/
│       │   ├── ResourceOwner.cs
│       │   └── SingleInstanceGate.cs
│       ├── Program.cs
│       ├── ScreenFix.App.csproj
│       ├── ScreenFixApplicationContext.cs
│       └── app.manifest
├── tests/
│   ├── ScreenFix.Core.Tests/
│   │   ├── ScreenFix.Core.Tests.csproj
│   │   ├── CalibrationGeometryTests.cs
│   │   ├── ConfigValidatorTests.cs
│   │   ├── DefaultConfigurationTests.cs
│   │   ├── GuardGeometryTests.cs
│   │   ├── JsonConfigStoreTests.cs
│   │   ├── MenuStateTests.cs
│   │   └── RectDTests.cs
│   └── ScreenFix.App.Tests/
│       ├── ScreenFix.App.Tests.csproj
│       └── LifecycleTests.cs
└── scripts/
    ├── assert-win-x64-package.ps1
    └── publish-win-x64.ps1
```

Do not add overlays, display enumeration, global hooks, Accessibility equivalents,
startup-at-login behavior, or macOS code in this phase. Disabled tray commands make
that boundary visible instead of pretending the display is protected. Held and
tap-move-tap gesture state, raw unsnapped gesture retention, transactional overlay/editor
ownership, runtime WinEvent correction, and display/power reconciliation remain explicit
Phase 2 or 3 work; Phase 1 tests only their pure geometry and reusable ownership inputs.

### Task 1: Scaffold the .NET 10 solution

**Files:**

- Create: `global.json`
- Create: `native/windows/Directory.Build.props`
- Create: `native/windows/.gitignore`
- Create: `native/windows/ScreenFix.slnx`
- Create: `native/windows/src/ScreenFix.Core/ScreenFix.Core.csproj`
- Create: `native/windows/src/ScreenFix.App/ScreenFix.App.csproj`
- Modify: `native/windows/src/ScreenFix.App/Program.cs`
- Create: `native/windows/src/ScreenFix.App/app.manifest`
- Create: `native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`

- [ ] **Step 1: Confirm the required stable SDK is available**

Run:

```bash
dotnet --list-sdks
```

Expected: at least one stable `10.0.x` SDK. Stop with the exact missing prerequisite if
none is installed; do not retarget an older framework.

- [ ] **Step 2: Select stable .NET 10 before running a template**

Create root `global.json` before invoking any template:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature",
    "allowPrerelease": false
  }
}
```

Then run:

```bash
dotnet --version
```

Expected: a stable `10.0.x` value with no prerelease suffix. This root pin applies to
every later repository-root `dotnet` command.

- [ ] **Step 3: Create the solution and portable project scaffolds from the repository root**

Run:

```bash
mkdir -p native/windows
dotnet new sln -n ScreenFix -o native/windows
dotnet new classlib -n ScreenFix.Core -o native/windows/src/ScreenFix.Core -f net10.0
dotnet new console -n ScreenFix.App -o native/windows/src/ScreenFix.App -f net10.0
dotnet new xunit -n ScreenFix.Core.Tests -o native/windows/tests/ScreenFix.Core.Tests -f net10.0
dotnet new xunit -n ScreenFix.App.Tests -o native/windows/tests/ScreenFix.App.Tests -f net10.0
dotnet sln native/windows/ScreenFix.slnx add native/windows/src/ScreenFix.Core/ScreenFix.Core.csproj
dotnet sln native/windows/ScreenFix.slnx add native/windows/src/ScreenFix.App/ScreenFix.App.csproj
dotnet sln native/windows/ScreenFix.slnx add native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj
dotnet sln native/windows/ScreenFix.slnx add native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj
dotnet add native/windows/src/ScreenFix.App/ScreenFix.App.csproj reference native/windows/src/ScreenFix.Core/ScreenFix.Core.csproj
dotnet add native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj reference native/windows/src/ScreenFix.Core/ScreenFix.Core.csproj
```

Expected: .NET 10 creates `ScreenFix.slnx`; all add/reference commands succeed.

- [ ] **Step 4: Configure a compile-safe WinForms shell**

Write `Directory.Build.props` with `LangVersion` `14.0`,
nullable and implicit usings enabled, warnings as errors, deterministic builds, and
`ContinuousIntegrationBuild` only when `CI` is true.

Remove template `Class1.cs`. Convert the console app project with these properties:

```xml
<OutputType>WinExe</OutputType>
<TargetFramework>net10.0-windows</TargetFramework>
<UseWindowsForms>true</UseWindowsForms>
<EnableWindowsTargeting>true</EnableWindowsTargeting>
<ApplicationHighDpiMode>PerMonitorV2</ApplicationHighDpiMode>
<AssemblyName>ScreenFix</AssemblyName>
<ApplicationManifest>app.manifest</ApplicationManifest>
```

Create `app.manifest` now with the exact execution-level declaration:

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

Replace the console template body with this compile-safe Phase 1 entry point; Task 7
will add the tray context later:

```csharp
using System.Windows.Forms;

namespace ScreenFix.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
    }
}
```

Ignore only `bin/`, `obj/`, and `artifacts/` under `native/windows`.

- [ ] **Step 5: Build the empty foundation**

Run:

```bash
dotnet restore native/windows/ScreenFix.slnx
dotnet build native/windows/ScreenFix.slnx -c Release --no-restore
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
```

Expected: build succeeds with zero warnings; both template tests pass. This path does
not require the WinForms template to be installed on a macOS development host.

- [ ] **Step 6: Commit the scaffold**

```bash
git add global.json native/windows
git commit -m "build: scaffold native Windows app"
```

### Task 2: Lock the rectangle and permanent-default contract

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Geometry/RectD.cs`
- Create: `native/windows/src/ScreenFix.Core/Configuration/ScreenFixConfig.cs`
- Create: `native/windows/src/ScreenFix.Core/Configuration/DefaultConfiguration.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/RectDTests.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/DefaultConfigurationTests.cs`
- Delete: template unit-test file

- [ ] **Step 1: Write failing rectangle and default tests**

Define tests before production types. Cover these exact oracles:

```csharp
Assert.False(new RectD(0, 0, 10, 10).Intersects(new RectD(10, 0, 5, 5)));
Assert.True(new RectD(0, 0, 10, 10).Intersects(new RectD(9, 9, 5, 5)));

var config = DefaultConfiguration.Create(
    new DisplayIdentity("display-1", "Ultrawide", 3440, 1440));
Assert.Equal(1, config.SchemaVersion);
Assert.True(config.Enabled);
Assert.Equal(3, config.Bands.Count);
Assert.Equal(1215d / 3440d, config.Bands[0].X);
Assert.Equal((1920d - 1215d) / 3440d, config.Bands[0].Width);
Assert.Equal(new[] { 0d, 0.34d, 0.73d }, config.Bands.Select(x => x.Y));
Assert.Equal(new[] { 0.34d, 0.39d, 0.27d }, config.Bands.Select(x => x.Height));
```

Also prove all three absolute bands on a 3440-wide display start at `1215` and end at
`1920`, and prove conversion adds a negative display origin.

- [ ] **Step 2: Run the focused tests to prove RED**

Run:

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter "FullyQualifiedName~RectDTests|FullyQualifiedName~DefaultConfigurationTests"
```

Expected: FAIL because `RectD`, configuration records, and `DefaultConfiguration` do not
exist.

- [ ] **Step 3: Add the minimal immutable core types**

Use these public shapes:

```csharp
public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool Intersects(RectD other) =>
        X < other.Right && other.X < Right && Y < other.Bottom && other.Y < Bottom;
}

public sealed record DisplayIdentity(string StableId, string Name, double Width, double Height);
public sealed record ScreenFixConfig(
    int SchemaVersion,
    bool Enabled,
    DisplayIdentity Display,
    IReadOnlyList<RectD> Bands);
```

`DefaultConfiguration.Create` must compute `1215d / 3440d` and
`(1920d - 1215d) / 3440d` in code. Add `RectD.ToAbsolute(RectD fullFrame)` using the
top-left contract; do not round in the core.

- [ ] **Step 4: Run the focused tests to prove GREEN**

Run the command from Step 2.

Expected: PASS with the exact 1215-to-1920 oracle.

- [ ] **Step 5: Commit the contract model**

```bash
git add native/windows/src/ScreenFix.Core native/windows/tests/ScreenFix.Core.Tests
git commit -m "feat: add native ScreenFix defaults"
```

### Task 3: Implement calibration hit, drag, and snapping geometry

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Geometry/CalibrationGeometry.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/CalibrationGeometryTests.cs`

- [ ] **Step 1: Write failing calibration geometry tests**

Create table-driven tests for:

- later band indices winning overlap hits;
- an 8-unit edge hit winning over a body hit;
- body dragging clamping every edge inside the display;
- left/right/top/bottom resize keeping the opposite edge fixed;
- 20-unit minimum width and height;
- a body edge snapping to each screen edge within 12 units;
- each left/right/top/bottom body edge snapping to each corresponding peer edge;
- each left/right/top/bottom resized edge snapping to a corresponding peer edge;
- exact 12-unit distance snapping inclusively and `12 + epsilon` not snapping;
- screen edges winning an equal-distance tie; and
- lower peer index winning an equal-distance peer tie.

Use the negative-origin display only for absolute conversion. `DragBand` and `SnapBand`
accept display-local deltas and normalized bands, matching the behavior contract.

- [ ] **Step 2: Run the calibration tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~CalibrationGeometryTests
```

Expected: FAIL because `CalibrationGeometry`, `DragPart`, `PointD`, and `EditorHit` do not
exist.

- [ ] **Step 3: Implement the smallest pure API**

Expose:

```csharp
public enum DragPart { Body, Left, Right, Top, Bottom }
public readonly record struct PointD(double X, double Y);
public readonly record struct EditorHit(int Index, DragPart Part);

public static EditorHit? HitTest(PointD point, IReadOnlyList<RectD> localBands, double handleSize);
public static RectD DragBand(RectD normalizedBand, DragPart part, PointD localDelta, RectD fullFrame, double minimumSize);
public static RectD SnapBand(RectD rawBand, int activeIndex, DragPart part,
    IReadOnlyList<RectD> bands, RectD fullFrame, double threshold);
```

Iterate hit-test bands from last to first, edges before bodies. Snap a copied candidate,
validate finite inputs, retain positive size, and compare native-unit distances with a
small floating tolerance. Do not store gesture state in this pure class; the Phase 2
editor must retain and pass the raw unsnapped band separately.

- [ ] **Step 4: Run focused and full core tests**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~CalibrationGeometryTests
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release
```

Expected: both commands PASS with zero warnings.

- [ ] **Step 5: Commit calibration geometry**

```bash
git add native/windows/src/ScreenFix.Core/Geometry native/windows/tests/ScreenFix.Core.Tests/CalibrationGeometryTests.cs
git commit -m "feat: add Windows calibration geometry"
```

### Task 4: Implement guard candidate geometry

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Geometry/GuardGeometry.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/GuardGeometryTests.cs`

- [ ] **Step 1: Write failing guard tests from the shared contract**

Cover no intersection, top/middle/lower intersection, a tall window crossing all bands,
nearest left, nearest right, a nearer candidate winning even when it shrinks more, exact
tie choosing left, oversized width/height, negative work-area origin, and no available
candidate. Include this nearest-before-resize oracle:

```csharp
var result = GuardGeometry.CorrectedFrame(
    new RectD(100, 100, 500, 300),
    new RectD(0, 0, 1000, 800),
    [new RectD(200, 0, 400, 800)]);
Assert.Equal(new RectD(0, 100, 200, 300), result);
```

The left result moves less even though the right side preserves more width.

- [ ] **Step 2: Run the guard tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~GuardGeometryTests
```

Expected: FAIL because `GuardGeometry.CorrectedFrame` does not exist.

- [ ] **Step 3: Implement the exact candidate ordering**

Return `RectD?`. First test half-open intersection. Clamp height and vertical position
to the work area. Derive boundaries only from bands overlapping the adjusted vertical
range. Build left and right candidates, preserving size where it fits. Compare this
tuple lexicographically:

```text
(abs(deltaX) + abs(deltaY), lostWidth + lostHeight, sideRank)
```

Use side rank `0` for left and `1` for right. Do not call Win32 or round coordinates in
this class.

- [ ] **Step 4: Run the focused and complete tests**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~GuardGeometryTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: PASS with zero warnings.

- [ ] **Step 5: Commit guard geometry**

```bash
git add native/windows/src/ScreenFix.Core/Geometry/GuardGeometry.cs native/windows/tests/ScreenFix.Core.Tests/GuardGeometryTests.cs
git commit -m "feat: add Windows guard geometry"
```

### Task 5: Validate and persist configuration safely

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Configuration/ConfigValidator.cs`
- Create: `native/windows/src/ScreenFix.Core/Configuration/JsonConfigStore.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/ConfigValidatorTests.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/JsonConfigStoreTests.cs`

- [ ] **Step 1: Write failing validation tests**

Prove one valid default passes. Independently reject null configuration, schema other
than 1, empty stable ID/name, non-positive or non-finite display dimensions, band count
other than three, NaN/infinity, non-positive band size, negative origin, and right/bottom
bounds above 1. Assert a stable diagnostic string for each category.

- [ ] **Step 2: Run validator tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~ConfigValidatorTests
```

Expected: FAIL because `ConfigValidator.Validate` is missing.

- [ ] **Step 3: Implement validation without mutation**

Return this result rather than throwing for user data:

```csharp
public readonly record struct ValidationResult(bool IsValid, string? Error);
public static ValidationResult Validate(ScreenFixConfig? value);
```

Count exactly three items; do not accept a sparse or null band collection. Keep messages
short and deterministic.

- [ ] **Step 4: Run validator tests to prove GREEN**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Write failing store tests**

Use a unique directory under `Path.GetTempPath()` and delete only that exact directory
in test cleanup. Prove:

- missing file returns `IsMissing=true` without creating a file;
- Save then Load round-trips a valid default using camel-case JSON;
- Save leaves no `.tmp` file;
- invalid JSON returns an error and leaves original bytes unchanged;
- structurally invalid JSON returns the validator error and is not overwritten; and
- Save rejects invalid configuration before creating or replacing a file.

- [ ] **Step 6: Run store tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~JsonConfigStoreTests
```

Expected: FAIL because `JsonConfigStore` and `ConfigLoadResult` are missing.

- [ ] **Step 7: Implement atomic UTF-8 JSON storage**

Expose:

```csharp
public sealed record ConfigLoadResult(ScreenFixConfig? Value, bool IsMissing, string? Error);
public sealed class JsonConfigStore(string path)
{
    public ConfigLoadResult Load();
    public void Save(ScreenFixConfig value);
}
```

Use `JsonSerializerOptions` with camel-case naming and indented output. Save to
`config.json.tmp` in the same directory, flush and close it, then call
`File.Move(temp, path, overwrite: true)`. Clean the temporary file on failure. Never
rewrite a file from Load. Keep trimming disabled later because reflection serialization
is intentional in Phase 1.

- [ ] **Step 8: Run all configuration and solution tests**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter "FullyQualifiedName~ConfigValidatorTests|FullyQualifiedName~JsonConfigStoreTests"
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: PASS with zero warnings.

- [ ] **Step 9: Commit validated persistence**

```bash
git add native/windows/src/ScreenFix.Core/Configuration native/windows/tests/ScreenFix.Core.Tests
git commit -m "feat: persist Windows ScreenFix config"
```

### Task 6: Define the shared tray menu state

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Menu/MenuState.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/MenuStateTests.cs`

- [ ] **Step 1: Write failing menu-state tests**

Model menu rows without WinForms types. Assert exact order and labels for enabled,
disabled, calibrating, disconnected, and paused states:

```text
optional Paused row
Disable or Enable
Calibrate
Select Monitor
Reset to Defaults
Reload
separator
Quit
```

Assert Reset is disabled when disconnected, Calibrate is checked while editing, and
every action except Quit is disabled when `implementationReady=false` in the Phase 1
shell. Also assert Enable/Disable is checked if and only if enabled, a Paused row is
disabled, Calibrate is disabled when disconnected, and Select Monitor is available when
`implementationReady=true` even with no saved display.

- [ ] **Step 2: Run the menu tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~MenuStateTests
```

Expected: FAIL because `MenuState.Build` does not exist.

- [ ] **Step 3: Implement immutable menu rows**

Use a `MenuCommand` enum, `MenuRow` record with label/checked/enabled/separator fields,
and one `MenuState.Build` method. Do not put callbacks, WinForms objects, or mutable
controller state in Core.

- [ ] **Step 4: Run menu and full tests**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~MenuStateTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: PASS.

- [ ] **Step 5: Commit the menu contract**

```bash
git add native/windows/src/ScreenFix.Core/Menu native/windows/tests/ScreenFix.Core.Tests/MenuStateTests.cs
git commit -m "feat: define native tray menu state"
```

### Task 7: Build the minimal WinForms tray lifecycle

**Files:**

- Create: `native/windows/src/ScreenFix.App/Lifecycle/ResourceOwner.cs`
- Create: `native/windows/src/ScreenFix.App/Lifecycle/SingleInstanceGate.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.App.Tests/LifecycleTests.cs`
- Delete: template test in `native/windows/tests/ScreenFix.App.Tests/`
- Modify: `native/windows/src/ScreenFix.App/Program.cs`
- Create: `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`

- [ ] **Step 1: Write failing ownership and single-instance tests**

Use a unique mutex name containing `Guid.NewGuid()`. Prove:

- the first `SingleInstanceGate.TryAcquire(name)` succeeds;
- a second acquisition of the same name returns null without blocking;
- disposing the first gate twice is safe and a later acquisition succeeds;
- `ResourceOwner` runs registered cleanup actions in reverse order exactly once; and
- if one cleanup throws, all remaining actions still run before the error is surfaced.

Link only `src/ScreenFix.App/Lifecycle/ResourceOwner.cs` and
`src/ScreenFix.App/Lifecycle/SingleInstanceGate.cs` into the portable `net10.0`
`ScreenFix.App.Tests` project. Do not reference the Windows-targeted app assembly or move
these OS-backed types into `ScreenFix.Core`.

- [ ] **Step 2: Run lifecycle tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~LifecycleTests
```

Expected: FAIL because `SingleInstanceGate` and `ResourceOwner` do not exist.

- [ ] **Step 3: Implement and prove the reusable ownership behavior**

`SingleInstanceGate.TryAcquire` uses a named `Mutex` with `initiallyOwned: true` and the
`createdNew` result; it never waits. Only an acquired gate releases ownership.
`ResourceOwner` accepts non-null cleanup actions, executes its LIFO stack once, continues
after individual failures, and throws one `AggregateException` after all cleanup has run.

Run:

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~LifecycleTests
```

Expected: PASS.

- [ ] **Step 4: Wire the not-yet-created tray context to prove RED**

Extend the compile-safe `Program.Main` after `ApplicationConfiguration.Initialize()`
with an acquisition of `Local\ScreenFix.Native`, an immediate return when acquisition
fails, and `Application.Run(new ScreenFixApplicationContext(gate))`, then run:

```bash
dotnet build native/windows/src/ScreenFix.App/ScreenFix.App.csproj -c Release
```

Expected: FAIL because `ScreenFixApplicationContext` does not exist.

- [ ] **Step 5: Implement the thin tray context**

`Program.Main` must remain `[STAThread]`, call `ApplicationConfiguration.Initialize()`,
acquire a per-user named mutex without waiting, and run exactly one context. A second
process exits cleanly before constructing `NotifyIcon`.

The context must:

- create one `NotifyIcon` using an embedded/system icon and tooltip `ScreenFix`;
- map `MenuState.Build(... implementationReady: false)` into a
  `ContextMenuStrip`;
- leave Enable, Calibrate, Select Monitor, Reset, and Reload visibly disabled;
- keep Quit enabled and call `ExitThread()`;
- register cleanup so the icon is hidden before the menu, icon, and mutex are disposed;
  and
- make every exit path idempotent through `ResourceOwner`.

The manifest requests `asInvoker`. PerMonitorV2 comes from the project property and
`ApplicationConfiguration.Initialize()`; do not call legacy DPI APIs manually.

- [ ] **Step 6: Build and inspect the Windows executable metadata**

```bash
dotnet build native/windows/src/ScreenFix.App/ScreenFix.App.csproj -c Release
```

Expected: PASS with zero warnings and an assembly named `ScreenFix.exe`. Do not attempt
to launch the WinForms binary on macOS or Linux.

- [ ] **Step 7: Run all platform-independent tests**

```bash
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
```

Expected: PASS.

- [ ] **Step 8: Commit the tray shell**

```bash
git add native/windows/src/ScreenFix.App native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: add Windows tray shell"
```

### Task 8: Publish and assert one self-contained x64 executable

**Files:**

- Create: `native/windows/scripts/assert-win-x64-package.ps1`
- Create: `native/windows/scripts/publish-win-x64.ps1`

- [ ] **Step 1: Write the independent package acceptance script**

`assert-win-x64-package.ps1` accepts an optional `-OutputDirectory`, defaulting to the
repository's `native/windows/artifacts/windows/win-x64`. It fails unless:

1. the directory exists;
2. exactly one regular file exists recursively;
3. its name is exactly `ScreenFix.exe`;
4. its first two bytes are `MZ`; and
5. its PE machine field is `0x8664` (AMD64, which covers ordinary Intel and AMD x64 PCs).

The script reads the PE offset as a little-endian 32-bit integer at byte `0x3c`, then
the machine field as a little-endian 16-bit integer at `peOffset + 4`. Validate offsets
before reading. Throw a distinct message for every failed assertion.

- [ ] **Step 2: Run the package acceptance to prove RED**

Run from a shell with PowerShell 7:

```bash
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: FAIL with `package directory does not exist` because no publish has run.

- [ ] **Step 3: Implement the fail-closed publish script**

The script resolves paths from `$PSScriptRoot`, removes only the exact
`native/windows/artifacts/windows/win-x64` directory, and runs:

```powershell
dotnet publish $Project `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -o $Output `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:PublishTrimmed=false `
  -p:DebugType=None `
  -p:DebugSymbols=false `
  -p:UseAppHost=true
```

Set `$ErrorActionPreference = "Stop"`, check `$LASTEXITCODE`, and invoke the independent
`assert-win-x64-package.ps1` against `$Output`. Print only the final absolute artifact
path and byte size after the assertion succeeds.

- [ ] **Step 4: Publish, then run the independent acceptance to prove GREEN**

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: PASS and exactly
`native/windows/artifacts/windows/win-x64/ScreenFix.exe`; no DLL, JSON, PDB, or runtime
installation is required on the target PC.

- [ ] **Step 5: Prove the acceptance rejects a companion file**

Run:

```bash
pwsh -NoProfile -Command "Set-Content -LiteralPath 'native/windows/artifacts/windows/win-x64/unexpected.txt' -Value 'unexpected'"
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: the second command FAILS with the exact file-count diagnostic. Then rerun the
publish command, which cleans only the exact output directory, and rerun the assertion.
Expected: PASS with one executable.

- [ ] **Step 6: Re-run the script to prove deterministic cleanup**

Run:

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: PASS again with one `ScreenFix.exe`; no stale artifact survives.

- [ ] **Step 7: Commit release automation**

```bash
git add native/windows/scripts/assert-win-x64-package.ps1 native/windows/scripts/publish-win-x64.ps1 native/windows/.gitignore
git commit -m "build: publish single-file Windows x64 app"
```

### Task 9: Complete Phase 1 verification

**Files:** None unless a verified defect requires a test-first correction.

- [ ] **Step 1: Verify formatting**

```bash
dotnet format native/windows/ScreenFix.slnx --verify-no-changes
```

Expected: exit 0. If it fails, run `dotnet format`, inspect the diff, and rerun the
verification before committing formatting alone.

- [ ] **Step 2: Verify clean build and tests from scratch**

Delete only `native/windows/**/bin` and `native/windows/**/obj` through `dotnet clean`,
then run:

```bash
dotnet clean native/windows/ScreenFix.slnx -c Release
dotnet restore native/windows/ScreenFix.slnx
dotnet build native/windows/ScreenFix.slnx -c Release --no-restore
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
```

Expected: zero warnings, zero errors, all tests pass.

- [ ] **Step 3: Verify the release artifact again**

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
```

Expected: the script's single-file, MZ, and AMD64 assertions all pass.

- [ ] **Step 4: Smoke-test on a physical Windows x64 machine**

Copy only `ScreenFix.exe` to a Windows x64 machine without a separately installed .NET
10 runtime. Verify:

- double-click creates one ScreenFix tray icon and no taskbar window;
- the five future feature commands are visible but disabled;
- starting the executable again does not create a second tray icon; and
- Quit removes the icon and leaves no ScreenFix process.

Record Windows edition/build and the executable SHA-256 in the execution report. Phase 1
does not claim mask or window-protection functionality.

- [ ] **Step 5: Confirm the final worktree state**

Run:

```bash
git status --short
git diff --check
```

Expected: no uncommitted Phase 1 files and no whitespace errors. Put machine/build/hash
evidence in the execution handoff, not an unspecified repository file.

## Phase 1 completion gate

Do not begin overlays or hooks until all of these are true:

- every geometry, defaults, validation, persistence, and menu test is green;
- Release builds with zero warnings;
- the publish script produces one AMD64 `ScreenFix.exe` and rejects any companion file;
- the single-instance tray smoke test passes on Windows x64; and
- the implementation is reviewed against both native packaging design and the shared
  behavior contract.
