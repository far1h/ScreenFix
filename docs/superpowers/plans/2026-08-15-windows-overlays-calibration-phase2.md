# Windows Overlays and Calibration Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Phase 1 tray shell into a useful Windows x64 app that remembers one physical monitor, renders three transactional click-through black masks, and supports the complete mouse and trackpad calibration contract.

**Architecture:** Keep matching, rounding, layout, and gesture state deterministic in `ScreenFix.Core`. Keep Win32 enumeration, WinForms surfaces, the tray adapter, and system messages in `ScreenFix.App`; runtime-neutral app orchestration is dependency-injected and linked into the portable app test project so it can be proven on macOS before physical Windows testing.

**Tech Stack:** .NET 10 LTS, C# 14, WinForms, System.Drawing, System.Text.Json, xUnit, User32 display configuration APIs, DWM layered windows, PowerShell 7

---

## Starting point, scope, and references

Start from Windows Phase 1 head `e8af6e0` or its reviewed successor. Before Task 1,
resolve the outstanding Phase 1 finding that left/right resize snapping must enforce
only minimum width and top/bottom resize snapping must enforce only minimum height;
rerun its focused regression tests and all Phase 1 tests. Do not build the Phase 2
gesture session on the known axis-minimum defect. The Phase 1 line already contains the
original `f195e81` foundation plus config-schema, DPI-minimum, and PE-header fixes.
Read these files before changing code:

- `docs/screenfix-behavior-contract.md`
- `docs/superpowers/specs/2026-08-15-native-packaging-design.md`
- `docs/superpowers/plans/2026-08-15-windows-exe-phase1.md`
- `docs/superpowers/specs/2026-08-15-trackpad-calibration-design.md`
- `docs/superpowers/specs/2026-08-15-calibration-controls-polish-design.md`

Use the current Microsoft documentation while implementing the adapters:

- `QueryDisplayConfig`, including its `ERROR_INSUFFICIENT_BUFFER` retry
- `DISPLAYCONFIG_TARGET_DEVICE_NAME.monitorDevicePath`
- `DISPLAYCONFIG_SOURCE_DEVICE_NAME.viewGdiDeviceName`
- layered-window hit testing and `SetLayeredWindowAttributes`
- per-monitor DPI behavior in Windows Forms

This phase deliberately does **not** subscribe to other processes' windows or move them.
Until Phase 3 lands, the runnable tray must honestly show the disabled status row
`Paused: Window correction is not available in this build`; masks, monitor selection,
calibration, reset, reload, enable/disable, and quit are real and enabled.

## File structure

Create focused files with one responsibility each:

```text
native/windows/
├── src/
│   ├── ScreenFix.Core/
│   │   ├── Calibration/
│   │   │   ├── CalibrationLayout.cs
│   │   │   └── CalibrationSession.cs
│   │   ├── Displays/
│   │   │   ├── ConnectedDisplay.cs
│   │   │   ├── DisplayMatcher.cs
│   │   │   └── DisplayTopologyBuilder.cs
│   │   └── Geometry/
│   │       └── NativePixelGeometry.cs
│   └── ScreenFix.App/
│       ├── Calibration/
│       │   ├── CalibrationForm.cs
│       │   ├── CalibrationPainter.cs
│       │   ├── DpiProbeWindow.cs
│       │   └── MonitorPickerForm.cs
│       ├── Displays/
│       │   └── WindowsDisplayTopology.cs
│       ├── Interop/
│       │   ├── DisplayConfigNative.cs
│       │   ├── NativeTypes.cs
│       │   └── User32.cs
│       ├── Notifications/
│       │   ├── SystemMessageCoordinator.cs
│       │   └── SystemMessageWindow.cs
│       ├── Overlays/
│       │   ├── MaskForm.cs
│       │   └── MaskOverlaySet.cs
│       ├── Runtime/
│       │   ├── RuntimeContracts.cs
│       │   ├── RuntimeController.cs
│       │   └── RuntimeState.cs
│       └── ScreenFixApplicationContext.cs
└── tests/
    ├── ScreenFix.Core.Tests/
    │   ├── CalibrationLayoutTests.cs
    │   ├── CalibrationSessionTests.cs
    │   ├── DisplayMatcherTests.cs
    │   ├── DisplayTopologyBuilderTests.cs
    │   └── NativePixelGeometryTests.cs
    └── ScreenFix.App.Tests/
        ├── MaskOverlaySetTests.cs
        ├── RuntimeControllerTests.cs
        └── SystemMessageCoordinatorTests.cs
```

