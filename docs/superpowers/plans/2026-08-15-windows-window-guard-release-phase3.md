# Windows Window Guard and Release Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete ScreenFix for Windows x64 by observing ordinary application windows, moving or resizing eligible windows out of the masks, hardening lifecycle/failure behavior, and producing the final self-contained AMD64 executable.

**Architecture:** Convert native window state into a small immutable facts model, decide eligibility and target frames in deterministic code, and keep hooks/inspection/writes in thin Win32 adapters. One UI-thread guard coordinator owns debounce, self-event suppression, refusal cooldowns, session generations, hooks, and timers; mask protection remains independent when window correction is unavailable.

**Tech Stack:** .NET 10 LTS, C# 14, WinForms message loop, xUnit, User32 WinEvent hooks and window placement APIs, Dwmapi visible-frame metrics, PowerShell 7 single-file publishing

---

## Starting point, scope, and references

Start only after the Phase 2 completion gate in
`docs/superpowers/plans/2026-08-15-windows-overlays-calibration-phase2.md` passes. Re-read:

- `docs/screenfix-behavior-contract.md`
- `docs/superpowers/specs/2026-08-15-native-packaging-design.md`
- the Phase 1 and Phase 2 Windows plans

Use current Microsoft documentation while implementing:

- `SetWinEventHook`/`UnhookWinEvent`: the installing thread needs a message loop;
  out-of-context events are queued in order but callbacks can be reentrant, and managed
  callbacks must be kept alive.
- `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` for the visible rectangle.
- `WINDOWPLACEMENT`: its restored rectangle uses workspace coordinates for ordinary
  top-level windows, so never feed `rcNormalPosition` directly to `SetWindowPos`.
- `SetWindowPos` screen coordinates and `SWP_NOACTIVATE`.

Windows has no macOS Accessibility permission toggle. ScreenFix runs as `asInvoker` and
uses Win32 APIs at normal integrity. UIPI may reject elevated targets; that is a
per-window one-second cooldown, not a reason to hide masks or elevate ScreenFix.

Do not add UI Automation, content inspection, DLL injection, admin prompts, a service,
networking, telemetry, or an installer.

## File structure

```text
native/windows/
├── src/
│   ├── ScreenFix.Core/
│   │   └── Guard/
│   │       ├── GuardMemory.cs
│   │       ├── WindowEligibility.cs
│   │       └── WindowFacts.cs
│   └── ScreenFix.App/
│       ├── Guard/
│       │   ├── GuardScheduler.cs
│       │   ├── WinEventHookSet.cs
│       │   ├── WindowCorrector.cs
│       │   ├── WindowGuard.cs
│       │   ├── WindowNativeQuery.cs
│       │   └── WindowsWindowInspector.cs
│       ├── Interop/
│       │   ├── DwmApi.cs
│       │   └── WindowNative.cs
│       └── Runtime/
│           ├── RuntimeController.cs
│           └── RuntimeState.cs
├── tests/
│   ├── ScreenFix.Core.Tests/
│   │   ├── GuardMemoryTests.cs
│   │   └── WindowEligibilityTests.cs
│   └── ScreenFix.App.Tests/
│       ├── GuardSchedulerTests.cs
│       ├── RuntimeGuardIntegrationTests.cs
│       ├── WinEventHookOwnershipTests.cs
│       ├── WindowGuardTests.cs
│       ├── WindowCorrectorTests.cs
│       └── WindowsWindowInspectorTests.cs
└── scripts/
    ├── assert-win-x64-package.ps1
    └── publish-win-x64.ps1
```

As in Phase 2, link only runtime-neutral coordinator/corrector files into the portable
app test project. Compile actual P/Invokes on macOS but execute them only on Windows.

### Task 1: Define ordinary-window eligibility from immutable facts

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Guard/WindowFacts.cs`
- Create: `native/windows/src/ScreenFix.Core/Guard/WindowEligibility.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/WindowEligibilityTests.cs`

- [ ] **Step 1: Write the first failing eligible-window test**

Use a facts record with no native handles:

```csharp
public sealed record WindowFacts(
    long Key,
    RectD VisibleFrame,
    bool IsVisible,
    bool IsMinimized,
    bool IsRootTopLevel,
    bool IsOwned,
    bool IsScreenFixOwned,
    bool IsPlatformOwned,
    bool IsToolOrMenu,
    bool IsMovable,
    bool IsBorderlessFullScreen,
    bool IsOnSelectedDisplay);
