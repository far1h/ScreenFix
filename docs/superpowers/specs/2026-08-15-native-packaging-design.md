# Native ScreenFix Packaging Design

Status: approved assumption

## Goal

Ship ScreenFix as applications that a non-developer can copy and launch without running
source code:

- one self-contained `ScreenFix.exe` for ordinary 64-bit Intel and AMD Windows PCs;
- one native `ScreenFix.app` zip for macOS 13 or later on Apple Silicon; and
- no Hammerspoon, Lua, .NET runtime, or other separately installed runtime on either
  target device.

The native apps implement the shared behavior in
[`docs/screenfix-behavior-contract.md`](../../screenfix-behavior-contract.md). The existing
Hammerspoon version remains usable and is not rewritten in place.

## Release assumptions

- Windows targets the current .NET 10 LTS SDK, C# 14, WinForms, and direct Win32
  interop. .NET 10 is supported through November 2028. The release RID is `win-x64`.
- macOS targets macOS 13+, Swift, AppKit, Core Graphics, and the Accessibility API. The
  release architecture is `arm64` only.
- The first reproducible artifacts may be unsigned or ad-hoc signed. Public,
  warning-free downloads additionally require publisher-owned signing credentials.
- No installer is needed initially. Users extract or copy the single Windows executable,
  or extract the macOS zip and drag the app to Applications.

## Repository layout

```text
global.json                            Stable .NET 10 SDK selection
native/
├── windows/
│   ├── ScreenFix.slnx
│   ├── src/
│   │   ├── ScreenFix.Core/          Pure configuration and geometry
│   │   └── ScreenFix.App/           WinForms tray app and Win32 adapters
│   ├── tests/
│   │   ├── ScreenFix.Core.Tests/    Platform-independent contract tests
│   │   └── ScreenFix.App.Tests/     Portable app ownership tests
│   └── scripts/
│       ├── assert-win-x64-package.ps1
│       └── publish-win-x64.ps1
└── macos/
    ├── Package.swift
    ├── Sources/
    │   ├── ScreenFixCore/            Pure configuration and geometry
    │   └── ScreenFixApp/             AppKit menu app and macOS adapters
    ├── Tests/
    │   └── ScreenFixCoreTests/
    └── scripts/
        └── package-arm64.sh
```

Keep the two native cores small and deliberately equivalent. The behavior contract and
platform-specific golden fixtures, rather than shared runtime code or a cross-platform
UI framework, prevent drift.

## Windows architecture

### Application shell and package

`ScreenFix.App` is a WinForms `WinExe` with no main form. Its project is scaffolded from
the portable console template so the same plan works from macOS and Windows, then the
project explicitly enables WinForms and Windows targeting. `Program.Main` calls
`ApplicationConfiguration.Initialize()` and runs a custom `ApplicationContext`. The
context owns one `NotifyIcon`, one `ContextMenuStrip`, a per-user named mutex, display
notifications, overlays, hooks, timers, and teardown.

`ScreenFix.App.Tests` links only the app's runtime-neutral lifecycle source files into a
`net10.0` test assembly. This proves mutex gating and cleanup ordering on non-Windows
development hosts without moving OS-backed ownership into the pure cross-platform core.

The project opts into PerMonitorV2 DPI awareness and requests `asInvoker`; ScreenFix
must never require administrator rights. Menu commands delegate to one runtime
controller instead of mutating windows directly. A second process detects the mutex and
exits without acquiring resources.

Publishing uses `dotnet publish` with `net10.0-windows`, `win-x64`, self-contained mode,
single-file bundling, bundled native libraries, trimming disabled, and symbols disabled.
The script writes to `artifacts/windows/win-x64` and fails unless the only regular file is
`ScreenFix.exe`. The target PC does not need .NET installed.