Do not add a third production project. Add a project reference from
`ScreenFix.App.Tests` to `ScreenFix.Core`, then link only runtime-neutral app source
files into the portable `net10.0` test assembly. Never instantiate WinForms or call
Win32 in tests that run on macOS.

### Task 1: Lock display matching and native-pixel rounding

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Displays/ConnectedDisplay.cs`
- Create: `native/windows/src/ScreenFix.Core/Displays/DisplayMatcher.cs`
- Create: `native/windows/src/ScreenFix.Core/Geometry/NativePixelGeometry.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/DisplayMatcherTests.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/NativePixelGeometryTests.cs`

- [ ] **Step 1: Write one failing display-match test**

Define a live descriptor whose stable ID is nullable because an individual topology
read can fail to resolve a target path:

```csharp
public sealed record ConnectedDisplay(
    string? StableId,
    string Name,
    int Width,
    int Height,
    RectD FullBounds,
    RectD WorkArea);
```

First prove that a case-insensitive stable-ID match wins even when another display has
the same name and dimensions. Then add separate tests proving: no fallback while one
live stable ID matches; exactly one ordinal name-and-dimensions fallback succeeds when
no stable ID matches; zero or two fallback candidates return null; and duplicate stable
IDs return null rather than guessing.

- [ ] **Step 2: Run the focused test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~DisplayMatcherTests
```

Expected: FAIL because the display types do not exist.

- [ ] **Step 3: Implement the conservative matcher**

Expose:

```csharp
public static ConnectedDisplay? Find(
    DisplayIdentity saved,
    IReadOnlyList<ConnectedDisplay> connected);
```

Use `StringComparer.OrdinalIgnoreCase` only for the Windows device path. Use ordinal
equality for the diagnostic friendly name and exact integer dimensions. Return a value
only when the applicable candidate set contains exactly one item.

- [ ] **Step 4: Write failing edge-rounding tests**

Prove that normalized edges are rounded separately with
`MidpointRounding.AwayFromZero`, then width and height are derived from the rounded
edges. Required oracles:

```csharp
var bands = DefaultConfiguration.Create(display).Bands;
var native = NativePixelGeometry.ToNativeBands(
    new RectD(-3440, -200, 3440, 1440), bands);

Assert.All(native, band => Assert.Equal(-2225, band.X));
Assert.All(native, band => Assert.Equal(-1520, band.Right));
Assert.Equal(native[0].Bottom, native[1].Y);
Assert.Equal(native[1].Bottom, native[2].Y);
Assert.Equal(-200, native[0].Y);
Assert.Equal(1240, native[2].Bottom);
```

Also prove `0.5` rounds away from zero at positive and negative origins, all three
rectangles stay inside the full display, and invalid input throws before returning a
partial list.

- [ ] **Step 5: Run rounding tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~NativePixelGeometryTests
```

Expected: FAIL because `NativePixelGeometry` is missing.

- [ ] **Step 6: Implement rounding and run the full core suite**

Use this edge rule for every band:

```csharp
var left = Round(full.X + band.X * full.Width);
var top = Round(full.Y + band.Y * full.Height);
var right = Round(full.X + band.Right * full.Width);
var bottom = Round(full.Y + band.Bottom * full.Height);
return new RectD(left, top, right - left, bottom - top);
```

Run:

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release
```

Expected: every old and new core test passes.

- [ ] **Step 7: Commit the deterministic display boundary**

```bash
git add native/windows/src/ScreenFix.Core native/windows/tests/ScreenFix.Core.Tests
git commit -m "feat: resolve Windows display geometry"
```

### Task 2: Merge Win32 monitor topology with stable DisplayConfig identity

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Displays/DisplayTopologyBuilder.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/DisplayTopologyBuilderTests.cs`
- Create: `native/windows/src/ScreenFix.App/Interop/NativeTypes.cs`
- Create: `native/windows/src/ScreenFix.App/Interop/User32.cs`
- Create: `native/windows/src/ScreenFix.App/Interop/DisplayConfigNative.cs`
- Create: `native/windows/src/ScreenFix.App/Displays/WindowsDisplayTopology.cs`

- [ ] **Step 1: Write failing topology-merge tests**

Keep the merge logic platform-neutral:

```csharp
public sealed record MonitorRecord(
    string GdiDeviceName, string FallbackName, RectD FullBounds, RectD WorkArea);