```

Prove one visible, root, unowned, movable ordinary app window on the selected display is
eligible when it intersects a half-open mask rectangle.

- [ ] **Step 2: Run the eligibility test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~WindowEligibilityTests
```

Expected: FAIL because the guard facts and policy are missing.

- [ ] **Step 3: Add one exclusion test at a time**

Independently reject hidden, minimized, non-root, owned popup, ScreenFix-owned,
platform/desktop/secure, tool/menu, non-movable, borderless full-screen, wrong-display,
and nonintersecting windows. Explicitly prove a maximized **ordinary** window remains
eligible; it is restored during correction rather than classified as full-screen.

Use half-open intersection so touching a mask edge remains eligible only if another
mask actually overlaps.

- [ ] **Step 4: Implement the pure predicate and run core tests**

Expose:

```csharp
public static bool IsEligible(WindowFacts facts, IReadOnlyList<RectD> maskBands);
```

Return false for invalid/non-finite rectangles; do not throw on a bad external window.

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release
```

Expected: all core tests pass.

- [ ] **Step 5: Commit eligibility**

```bash
git add native/windows/src/ScreenFix.Core/Guard native/windows/tests/ScreenFix.Core.Tests/WindowEligibilityTests.cs
git commit -m "feat: classify Windows guard targets"
```

### Task 2: Lock debounce, self-event, and refusal timing

**Files:**

- Create: `native/windows/src/ScreenFix.Core/Guard/GuardMemory.cs`
- Create: `native/windows/tests/ScreenFix.Core.Tests/GuardMemoryTests.cs`
- Create: `native/windows/src/ScreenFix.App/Guard/GuardScheduler.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/GuardSchedulerTests.cs`

- [ ] **Step 1: Write failing guard-memory tests**

Inject `DateTimeOffset now`; never call the system clock in the pure type. Prove:

- a successful target is suppressed for 250 milliseconds only when the current frame
  is within one native point on every edge;
- a non-near event is not suppressed and clears the recent target;
- exactly 250 milliseconds is expired;
- refusal is blocked for one second and exactly one second is expired;
- state is isolated by stable window key; and
- prune removes expired entries without changing live entries.

- [ ] **Step 2: Run memory tests to prove RED, then implement**

```bash
dotnet test native/windows/tests/ScreenFix.Core.Tests/ScreenFix.Core.Tests.csproj -c Release --filter FullyQualifiedName~GuardMemoryTests
```

Expected: FAIL because `GuardMemory` is absent. Implement `ShouldSuppressRecent`,
`IsRefused`, `RecordSuccess`, `RecordRefusal`, `Forget`, and `Clear`, then rerun to PASS.

- [ ] **Step 3: Write failing debounce tests with a fake UI scheduler**

Define a cancellable `IUiDelay.Schedule(TimeSpan, Action)` seam. Prove a signal schedules
150 milliseconds, a later signal for the same key cancels/replaces only that key, two
different windows remain independent, stopping cancels all pending work, stale session
generations do not run, and a callback cannot run after disposal even if the fake fires
it late.

- [ ] **Step 4: Implement the scheduler and run both suites**

The production adapter uses `System.Windows.Forms.Timer` on the existing UI thread.
Keep one timer per pending key and dispose it before invoking correction.

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~GuardSchedulerTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: all tests pass.

- [ ] **Step 5: Commit temporal guard state**

```bash
git add native/windows/src/ScreenFix.Core/Guard native/windows/src/ScreenFix.App/Guard/GuardScheduler.cs native/windows/tests
git commit -m "feat: debounce Windows window correction"
```

### Task 3: Inspect native windows without reading their contents

**Files:**

- Create: `native/windows/src/ScreenFix.App/Interop/DwmApi.cs`
- Create: `native/windows/src/ScreenFix.App/Interop/WindowNative.cs`
- Create: `native/windows/src/ScreenFix.App/Guard/WindowNativeQuery.cs`
- Create: `native/windows/src/ScreenFix.App/Guard/WindowsWindowInspector.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/WindowsWindowInspectorTests.cs`

- [ ] **Step 1: Write failing inspector tests through a native-query seam**

Define `IWindowNativeQuery` in `WindowNativeQuery.cs`. Its methods return managed style,
PID, owner/root, shell/desktop handles, outer/DWM rectangles, selected monitor handle,
and show-state results. Link this file and `WindowsWindowInspector.cs` into the portable
app tests and use a fully controlled fake.

Keep the inspector signature portable with this value beside the query interface:

```csharp
public readonly record struct SelectedMonitor(
    nint Handle,
    RectD FullBounds,
    RectD WorkArea);