This follows Microsoft's current guidance for `ApplicationConfiguration.Initialize`,
[`NotifyIcon`](https://learn.microsoft.com/en-us/dotnet/desktop/winforms/controls/notifyicon-component-windows-forms),
and [self-contained single-file publishing](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview).

### Display and overlay adapters

Enumerate monitor rectangles with `EnumDisplayMonitors` and `GetMonitorInfo`. Resolve
the active display-config path with `QueryDisplayConfig`; obtain the target device path,
friendly name, and EDID identifiers with `DisplayConfigGetDeviceInfo`. The target device
path is the primary persisted identity.

Create one borderless WinForms overlay per mask band. Each committed normal overlay is
opaque black, omitted from the taskbar, shown without activation, and given
`WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT`; it is positioned with
`SetWindowPos` as topmost. Rebuild candidates transactionally and preserve negative
virtual-desktop origins.

A message-only `NativeWindow` receives `WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE`, and power
broadcasts. It triggers the same idempotent reconcile path used by Reload and wake.

### Calibration adapter

Calibration uses one borderless PerMonitorV2 editor over the selected display. Only the
editor is interactive; committed black overlays remain separate. The editor draws the
three translucent red bands, white 8-point edges, polished instruction, and Save/Cancel
controls. It handles `MouseDown`, `MouseMove`, `MouseUp`, and `MouseCaptureChanged` to
implement both held drag and tap-move-tap from the shared contract.

All pure movement, resize, hit-test, and snap calculations stay in `ScreenFix.Core`.
Windows scales 4-, 8-, 12-, and 20-point thresholds by the monitor DPI before passing
native-pixel values to the core. Losing capture or display ownership cancels the active
gesture safely. Editor replacement remains transactional.

### Window guard adapter

Use out-of-context `SetWinEventHook` subscriptions for object show and location changes,
move/resize completion, and foreground changes, skipping ScreenFix's own process.
`EnumWindows` seeds already-visible windows at startup. Copy callback data immediately
and dispatch all reconciliation to the WinForms UI thread; keep delegate instances alive
until `UnhookWinEvent` completes.

Eligibility uses `IsWindowVisible`, `IsIconic`, root ownership, styles, process identity,
monitor identity, and borderless full-screen detection. A maximized standard window is
restored into the chosen safe normal frame; exclusive or borderless full-screen windows
remain untouched. Geometry uses `GetWindowRect` and the selected monitor's `rcWork`;
corrections use Win32 placement APIs without changing z-order. Elevated windows can
reject operations because the app deliberately runs at normal integrity. That is
reported as a per-window refusal, not a runtime failure.

## Native macOS architecture

### Application shell and package

`ScreenFixApp` is an AppKit menu-bar application with activation policy `.accessory` and
`LSUIElement=true`. It retains one variable-length `NSStatusItem`, installs the shared
menu contract, and owns one runtime controller. Launch Services prevents multiple app
instances; `LSMultipleInstancesProhibited` documents that requirement explicitly.

Swift Package Manager builds an `arm64` release executable. `package-arm64.sh` creates a
standard `ScreenFix.app/Contents` bundle, copies the executable and resources, writes the
versioned `Info.plist`, ad-hoc signs the bundle for local testing, and zips it with
`ditto --keepParent`. A release mode accepts a Developer ID identity and uses
`notarytool` outside the source tree; credentials never enter the repository.

### Display and overlay adapters

Read live screens from `NSScreen.screens` on every reconcile. Obtain each
`CGDirectDisplayID` from `NSScreen.deviceDescription["NSScreenNumber"]`, then persist the
UUID returned by `CGDisplayCreateUUIDFromDisplayID`; retain vendor, model, and serial as
diagnostics. Use name and dimensions only as the conservative unique fallback in the
behavior contract.

Each band is a borderless, opaque black `NSPanel`. Normal panels use
`ignoresMouseEvents=true`, do not become key or main, and use a nonactivating style.
Their collection behavior includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and
`.stationary`; their level stays above ordinary app content. Candidate panels are fully
configured and ordered before the old set is closed.

Listen for `NSApplication.didChangeScreenParametersNotification` and workspace wake
notifications. Convert AppKit bottom-left screen rectangles to the core's top-left
coordinate system at one adapter boundary.

Apple documents that [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens)
must not be cached and that display changes emit the screen-parameters notification.
The status app retains its [`NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:))
for its full lifetime.

### Calibration adapter

Use one transparent full-display `NSPanel` with a custom `NSView`. The view accepts
mouse-moved events and implements `mouseDown`, `mouseDragged`, `mouseMoved`, and
`mouseUp` for held and latched gestures. It draws the same geometry and styling as the
approved calibration controls. Because calibration handles events in ScreenFix's own
window, it does not need global input capture or Hammerspoon.

### Window guard adapter

Ask for Accessibility trust with `AXIsProcessTrustedWithOptions`. The mask continues if
permission is missing; only the guard pauses. Enumerate running GUI applications with
`NSWorkspace`, attach `AXObserver` callbacks for window-created, moved, resized, and
focused-window changes, and seed current windows before waiting for callbacks.

Read and write `kAXPositionAttribute`, `kAXSizeAttribute`, minimized state, role,
subrole, and full-screen state. Convert Accessibility's top-left global coordinates at
the adapter boundary. Apps that reject writes enter the one-second refusal cooldown.
Observer callbacks carry runtime and session generations so teardown makes late events
inert.

## Persistence

Windows writes `%LOCALAPPDATA%\ScreenFix\config.json`. macOS writes
`~/Library/Application Support/ScreenFix/config.json`. Both use UTF-8 JSON, the schema in
the behavior contract, and an atomic temporary-file replacement. Invalid files are
reported and preserved for diagnosis instead of silently overwritten. Reset is the only
command that recreates defaults for an already selected display.

## Signing and user installation

### Windows

The development artifact is one `ScreenFix.exe`: copy it anywhere and double-click.
Authenticode signing is optional for local transfer but required to establish publisher
reputation and reduce SmartScreen warnings in a public release. Code-sign after publish,
then repeat the one-file assertion.

### macOS

Extract `ScreenFix-macos-arm64.zip`, drag `ScreenFix.app` to Applications, and open it.
An ad-hoc build may require Control-click, Open once. A public release signs all nested
code with Developer ID, submits the zip for notarization, and distributes the notarized
result. No Hammerspoon process needs to be open.

## Delivery sequence

1. Windows Phase 1: solution, contract geometry/config core, tested JSON store, minimal
   tray shell, and asserted single-file `win-x64` publish.
2. Windows Phase 2: monitor identity, transactional overlays, and calibration.
3. Windows Phase 3: window guard, display/power lifecycle, permission limitations, and
   end-to-end validation on a physical Windows x64 machine.
4. macOS Phase 1: Swift core parity and menu-bar app bundle.
5. macOS Phase 2: panels, calibration, Accessibility guard, lifecycle, and signed/notarized
   release automation.

Each phase must leave a runnable artifact and keep the platform-neutral golden fixtures
green before the next phase starts.

## Acceptance criteria

- `ScreenFix.exe` launches on Windows x64 without an installed .NET runtime, creates one
  tray instance, and eventually implements the full shared behavior contract.
- `ScreenFix.app` launches on macOS 13+ Apple Silicon without Hammerspoon, creates one
  menu-bar instance, and eventually implements the full shared behavior contract.
- Reset always restores the exact permanent 1215-to-1920 defaults on a 3440-wide display.
- Both calibration input styles, edge and peer snapping, guard selection, and lifecycle
  failure behavior match the shared golden cases.
- The black mask still works when cross-app window-control permission is unavailable.
- Package scripts fail rather than publishing an incomplete, multi-file, wrong-RID, or
  wrong-architecture artifact.
