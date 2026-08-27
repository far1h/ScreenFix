# Windows Icons and Maximize Correction Design

Status: approved

## Goal

Give the Windows application one recognizable Screen Patch identity in both places users
see it, and make ordinary maximized windows respect the same safe area as snapped
windows:

- the notification-area icon uses the Screen Patch artwork;
- `ScreenFix.exe` shows the same artwork in Explorer and shortcuts;
- Windows-key-Up and the maximize button restore an ordinary window into the selected
  safe frame when it overlaps a mask; and
- borderless and F11 full-screen windows remain untouched.

The icon and maximize corrections ship together in one focused Windows change. They do
not alter mask geometry, calibration, window-side selection, or the macOS application.

## Proven root causes

### Generic Windows icons

[`native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs`](../../../native/windows/src/ScreenFix.App/ScreenFixApplicationContext.cs)
constructs the `NotifyIcon` with `SystemIcons.Application`. That is a generic system
icon, not ScreenFix artwork.

[`native/windows/src/ScreenFix.App/ScreenFix.App.csproj`](../../../native/windows/src/ScreenFix.App/ScreenFix.App.csproj)
does not set `ApplicationIcon`, embed a branded icon, or include an `.ico` file. The
published PE therefore has no requested ScreenFix application icon for Explorer, and
the runtime has no branded resource to load for the tray.

### Maximized windows do not move

[`native/windows/src/ScreenFix.App/Interop/NativeTypes.cs`](../../../native/windows/src/ScreenFix.App/Interop/NativeTypes.cs)
defines `NativeWindowPlacement` with a trailing `DeviceRectangle`. That makes the
managed structure 60 bytes. The Win32 `WINDOWPLACEMENT` structure ends at
`rcNormalPosition` and is 44 bytes; its `length` member must contain the exact structure
size before `GetWindowPlacement` or `SetWindowPlacement` is called.

[`native/windows/src/ScreenFix.App/Interop/WindowNative.cs`](../../../native/windows/src/ScreenFix.App/Interop/WindowNative.cs)
sets `Length` from `Marshal.SizeOf<NativeWindowPlacement>()`, so both placement calls
receive 60 instead of 44. Their mappings also carry the non-native `DeviceRectangle`
through `WindowPlacementData`.

[`native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs`](../../../native/windows/src/ScreenFix.App/Guard/WindowCorrector.cs)
must restore a zoomed window through `TryGetPlacement` and `TrySetPlacement` before it
applies the safe frame. A failed restore records a refusal and returns without calling
`TrySetFrame`. Snapped windows are not zoomed, so they bypass this placement path and
already fit the safe area. This explains why left/right snapping works while Windows-key-Up
and the maximize button do not.

## Screen Patch artwork

Windows uses the same approved Screen Patch composition as macOS. The canonical source
is a transparent SVG with `viewBox="0 0 220 220"` and this exact geometry:

- background: `x=10`, `y=10`, `width=200`, `height=200`, `rx=45`; diagonal gradient
  from `(28, 18)` to `(192, 207)` with stops `#FFB23E` at 0%, `#F46744` at 54%, and
  `#A92C4D` at 100%;
- display body: `x=38`, `y=54`, `width=144`, `height=103`, `rx=18`, fill `#FFF7E8`;
- display surface: `x=50`, `y=67`, `width=120`, `height=77`, `rx=9`, fill `#FFD8A0`;
- damage paths: `M57 77 L91 134` and `M133 77 L163 126`, stroke `#FF9F61`, width 8,
  rounded ends, opacity 0.8;
- center mask: `x=96`, `y=54`, `width=28`, `height=103`, `rx=8`, fill `#27212B`;
- stand: paths `M88 172 H132` and `M110 158 V172`, stroke `#FFF5E5`, width 10,
  rounded ends; and
- mask marks: horizontal paths from `x=103` to `x=117` at `y=75`, `94`, `113`, and
  `132`, stroke `#F7C46C`, width 4, rounded ends.