```

Expose `IWindowInspector.TryInspect(nint hwnd, SelectedMonitor selected)`. The Windows
topology adapter maps its live display into this value at the runtime boundary; portable
tests do not link or construct WinForms display adapters.

Prove one valid ordinary window maps to expected `WindowFacts`, `IsZoomed`, outer frame,
visible frame, and all four DWM edge differences. Then independently prove every style
mask, owner/root result, own PID, tool/menu classification, non-movable classification,
selected-monitor comparison, and borderless-full-screen decision. Prove DWM failure
falls back to the outer rectangle with zero edge differences and that native failure
returns no facts rather than a partial eligible window.

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowsWindowInspectorTests
```

Expected: FAIL because the inspector/query types are absent.

- [ ] **Step 2: Add only required Win32 declarations**

Declare Unicode/native-size signatures for:

```text
IsWindow, IsWindowVisible, IsIconic, IsZoomed
GetAncestor(GA_ROOT), GetWindow(GW_OWNER)
GetWindowLongPtrW(GWL_STYLE/GWL_EXSTYLE)
GetWindowThreadProcessId, GetClassNameW
GetWindowRect, MonitorFromRect
GetShellWindow, GetDesktopWindow
DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)
```

Each wrapper returns a result instead of leaking a stale `GetLastWin32Error`. Do not
open another process or request query rights merely to classify a window; the PID from
`GetWindowThreadProcessId` is sufficient to skip ScreenFix itself.

- [ ] **Step 3: Implement classification and frame metrics**

Read the outer rectangle with `GetWindowRect`. Prefer DWM extended frame bounds as the
visible rectangle; if DWM fails, use the outer rectangle. Preserve the four differences
between outer and visible edges so a corrected visible target can later be converted
back to an outer `SetWindowPos` rectangle.

Classify:

- root only when `GetAncestor(GA_ROOT) == hwnd`;
- owned when `GetWindow(GW_OWNER) != 0`;
- tool/menu from `WS_EX_TOOLWINDOW`, class `#32768`, and popup-only styles;
- platform-owned when the handle equals `GetShellWindow` or `GetDesktopWindow`;
- movable from ordinary top-level caption/thick-frame styles;
- selected display by `MonitorFromRect(... MONITOR_DEFAULTTONULL)` equality; and
- borderless full-screen only when the visible frame is within one native pixel of the
  selected full bounds and ordinary caption/thick-frame styles are absent.

Do not reject `IsZoomed`; return it separately for the corrector.

- [ ] **Step 4: Run portable mapping tests and build the native adapter**

`WindowNative` implements `IWindowNativeQuery`; all policy remains in the injected
inspector. Do not use undocumented `WorkerW`/`Progman` class-name lists as a security or
ownership boundary. Shell helper surfaces not equal to the documented handles must
still fail ordinary movable-window eligibility.

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowsWindowInspectorTests
dotnet build native/windows/ScreenFix.slnx -c Release
```

Expected: tests pass and native code compiles with zero warnings.

- [ ] **Step 5: Commit the inspected boundary**

```bash
git add native/windows/src/ScreenFix.App/Interop native/windows/src/ScreenFix.App/Guard/WindowNativeQuery.cs native/windows/src/ScreenFix.App/Guard/WindowsWindowInspector.cs native/windows/src/ScreenFix.App/Runtime native/windows/tests/ScreenFix.App.Tests/WindowsWindowInspectorTests.cs
git commit -m "feat: inspect Windows guard candidates"
```

### Task 4: Subscribe safely to WinEvent signals and seed existing windows

**Files:**

- Create: `native/windows/src/ScreenFix.App/Guard/WinEventHookSet.cs`
- Modify: `native/windows/src/ScreenFix.App/Interop/WindowNative.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/WinEventHookOwnershipTests.cs`

- [ ] **Step 1: Write failing hook-ownership tests against a fake native API**

Prove transactional installation of these individual hooks:

```text
EVENT_OBJECT_CREATE
EVENT_OBJECT_SHOW
EVENT_OBJECT_LOCATIONCHANGE
EVENT_SYSTEM_MOVESIZEEND
EVENT_SYSTEM_FOREGROUND
EVENT_SYSTEM_MINIMIZEEND
```

Use `WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS`, process/thread IDs zero. Prove
failure of any registration unhooks every already-created hook, successful stop unhooks
each exactly once, delegate ownership outlives every hook, callbacks after stop are
generation-rejected, and object events with non-window `idObject`/`idChild` are ignored.

- [ ] **Step 2: Run the ownership test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WinEventHookOwnershipTests
```