public sealed record ActivePathRecord(
    string GdiDeviceName, string? TargetDevicePath, string? FriendlyName);
```

Prove case-insensitive `GdiDeviceName` joining, friendly-name preference, preservation
of negative origins, omission of inactive DisplayConfig paths, nullable stable ID when
target-name lookup fails, one output per `EnumDisplayMonitors` result, and deterministic
sorting by full-frame X then Y then GDI device name. Also prove a cloned GDI source that
maps to multiple target paths gets no guessed stable ID; such a monitor stays visible as
a diagnostic record but cannot be newly selected until the topology is unambiguous.
Prove the independent fallback name survives complete and partial DisplayConfig failure
and can match a previously saved friendly name with exact dimensions.

- [ ] **Step 2: Run the merge test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~DisplayTopologyBuilderTests
```

Expected: FAIL because `DisplayTopologyBuilder` is missing.

- [ ] **Step 3: Implement the pure merge and prove GREEN**

`DisplayTopologyBuilder.Build` returns `ConnectedDisplay` values. Dimensions come from
the full monitor rectangle, not the work area or a cached configuration. Reject empty
and non-positive monitor frames without discarding other valid monitors.

- [ ] **Step 4: Declare only the required source-generated P/Invokes**

Use `[LibraryImport]` on partial methods where signatures permit it, Unicode structs,
and explicit `SetLastError=true`. Define and document native-size fields exactly; run
`Marshal.SizeOf` assertions on Windows later. Required calls are:

```text
EnumDisplayMonitors
GetMonitorInfoW(MONITORINFOEXW)
EnumDisplayDevicesW(DISPLAY_DEVICEW)
GetDisplayConfigBufferSizes
QueryDisplayConfig
DisplayConfigGetDeviceInfo
```

Call `GetDisplayConfigBufferSizes` then `QueryDisplayConfig` with
`QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE`. Retry the whole allocation/query pair
on `ERROR_INSUFFICIENT_BUFFER`, capped at three topology attempts so a continuously
changing setup returns a typed error instead of looping forever. For each active path,
obtain both `DISPLAYCONFIG_SOURCE_DEVICE_NAME.viewGdiDeviceName` and
`DISPLAYCONFIG_TARGET_DEVICE_NAME.monitorDevicePath`/friendly name. Do not persist
adapter LUID, source ID, target ID, `HMONITOR`, or `\\.\DISPLAYn` as identity.

Independently call `EnumDisplayDevicesW(monitorInfo.szDevice, 0, ...)` and retain its
non-empty `DeviceString` as the monitor's fallback friendly name. Prefer a non-empty
DisplayConfig target friendly name when available, but never replace the independent
name with the transient `\\.\DISPLAYn`. If both sources lack a friendly name, keep the
display available for diagnostics with its GDI label but do not allow name fallback.

- [ ] **Step 5: Implement the thin Windows adapter and build it**

`WindowsDisplayTopology.Enumerate()` calls the native adapter fresh every time, maps
`HMONITOR` to the pure descriptor separately for runtime ownership, and uses the pure
builder for identity. If display-config lookup fails, still return monitor rectangles
with null stable IDs and the independent `EnumDisplayDevicesW` friendly name so a unique
saved name-and-dimension fallback can work. Do not put DPI in the topology model: mask
geometry is physical-pixel normalized, while the calibration adapter obtains supported
per-monitor DPI from a monitor-bound window handle in Task 6.

```bash
dotnet build native/windows/src/ScreenFix.App/ScreenFix.App.csproj -c Release
```

Expected: PASS with zero warnings on the non-Windows build host; do not execute these
calls there.

- [ ] **Step 6: Commit monitor discovery**

```bash
git add native/windows/src/ScreenFix.Core/Displays native/windows/src/ScreenFix.App/Interop native/windows/src/ScreenFix.App/Displays native/windows/tests/ScreenFix.Core.Tests
git commit -m "feat: discover Windows monitors"
```

### Task 3: Build transactional click-through black masks

**Files:**