The artwork must stay legible at 16 pixels. Small-frame checks therefore verify the
center mask remains distinct and the silhouette does not collapse into the background.

## Icon assets and generation

Store the canonical SVG and one generated multi-resolution ICO under
`native/windows/src/ScreenFix.App/Resources`. The ICO is committed because Windows
publishing must not depend on an SVG renderer. There is only one `.ico`; MSBuild and the
runtime consume that same file.

A small macOS generation script performs this repeatable pipeline when artwork changes.
It requires only repository code plus the system `qlmanage`, `sips`, and `python3`
commands already used for local asset work:

1. Use Quick Look to render the approved SVG to a 1024-pixel PNG in a temporary
   directory.
2. Use `sips` to downsample separate PNG frames at 16, 20, 24, 32, 40, 48, 64, 128,
   and 256 pixels.
3. Use a small Python standard-library packer to write those PNG payloads into one ICO
   directory in ascending size order.
4. Write through a temporary file, reject a directory or symlink output target, set a
   normal `0644` asset mode, and replace the committed ICO only after validation.

The packer and validator stay in the repository rather than relying on an opaque online
converter. Validation parses the ICO header and directory, requires exactly the planned
sizes, checks every offset and length stays within the file without overlap, and checks
each payload's PNG signature and dimensions. It also renders the 256-, 32-, and
16-pixel frames for visual inspection. Generation leaves no PNG or ICO byproducts in
the publish directory.

## One ICO, used twice

`ScreenFix.App.csproj` sets `ApplicationIcon` to the generated ICO so the native apphost
contains an Explorer icon. The project also includes that same file as an
`EmbeddedResource` with a stable logical name for tray loading.

A short resource loader opens the manifest resource, constructs an `Icon`, clones it,
then closes the source `Icon` and stream. The clone is assigned to `NotifyIcon` and is
owned for the application lifetime. Teardown hides and disposes `NotifyIcon` before
disposing the cloned icon handle. This ordering prevents the tray component from
referencing a closed stream or destroyed handle.

If the embedded resource is missing or invalid at runtime, the loader catches that load
failure and returns an owned clone of `SystemIcons.Application`. The fallback keeps the
menu usable, but it is not used during a successful branded load and does not hide
build-time or package-test failures.

## Correct `WINDOWPLACEMENT` interop

Remove `DeviceRectangle` from all layers of placement data:

- remove the field from `NativeWindowPlacement`;
- remove it from `WindowPlacementData`;
- remove it from native-to-managed and managed-to-native mappings; and
- update constructors and test fakes that currently supply it.

Keep `Length = (uint)Marshal.SizeOf<NativeWindowPlacement>()`, but add a portable test
that first proves `Marshal.SizeOf<NativeWindowPlacement>() == 44`. This makes the ABI
contract explicit and prevents another trailing field from silently breaking both
placement calls.

No correction policy changes are needed. Once the exact placement structure allows
`TryRestoreWithoutActivation` to succeed, the existing corrector restores a normal
maximized window without activation and applies its already-selected safe outer frame
with no z-order change. The existing borderless/full-screen eligibility check remains
the authority, so exclusive, borderless, and F11 full-screen windows never enter this
restore path.

## Test-first implementation

Work in small red-green increments.

### Icon tests

1. Add a generator regression test that fails while the ICO is absent, incomplete, or
   has the wrong frame table.
2. Add a Windows application test that resolves the stable manifest-resource name,
   loads the embedded ICO, clones it after closing the resource stream, and proves the
   clone remains usable. Prove the fallback separately with a missing-resource case.
3. Extend the package assertion regression test so a package without the canonical
   embedded ICO bytes is rejected.
4. Extend the PE assertion so a package without `RT_GROUP_ICON` and its referenced
   `RT_ICON` images is rejected. Require the final published executable's group-icon
   dimensions to match the canonical ICO frames.
5. Publish and assert the real `ScreenFix.exe`, proving both the managed tray resource
   and native Explorer icon survived single-file bundling.