Expected: FAIL because `WinEventHookSet` is missing.

- [ ] **Step 3: Implement hook lifetime exactly**

Install on the WinForms UI thread, whose message loop is already running. Retain the
delegate in a field and a `GCHandle` until after every `UnhookWinEvent` returns. The
native callback copies `eventType`, `hwnd`, `idObject`, and `idChild`, then uses
`BeginInvoke`/the injected UI dispatcher; it never inspects or corrects a window inside
the callback because WinEvent callbacks can be reentrant.

After all hooks commit, call `EnumWindows` and enqueue every existing top-level handle.
Installing before enumeration avoids missing a window created during seeding; debounce
collapses duplicates.

- [ ] **Step 4: Run tests, build, and commit**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WinEventHookOwnershipTests
dotnet build native/windows/ScreenFix.slnx -c Release
git add native/windows/src/ScreenFix.App/Guard/WinEventHookSet.cs native/windows/src/ScreenFix.App/Interop/WindowNative.cs native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: observe Windows window events"
```

### Task 5: Correct normal and maximized windows without activation

**Files:**

- Create: `native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs`
- Modify: `native/windows/src/ScreenFix.App/Interop/WindowNative.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/WindowCorrectorTests.cs`

- [ ] **Step 1: Write the first failing normal-window correction test**

Inject inspector, native writer, clock, and memory seams. For an eligible visible frame,
prove the corrector calls existing `GuardGeometry.CorrectedFrame`, converts the visible
target back to the outer-window rectangle using recorded DWM edge differences, rounds
edges away from zero, and performs one `SetWindowPos` with:

```text
SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS
```

Prove no write occurs when geometry returns null.

- [ ] **Step 2: Run the normal test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter "FullyQualifiedName~WindowCorrectorTests.Normal"
```

Expected: FAIL because `WindowCorrector` is missing.

- [ ] **Step 3: Implement normal correction with bounded delayed verification**

An accepted `SWP_ASYNCWINDOWPOS` only means the request was posted to the target input
queue. Record a per-window pending target immediately, suppress further correction for
that key while pending, and verify through the injected UI-delay scheduler at absolute
deadlines 50, 150, 300, and 500 milliseconds after the write:

- if the observed visible frame is within one native point on every edge, clear pending
  and record success for 250 milliseconds from that verification time;
- if the handle disappears, forget the key without recording refusal;
- if it is not near and the 500-millisecond deadline has not elapsed, keep pending and
  schedule the next deadline; and
- at 500 milliseconds, clear pending and record a one-second refusal for that window.

A false native return or exception records refusal immediately. Pending signals for the
same key may complete success early when already near the target, but must never enqueue
a second write. Stop/generation replacement cancels verification timers and makes late
callbacks inert. Do not change global status for any per-window result.

- [ ] **Step 4: Add a failing maximized-window test**

For `IsZoomed=true`, first retrieve a correctly sized `WINDOWPLACEMENT`, preserve its
workspace-coordinate `rcNormalPosition`, set `showCmd=SW_SHOWNOACTIVATE`, add
`WPF_ASYNCWINDOWPLACEMENT`, and call `SetWindowPlacement`. Then queue the same
screen-coordinate `SetWindowPos` used for a normal window. This avoids feeding workspace
coordinates to `SetWindowPos` and restores without requesting activation.

Prove placement failure records refusal and skips `SetWindowPos`; minimized and
borderless-full-screen windows never reach this path.

- [ ] **Step 5: Add remaining verification, refusal, and self-event tests**