- Create: `native/windows/src/ScreenFix.App/Overlays/MaskOverlaySet.cs`
- Create: `native/windows/src/ScreenFix.App/Overlays/MaskForm.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.App.Tests/MaskOverlaySetTests.cs`

- [ ] **Step 1: Write failing transaction tests against fake surfaces**

Define runtime-neutral seams in `MaskOverlaySet.cs`:

```csharp
public interface IMaskSurface : IDisposable
{
    void Prepare(RectD nativeBounds);
    void ShowNoActivate();
    bool IsReady { get; }
}

public interface IMaskSurfaceFactory
{
    IMaskSurface Create();
}
```

Link that source into `ScreenFix.App.Tests`. Prove: exactly three candidates prepare
and show before old surfaces are disposed; failure creating, preparing, showing, or
verifying any candidate disposes every candidate and leaves all old surfaces alive;
successful replacement retires old surfaces once; `Clear` and `Dispose` are idempotent;
and a replacement after disposal is rejected.

- [ ] **Step 2: Run the transaction test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~MaskOverlaySetTests
```

Expected: FAIL because the overlay set does not exist.

- [ ] **Step 3: Implement the smallest transactional owner**

`Replace` must validate exactly three frames before allocation. Keep candidates in a
local list until all report ready. On success, swap the committed list in one statement,
then dispose the old list. Return a typed result containing a short error; do not show
UI or alter guard state in this class.

- [ ] **Step 4: Implement the real `MaskForm`**

Create a borderless, black, taskbar-free form. Override `CreateParams` to add:

```text
WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
```

The `WS_EX_LAYERED` addition is mandatory: Microsoft documents it together with
`WS_EX_TRANSPARENT` for top-level hit testing. Call
`SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)`, then use `SetWindowPos` with
`HWND_TOPMOST`, exact virtual-screen pixel bounds, and
`SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER`. Override
`ShowWithoutActivation => true`; never call `Activate`, `Select`, or `Focus`.

`IsReady` requires a created native handle, `Visible`, and an unchanged physical
rectangle returned by `GetWindowRect`. If any native call fails, throw a short
`Win32Exception`; the transactional owner will preserve the old set.

- [ ] **Step 5: Run tests and build**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~MaskOverlaySetTests
dotnet build native/windows/ScreenFix.slnx -c Release
```

Expected: tests pass; build has zero warnings.

- [ ] **Step 6: Commit the mask transaction**

```bash
git add native/windows/src/ScreenFix.App/Overlays native/windows/src/ScreenFix.App/Interop native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: render transactional Windows masks"
```

### Task 4: Lock the calibration control layout in logical points

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Calibration/CalibrationLayout.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/CalibrationLayoutTests.cs`

- [ ] **Step 1: Write failing layout tests**

Port the approved control contract without WinForms types. Test the normal
3440-by-1440 logical layout and the exact negative-origin 260-by-180 oracle:

```text
Save              (24, 114, 100, 42)
Cancel            (136, 114, 100, 42)
Instruction       (24, 24, 212, 58)
Instruction dot   (40, 49, 8, 8)
Instruction text  (58, 24, 162, 58), 13 point
```

Also prove the normal button size is 104-by-42, the button gap is 12, the normal
instruction frame is `(24,24,330,42)`, and widths below 260 or heights below 180 fail
with `display is too small for calibration controls`.

- [ ] **Step 2: Run the layout test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~CalibrationLayoutTests
```

Expected: FAIL because `CalibrationLayout` is missing.

- [ ] **Step 3: Implement immutable layout output and prove GREEN**

Expose one `TryCreate(width, height)` returning frames, radii, font sizes, and colors as
plain values. Use `min(104, floor((width - 48 - 12) / 2))`; preserve the 24-point
insets and the approved wide/narrow instruction split at 378 points. Origin is not part
of the local layout.

- [ ] **Step 4: Commit the layout**

```bash
git add native/windows/src/ScreenFix.Core/Calibration native/windows/tests/ScreenFix.Core.Tests/CalibrationLayoutTests.cs
git commit -m "feat: define Windows calibration layout"
```

### Task 5: Implement held and tap-move-tap gesture state

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Calibration/CalibrationSession.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/CalibrationSessionTests.cs`

- [ ] **Step 1: Write the first failing held-drag test**

Use a 1000-by-800 logical canvas and the existing normalized geometry. Define:

```csharp
public enum CalibrationAction
{
    None, AcquireCapture, KeepCapture, ReleaseCapture, Render, Save, Cancel
}