The managed embedded resource is checked independently from PE resources: the tray
loader reads the former, while Explorer reads the latter. Finding one must never be
accepted as proof of the other.

### Maximize tests

1. Link the native placement structure into the portable app test assembly and add a
   failing `Marshal.SizeOf<NativeWindowPlacement>() == 44` assertion. It initially
   reports 60 and proves the interop defect without requiring Windows.
2. Remove `DeviceRectangle` and update the placement mappings and existing corrector
   fixtures until the portable tests pass.
3. Add a Windows-native probe that creates a normal resizable top-level window,
   maximizes it using the same Win32 zoomed state produced by Windows-key-Up and the
   maximize button, and asserts `TryGetPlacement` succeeds.
4. Use the production placement writer to restore the probe without activation, apply
   a known safe outer frame, pump pending window messages, and assert the end state is
   not zoomed and its final rectangle equals the safe target.
5. Retain or add eligibility coverage proving a borderless full-screen probe is
   excluded and never restored.

## Verification

Focused checks run after each increment; full checks run before the pull request:

- ICO generator and parser regression tests;
- portable `ScreenFix.Core.Tests` and `ScreenFix.App.Tests`;
- Windows-targeted tests compile on the development host;
- `test-windows-native.ps1` executes the real maximize probe on Windows;
- package assertion regression tests;
- self-contained `win-x64` publish and final package assertion; and
- repository-wide Lua and native macOS suites to catch unrelated regressions.

Manual Windows acceptance uses an ordinary resizable application on the damaged
display:

1. Confirm the Screen Patch appears in the notification area, Explorer, and an `.exe`
   shortcut at normal and high DPI.
2. Drag the window across a mask and press Windows-key-Up; confirm it settles entirely
   into the selected safe side.
3. Repeat with the maximize button.
4. Confirm Windows-key-Left and Windows-key-Right still fit the same safe region.
5. Enter borderless or F11 full screen and confirm ScreenFix does not move the window.

## Expected files

Implementation is expected to stay within the Windows application, tests, and scripts:

```text
native/windows/
├── scripts/
│   ├── assert-win-x64-package.ps1
│   ├── build-app-icon.sh
│   ├── icon_ico.py
│   ├── test-assert-win-x64-package.ps1
│   └── test-build-app-icon.sh
├── src/ScreenFix.App/
│   ├── Guard/WindowCorrector.cs
│   ├── Interop/NativeTypes.cs
│   ├── Interop/WindowNative.cs
│   ├── Resources/ScreenFixAppIcon.svg
│   ├── Resources/ScreenFix.ico
│   ├── Runtime/TrayIconLoader.cs
│   ├── ScreenFix.App.csproj
│   └── ScreenFixApplicationContext.cs
└── tests/
    ├── ScreenFix.App.Tests/
    │   ├── NativeWindowPlacementTests.cs
    │   └── WindowCorrectorTests.cs
    └── ScreenFix.Windows.Tests/
        ├── TrayIconLoaderTests.cs
        └── WindowNativePlacementTests.cs
```

Exact test-file grouping may follow existing project conventions, but production code
must keep icon loading separate from application orchestration and placement ABI data
separate from correction policy.

## Acceptance criteria

- The notification-area icon and Explorer `.exe` icon both display the approved Screen
  Patch artwork from one multi-resolution ICO.
- The ICO contains validated 16, 20, 24, 32, 40, 48, 64, 128, and 256 pixel frames.
- Tray icon ownership remains valid after its resource stream closes and is disposed in
  the correct order at application shutdown.
- `NativeWindowPlacement` is exactly 44 bytes on the portable test host and Windows.
- An ordinary window maximized with Windows-key-Up or the maximize button is restored
  and placed entirely within the same safe candidate used for snapping.
- Existing left/right snap correction continues to pass.
- Borderless, exclusive, and F11 full-screen windows remain untouched.
- The final single-file `ScreenFix.exe` passes explicit checks for both its embedded tray
  resource and PE group icon.