Use a fake writer/inspector/scheduler to prove immediate application, application after
150 milliseconds, application only at 500 milliseconds, a write that never applies,
and a handle that disappears. Assert exact verification deadlines, no duplicate write
while pending, early target-event completion, deadline refusal, and timer cancellation
on stop.

Also prove a recent within-one-point self-event produces no write; a different observed
frame is corrected; refusal suppresses exactly one second; one elevated/refusing window
does not block another; stale generation results are ignored; and a window destroyed
between inspection and write is contained.

- [ ] **Step 6: Run corrector and full tests**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowCorrectorTests
dotnet test native/windows/ScreenFix.slnx -c Release
```

Expected: all tests pass.

- [ ] **Step 7: Commit correction**

```bash
git add native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs native/windows/src/ScreenFix.App/Interop/WindowNative.cs native/windows/tests/ScreenFix.App.Tests/WindowCorrectorTests.cs
git commit -m "feat: correct Windows window frames"
```

### Task 6: Own one complete guard session

**Files:**

- Create: `native/windows/src/ScreenFix.App/Guard/WindowGuard.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/WindowGuardTests.cs`

- [ ] **Step 1: Write failing session tests**

With fake hooks, scheduler, inspector, and corrector, prove:

- `Start(display, maskFrames)` installs hooks then seeds existing windows;
- repeated Start with the identical display/masks is idempotent;
- changed display/masks builds a candidate hook session before retiring the old one;
- candidate hook failure preserves the old hook session but pauses all correction until
  the controller explicitly retries, preventing old geometry from moving windows;
- Stop invalidates generation before unhooking, cancels timers, clears recent/refusal
  memory, and is idempotent;
- signals for null handles or other objects are ignored; and
- one correction exception is contained and other window keys continue.

- [ ] **Step 2: Run the session test to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowGuardTests
```

Expected: FAIL because `WindowGuard` does not exist.

- [ ] **Step 3: Implement one UI-thread session owner**

Every callback captures a monotonically increasing generation. The public `Start`,
`Pause`, and `Stop` methods are idempotent. Hook registration failure returns a typed
reason for the controller; it never clears overlays. Schedule all seed and event handles
through the same 150-millisecond path.