public enum GesturePhase { Idle, Pressed, Latched }
```

Prove a primary down on the body acquires capture, movement below 4 logical points does
nothing, movement at Euclidean distance 4 applies the full accumulated delta, continued
movement applies only the new delta to the raw unsnapped band, and primary up releases
capture and returns to idle.

- [ ] **Step 2: Run the focused test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter "FullyQualifiedName~CalibrationSessionTests.Held"
```

Expected: FAIL because `CalibrationSession` is missing.

- [ ] **Step 3: Implement held state minimally and prove GREEN**

The session owns a deep copy of all three working bands and this active gesture data:

```text
band index, drag part, press point, last point,
raw unsnapped band, moved flag, gesture phase
```

Call `CalibrationGeometry.DragBand(... minimumSize: 20)` and
`SnapBand(... threshold: 12, minimumSize: 20)`. Calculate both results before committing
any gesture or working-band field, so a calculation failure leaves the previous input
state atomic.

- [ ] **Step 4: Add failing tap-move-tap and priority tests**

Prove all of the following independently:

- down/up below threshold enters `Latched` and keeps capture;
- mouse movement with no pressed button moves or resizes a latched selection;
- the next primary down drops the latch and does not select a second band;
- Save and Cancel take priority and fire immediately while latched;
- left, right, top, bottom, and body all work in held and latched modes;
- later bands and 8-point edges retain existing hit priority;
- screen/peer snaps stay visible while the raw band continues unsnapped and release
  beyond 12 points has no sticky drift;
- capture loss clears only the gesture, not the editor or working copy; and
- non-primary buttons never start or finish a gesture.

- [ ] **Step 5: Implement the remaining state transitions and run all tests**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~CalibrationSessionTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: every gesture and regression test passes.

- [ ] **Step 6: Commit complete pointer semantics**

```bash
git add native/windows/src/ScreenFix.Core/Calibration/CalibrationSession.cs native/windows/tests/ScreenFix.Core.Tests/CalibrationSessionTests.cs
git commit -m "feat: support Windows calibration gestures"
```

### Task 6: Render and drive the WinForms calibration editor

**Files:**

- Create: `native/windows/src/ScreenFix.App/Calibration/CalibrationPainter.cs`
- Create: `native/windows/src/ScreenFix.App/Calibration/CalibrationForm.cs`
- Create: `native/windows/src/ScreenFix.App/Calibration/DpiProbeWindow.cs`
- Create: `native/windows/src/ScreenFix.App/Calibration/MonitorPickerForm.cs`
- Modify: `native/windows/src/ScreenFix.App/Interop/User32.cs`
- Create: `native/windows/src/ScreenFix.App/Runtime/RuntimeContracts.cs`

- [ ] **Step 1: Make the app build fail on the missing editor boundary**

Add an `ICalibrationHost` contract in `RuntimeContracts.cs` with transactional
`Start`, `Stop`, and `IsEditing` members, then reference `CalibrationForm` from the
Windows implementation.

```bash
dotnet build native/windows/src/ScreenFix.App/ScreenFix.App.csproj -c Release
```

Expected: FAIL because the forms do not exist.

- [ ] **Step 2: Implement custom painting from the pure model**

Use one borderless topmost `Form` exactly covering the selected display. Set
`ShowInTaskbar=false`, `DoubleBuffered=true`, and `WS_EX_TOOLWINDOW`; this editor is
interactive and may activate, unlike normal masks. `CalibrationPainter` uses a DPI
transform so geometry remains in logical points:

```text
physical pixels = logical points * DeviceDpi / 96
logical pointer = client pixels * 96 / DeviceDpi
```

Draw three translucent red fills, orange outlines, 8-point white edges, and the exact
approved instruction/Save/Cancel styles. Do not use child controls; painting and hit
testing must share the pure frames so button text cannot drift inside a separate
control layout.

Before allocating an editor form, create a one-pixel hidden, nonactivating
`DpiProbeWindow` with native creation coordinates inside the selected monitor. Call
`GetDpiForWindow` on that monitor-bound handle, then dispose the probe. Convert the full
physical monitor size to logical points and reject anything below 260-by-180 before
allocating the editor. After the candidate editor handle exists at the selected monitor
bounds, require its `DeviceDpi`/`GetDpiForWindow` value to match the preflight value; a
mismatch disposes the candidate and requests a fresh reconcile. Do not use
`GetDpiForMonitor` in this PerMonitorV2 process. Add the `GetDpiForWindow` declaration to
`User32.cs`; a zero result is a candidate failure, not a silent 96-DPI fallback.

- [ ] **Step 3: Wire capture-based mouse and trackpad input**

`OnMouseDown` passes only the primary button to `CalibrationSession.PointerDown` and
sets `Capture=true` only when requested. `OnMouseMove` passes the logical point and
current primary-button state. A quick `OnMouseUp` keeps capture for latched movement;
a completed held drag releases it. `OnMouseCaptureChanged` calls the pure capture-loss
transition. Save/Cancel callbacks carry the editor generation and a deep band copy.

Never require Shift, double-click, a secondary button, a global mouse hook, or an
administrator/accessibility permission.

- [ ] **Step 4: Implement transactional editor replacement**

Allocate, lay out, paint, create the handle, position, and show a candidate before
retiring an old editor. Reject a display smaller than 260-by-180 logical points before
creating a form. If topology bounds or DPI change during calibration, cancel the
working copy and let the controller reconcile; never reinterpret a half-finished drag
under new scaling.

- [ ] **Step 5: Implement a simple monitor picker**

`MonitorPickerForm` lists every fresh topology record as
`Friendly name — WIDTH x HEIGHT — left/top origin`. It stores the selected stable path
outside display text, disables Save when no item is selected, and returns a generation-
checked descriptor. Cancel makes no configuration change. If a monitor lacks a target
device path, show it disabled because a new selection must persist a stable identity.

- [ ] **Step 6: Build and commit the UI adapter**

```bash
dotnet build native/windows/ScreenFix.slnx -c Release
```

Expected: PASS with zero warnings.

```bash
git add native/windows/src/ScreenFix.App/Calibration native/windows/src/ScreenFix.App/Runtime
git commit -m "feat: add Windows calibration editor"
```

### Task 7: Implement runtime commands, persistence, and dynamic tray state

**Files:**

- Modify: `native/windows/src/ScreenFix.App/Runtime/RuntimeContracts.cs`
- Create: `native/windows/src/ScreenFix.App/Runtime/RuntimeState.cs`
- Create: `native/windows/src/ScreenFix.App/Runtime/RuntimeController.cs`
- Modify: `native/windows/src/ScreenFix.Core/Menu/MenuState.cs`
- Modify: `native/windows/tests/ScreenFix.Core.Tests/MenuStateTests.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj`
- Create: `native/windows/tests/ScreenFix.App.Tests/RuntimeControllerTests.cs`

- [ ] **Step 1: Write failing controller startup tests with fakes**

Link runtime-neutral controller files into `ScreenFix.App.Tests`. Inject configuration,
topology, overlay, editor, picker, menu-refresh, clock, and one-shot-notice interfaces.
Prove separately:

- missing config creates no file or overlay and requests monitor selection in status;
- invalid config bytes stay unchanged and an invalid-settings status is exposed;
- enabled connected config renders three masks;
- disabled config creates none;
- a disconnected saved display creates none and reports one failure episode;
- unique fallback reconnect works; and
- ambiguous fallback never creates masks.