- [ ] **Step 4: Run all tests and commit**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~WindowGuardTests
dotnet test native/windows/ScreenFix.slnx -c Release
git add native/windows/src/ScreenFix.App/Guard native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: own Windows guard sessions"
```

### Task 7: Integrate guard availability and lifecycle degradation

**Files:**

- Modify: `native/windows/src/ScreenFix.App/Runtime/RuntimeContracts.cs`
- Modify: `native/windows/src/ScreenFix.App/Runtime/RuntimeController.cs`
- Modify: `native/windows/src/ScreenFix.App/Runtime/RuntimeState.cs`
- Modify: `native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`
- Create: `native/windows/tests/ScreenFix.App.Tests/RuntimeGuardIntegrationTests.cs`
- Modify: `native/windows/tests/ScreenFix.App.Tests/LifecycleTests.cs`

- [ ] **Step 1: Write failing integration tests**

Prove the guard runs only when configuration is enabled, the saved display is connected,
masks are committed successfully, calibration is closed, and the app is not suspended.
Prove each transition independently:

- successful startup: masks commit, then guard starts with the same three native frames;
- calibration start pauses/stops guard but preserves committed masks underneath;
- Save/Cancel restores guard after normal masks reconcile;
- mask failure preserves old masks but pauses guard;
- disable/disconnect/suspend stops guard before closing masks;
- reconnect/resume/reload retries without duplicate hooks;
- hook failure leaves masks active and shows
  `Paused: Window correction unavailable`;
- hook recovery removes that row and resets its one-shot notice episode;
- elevated-window refusal never creates a global paused row; and
- invalid configuration reload preserves the previously committed runtime but pauses
  guard until a valid reload.

- [ ] **Step 2: Run integration tests to prove RED**

```bash
dotnet test native/windows/tests/ScreenFix.App.Tests/ScreenFix.App.Tests.csproj -c Release --filter FullyQualifiedName~RuntimeGuardIntegrationTests
```

Expected: at least the Phase 2 placeholder status and missing guard paths fail.

- [ ] **Step 3: Integrate and remove the Phase 2 placeholder**

Replace `Paused: Window correction is not available in this build` with actual dynamic
guard status. Keep exactly one optional disabled status row with final priority:

```text
1. Paused: Invalid configuration
2. Paused: Mask rendering failed
3. Paused: Selected display is disconnected
4. Paused: Select a monitor
5. Paused: Window correction unavailable
```

Intentional Disable and calibration show no paused row. Add transition tests proving
configuration/display/mask failures outrank guard failure and recovery reveals the next
applicable reason without ever rendering two status rows.

`Reload` rereads a candidate configuration and fresh topology, stages masks, then
commits controller state and starts the guard. If load/validation/staging fails, retain
the old visible set, leave the invalid bytes untouched, pause guard, and report once.

- [ ] **Step 4: Prove final teardown order**

Update lifecycle tests to require:

```text
invalidate controller/session callbacks
unhook WinEvents and stop every guard/editor timer
release system-message handle
close editor
close masks
dispose menu
hide and dispose NotifyIcon
release mutex
```

All cleanup continues after individual failures; late posted work is generation-inert.

- [ ] **Step 5: Run tests, build, and commit**

```bash
dotnet test native/windows/ScreenFix.slnx -c Release
dotnet build native/windows/ScreenFix.slnx -c Release --no-restore
git add native/windows/src/ScreenFix.App native/windows/tests/ScreenFix.App.Tests
git commit -m "feat: integrate Windows window guard"
```

### Task 8: Harden the final single-file package and concise installation guide

**Files:**

- Modify: `native/windows/scripts/assert-win-x64-package.ps1`
- Modify: `native/windows/scripts/publish-win-x64.ps1`
- Modify: `README.md`

- [ ] **Step 1: Extend the package assertion and prove RED on bad fixtures**

Keep all reviewed Phase 1 checks, including PE32+ bounds/magic regression fixtures.
Additionally validate:

- PE subsystem is `2` (`IMAGE_SUBSYSTEM_WINDOWS_GUI`);
- executable length is nonzero and a SHA-256 can be computed; and
- the recursive output still contains exactly one regular file.

Retain the existing wrong-machine, malformed-header, and companion-file tests. Add a
minimal console-subsystem fixture, run it separately, and assert its distinct diagnostic.
Delete only the exact temporary directory.

- [ ] **Step 2: Update publish metadata without changing the package shape**

Set stable assembly/file/product version properties in the project. Publish remains
`win-x64`, self-contained, single-file, untrimmed, no symbols. If a release environment
provides a signing command/certificate, sign the one produced executable and rerun the
same assertion; do not add credentials or assume unsigned local builds are warning-free.

- [ ] **Step 3: Update the README only after the executable passes**

Keep `README.md` concise. Add:

```text
Windows x64 installation
1. Download ScreenFix-windows-x64.zip (or ScreenFix.exe).
2. Extract it if zipped.
3. Double-click ScreenFix.exe.
4. Open the tray icon, choose Select Monitor, calibrate, then Save.
5. Windows may show SmartScreen for an unsigned local build; choose More info only if
   the file came from the trusted project release.
```

State Windows x64 means ordinary Intel/AMD 64-bit Windows, not Windows on ARM. State the
normal-integrity limitation for elevated windows and that no separate .NET runtime is
needed. Remove all Phase 1/Phase 2 wording that implies commands are disabled or window
correction is unfinished.

- [ ] **Step 4: Publish and prove final shape**

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
pwsh -NoProfile -Command "Get-FileHash 'native/windows/artifacts/windows/win-x64/ScreenFix.exe' -Algorithm SHA256"
```

Expected: one PE32+ Windows GUI AMD64 executable and a SHA-256 value.

- [ ] **Step 5: Commit release hardening**

```bash
git add native/windows/scripts native/windows/src/ScreenFix.App/ScreenFix.App.csproj README.md
git commit -m "build: finalize Windows x64 package"
```

### Task 9: Complete automated verification from a clean tree

**Files:** None unless a proven defect requires a test-first correction.

- [ ] **Step 1: Verify formatting**

```bash
dotnet format native/windows/ScreenFix.slnx --verify-no-changes
```

Expected: exit 0.

- [ ] **Step 2: Clean, restore, build, and test**

```bash
dotnet clean native/windows/ScreenFix.slnx -c Release
dotnet restore native/windows/ScreenFix.slnx
dotnet build native/windows/ScreenFix.slnx -c Release --no-restore
dotnet test native/windows/ScreenFix.slnx -c Release --no-build
```