- [ ] **Step 2: Run one startup test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter "FullyQualifiedName~RuntimeControllerTests.Start"
```

Expected: FAIL because `RuntimeController` is missing.

- [ ] **Step 3: Implement startup and idempotent reconcile**

Every public entry verifies UI-thread ownership. Increment a session generation before
replacement or teardown. Reconcile always rereads live topology. If display resolution
or origin changed, derive masks again from normalized bands; never rewrite saved bands
merely because topology changed.

On a mask replacement failure, preserve the old committed surfaces, expose
`Paused: Mask rendering failed`, and send only one balloon notice for that uninterrupted
failure episode. A later successful replace clears the episode.

- [ ] **Step 4: Add failing command tests**

Test each command as its own fact:

- Select Monitor starts calibration with exact defaults but persists only on Save;
- cancelling a new selection retains the previous saved display and masks;
- Calibrate edits a deep copy and choosing checked Calibrate again cancels immediately;
- Save validates, persists, then reconciles; Save failure keeps the editor live;
- Cancel discards the copy and restores protection;
- Disable persists `enabled=false`, closes every mask immediately, and cancels editing;
- Enable persists `enabled=true`, or opens Select Monitor when none is saved;
- Reset rereads the saved connected display, restores exact `1215/3440` and
  `(1920-1215)/3440` bands, preserves enabled state, and persists before reconcile;
- disconnected Reset is disabled and cannot mutate storage;
- Reload with a valid candidate transactionally reconciles;
- invalid Reload leaves committed masks/config in memory untouched and reports status;
- stale picker/editor callbacks cannot save or alter a newer generation; and
- Stop is idempotent and makes all late callbacks inert.

- [ ] **Step 5: Implement commands and remove the Phase 1 readiness switch**

Replace the coarse `implementationReady` parameter with explicit state sufficient for
the exact menu contract. Select exactly zero or one disabled status row with this Phase
2 priority and these labels:

```text
1. Paused: Invalid configuration
2. Paused: Mask rendering failed
3. Paused: Selected display is disconnected
4. Paused: Select a monitor
5. Paused: Window correction is not available in this build
```

The intermediate window-correction row appears only while saved configuration is
enabled, connected, successfully masked, and not calibrating. Intentional Disable has
no paused row. Add table-driven tests for every individual reason, all pairwise higher-
priority combinations, recovery transitions, and the invariant that at most one row
starts with `Paused:`. All six real Phase 2 commands are enabled according to connected/
editing state. Keep exact order and checks.

- [ ] **Step 6: Run controller, menu, and full tests**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~RuntimeControllerTests
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~MenuStateTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: all tests pass.

- [ ] **Step 7: Commit the runtime**

```bash
git add native/windows/src/ScreenFix.App/Runtime native/windows/src/ScreenFix.Core/Menu native/windows/tests
git commit -m "feat: control Windows mask runtime"
```

### Task 8: Reconcile display, work-area, DPI, power, and reload events

**Files:**

- Create: `native/windows/src/ScreenFix.App/Notifications/SystemMessageWindow.cs`
- Create: `native/windows/src/ScreenFix.App/Notifications/SystemMessageCoordinator.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/SystemMessageCoordinatorTests.cs`

- [ ] **Step 1: Write failing event-routing tests**

Put message decoding/coalescing in `SystemMessageCoordinator.cs`, separate from the
`NativeWindow`, so it can be linked into portable tests. Prove these mappings:

```text
WM_DISPLAYCHANGE                         -> topology reconcile
WM_SETTINGCHANGE with SPI_SETWORKAREA    -> topology reconcile
WM_POWERBROADCAST/PBT_APMSUSPEND         -> suspend resources
WM_POWERBROADCAST/PBT_APMRESUMEAUTOMATIC -> resume reconcile
WM_DPICHANGED for editor                 -> cancel editor then reconcile
```

Prove duplicate display messages coalesce into one UI-turn reconcile, suspend and
resume are idempotent, and a queued event carrying an old generation is ignored.

- [ ] **Step 2: Run the event test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~SystemMessageCoordinatorTests
```

Expected: FAIL because the coordinator does not exist.

- [ ] **Step 3: Implement the message-only window and routing**

Create one hidden, nonactivating top-level `NativeWindow` handle on the WinForms UI
thread. Do **not** use `HWND_MESSAGE`: message-only windows do not receive broadcast
display/settings/power messages. Its `WndProc` copies only message IDs/values into the
coordinator, which posts reconciliation; no native callback may mutate controller state
reentrantly. The calibration form reports `WM_DPICHANGED` to this same coordinator. On
disconnect, close editor and masks. On a later unambiguous reconnect, rebuild them. On
a changed frame or DPI during editing, cancel rather than save the working copy.

- [ ] **Step 4: Run tests and commit**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~SystemMessageCoordinatorTests
dotnet test native/windows/ScreenFix.slnx -c Release
git add native/windows/src/ScreenFix.App/Notifications native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: reconcile Windows display lifecycle"
```

### Task 9: Wire the real tray application and teardown order

**Files:**

- Modify: `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`
- Modify: `native/windows/src/ScreenFix.App/Program.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/LifecycleTests.cs`

- [ ] **Step 1: Write failing ownership-order tests**

Model the required order with fake resources: revoke callbacks/generation, stop system
messages, close editor, clear masks, dispose menu, hide/dispose icon, release the named
mutex. Prove partial construction performs the same safe suffix and every action runs
at most once even when a cleanup throws.

- [ ] **Step 2: Run the lifecycle test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~LifecycleTests
```

Expected: the new ownership-order test fails against the Phase 1 shell.

- [ ] **Step 3: Wire one controller and rebuild the menu from state**

Resolve `%LOCALAPPDATA%\ScreenFix\config.json` with
`Environment.SpecialFolder.LocalApplicationData`. Construct one topology adapter,
overlay set, calibration host, system-message window, and controller after acquiring the
mutex. Menu clicks delegate to controller methods. Rebuild menu items on demand without
duplicating the `NotifyIcon` or leaking old click handlers.

Startup failures keep Quit available and show one diagnostic balloon when possible.
Do not add Run at startup or an installer in this phase.

- [ ] **Step 4: Build, test, and commit**

```bash
dotnet build native/windows/ScreenFix.slnx -c Release
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
git add native/windows/src/ScreenFix.App native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: activate Windows ScreenFix masks"
```

### Task 10: Verify the Phase 2 executable on physical Windows x64

**Files:** None unless a proven defect requires a test-first correction.

- [ ] **Step 1: Verify formatting and clean tests**

```bash
dotnet format native/windows/ScreenFix.slnx --verify-no-changes
dotnet clean native/windows/ScreenFix.slnx -c Release
dotnet restore native/windows/ScreenFix.slnx
dotnet build native/windows/ScreenFix.slnx -c Release --no-restore
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
```

Expected: zero warnings/errors and all tests pass.

- [ ] **Step 2: Publish and reassert the one-file AMD64 package**

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: exactly one self-contained AMD64 `ScreenFix.exe`.

- [ ] **Step 3: Perform monitor/mask smoke tests on Windows x64**

On a normal-integrity physical or virtual Windows x64 installation without a separate
.NET 10 runtime, verify:

- first launch shows one tray icon and asks the user to select a monitor;
- selecting a 3440-by-1440 monitor and saving defaults creates three black bands at
  x=1215 through x=1920 with no vertical gap;
- a left/top negative-origin secondary monitor receives masks at its own coordinates;
- the three masks remain topmost over ordinary apps and never steal focus;
- clicks, mouse wheel, and trackpad gestures pass through black masks to apps beneath;
- disabling removes all three immediately; enabling restores them;
- disconnect removes all three; reconnect restores exactly one set;
- resolution, scale, taskbar position, sleep, and wake do not duplicate masks;
- switching Windows virtual desktops keeps masks visible where Windows supports the
  topmost tool-window behavior; if the OS does not expose a supported all-desktops pin,
  record that limitation explicitly rather than using undocumented virtual-desktop APIs;
- a second ScreenFix process creates no second tray icon or mask set; and
- Quit leaves no tray icon, editor, overlay window, or process.

- [ ] **Step 4: Perform full calibration input smoke tests**

With both a mouse and a Windows precision trackpad, independently verify body movement
and all four edge resizes using held drag and tap-move-tap. Verify snapping to every
screen edge and a peer edge, release beyond 12 logical points, minimum size, Save,
Cancel, checked-Calibrate-as-Cancel, exact Reset defaults, button/text alignment at
100% and 150% scale, and editor cancellation when display scale changes.

Record Windows edition/build, GPU/monitor topology, DPI values, executable SHA-256, and
each pass/fail result in the execution handoff. Fix any failure by first adding the
smallest reproducing automated test or a focused Windows integration harness.

- [ ] **Step 5: Confirm clean worktree state**

```bash
git status --short
git diff --check
```

Expected: no uncommitted Phase 2 source and no whitespace errors. The ignored artifact
may remain under `native/windows/artifacts/windows/win-x64/`.

## Phase 2 completion gate

Do not begin WinEvent correction until:

- all old and new portable tests are green;
- monitor stable-ID matching and topology/DPI changes pass on Windows;
- exactly three opaque black masks are transactional, topmost, and click-through;
- held and tap-move-tap movement/resizing pass with mouse and trackpad;
- Save, Cancel, Reset, Reload, Enable/Disable, disconnect/reconnect, and Quit are proven;
- the tray honestly states that window correction is unavailable in this intermediate
  build; and
- the single self-contained AMD64 package assertion still passes.