Expected: zero warnings, zero errors, all tests pass.

- [ ] **Step 3: Publish twice to prove exact-output cleanup**

```bash
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/publish-win-x64.ps1
pwsh -NoProfile -File native/windows/scripts/assert-win-x64-package.ps1
```

Expected: both publishes succeed and only one executable remains.

- [ ] **Step 4: Check repository state**

```bash
git diff --check
git status --short
```

Expected: no uncommitted source/docs and no whitespace errors. The ignored final
artifact may remain in `native/windows/artifacts/windows/win-x64/`.

### Task 10: Pass end-to-end UAT on physical Windows x64

**Files:** None unless UAT proves a defect.

- [ ] **Step 1: Verify installation and single-instance lifecycle**

Use a supported Windows x64 machine without a separately installed .NET 10 runtime.
Copy only `ScreenFix.exe`, launch it, confirm one tray icon/no taskbar window, launch it
again, confirm no duplicate, then Quit and confirm no process, hooks, mask windows, or
tray icon remain.

- [ ] **Step 2: Re-run all Phase 2 display/mask/calibration UAT**

Test a 3440-by-1440 damaged monitor, negative-origin secondary monitor, 100%/150% mixed
DPI, top/left taskbar, disconnect/reconnect, scale/resolution changes, sleep/wake, click-
through, held mouse drag, held trackpad drag, tap-move-tap, all four resizes, snapping,
Save/Cancel/toggle-cancel, Reload, Disable/Enable, and exact Reset.

- [ ] **Step 3: Verify existing and newly shown windows**

With Notepad, File Explorer, and a browser:

- launch each intersecting a band and verify correction after about 150 milliseconds;
- move and resize into top, middle, and bottom bands;
- span multiple bands with a tall window;
- verify nearest-side selection, necessary-only shrinking, and exact-tie left choice;
- verify work-area clamping with taskbar on every available edge;
- verify a maximized ordinary window restores into a safe normal frame;
- verify the corrected app does not gain focus when another app was foreground; and
- verify a borderless full-screen window remains unchanged;
- verify a tool window, native menu, desktop, shell window, owned popup, and non-movable
  window remain unchanged; and
- compare inspector diagnostics for a framed window and a DWM-framed window so visible-
  to-outer edge offsets and selected-monitor mapping match the actual native rectangles.

- [ ] **Step 4: Verify suppression and degraded behavior**

Generate repeated move/resize events and prove no oscillation or retry storm. Use the
focused harness to delay a target thread for less than 500 milliseconds and prove the
pending write is not falsely refused or duplicated; then delay beyond the deadline and
prove the one-second cooldown. Run one target app elevated: ScreenFix must remain non-
elevated, masks stay visible, refused writes cool down for one second, and normal-
integrity windows still correct. Exercise a hook-install failure with a focused test
build or injectable harness: the menu must show window correction paused while masks
and calibration continue.

- [ ] **Step 5: Record release evidence**

Record Windows edition/build, machine architecture, GPU, monitor origins/resolutions/
DPI, artifact byte size and SHA-256, whether it is signed, and every UAT result in the
release handoff. Do not claim the Windows package complete without this Windows evidence;
a macOS cross-build proves package structure, not runtime behavior.

If any UAT step fails, identify a consistent reproduction, add the smallest failing test
or focused Windows harness, prove RED, fix minimally, prove GREEN, rerun the affected UAT,
then rerun Tasks 9 and 10.

## Final Windows completion gate

The Windows workstream is complete only when:

- all Phase 1, Phase 2, and Phase 3 automated tests pass;
- every menu command is real and no intermediate-build status remains;
- stable display identity, negative origins, mixed DPI, and reconnect are proven;
- three opaque click-through masks rebuild transactionally and keep old masks on a
  replacement failure;
- mouse and trackpad held/tap-move-tap movement and edge resizing pass;
- startup/existing/new/shown/moved/resized eligible windows correct after 150 ms;
- self-events suppress for 250 ms and refusals cool down for one second per window;
- masks remain usable when hooks or elevated-window writes fail;
- teardown ordering and stale-generation rejection are proven;
- physical Windows x64 UAT passes; and
- the distributable is one self-contained PE32+ Windows GUI AMD64 `ScreenFix.exe` with
  recorded size and SHA-256.
