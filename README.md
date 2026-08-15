# ScreenFix

ScreenFix masks a damaged vertical display region and keeps ordinary windows in the
usable space on either side. The current implementation runs through Hammerspoon;
standalone Windows and macOS packages are under development.

![A MacBook display with a damaged vertical band](D75077A6-60A3-41E7-998E-AA33DABA7046.PNG)

*The very practical reason ScreenFix exists.*

## Result

Calibrating the three masks:

![ScreenFix calibration on the damaged ultrawide display](assets/results/screenfix-result-1.jpg)

Saved click-through masks:

![ScreenFix masking the damaged region after saving](assets/results/screenfix-result-2.jpg)

Software cannot repair physical screen damage or control dead, leaking, or stuck pixels.
The masks turn responsive pixels black and keep useful content away from the damaged
region; physically black or colored pixels may remain visible.

## Files

```text
.
├── init.lua                         Loads the modules and owns one ScreenFix runtime.
├── assets/results/                  Shows calibration and the saved result.
├── screenfix/
│   ├── calibration.lua             Provides monitor selection and the three-band editor.
│   ├── controller.lua              Coordinates lifecycle, menu actions, and runtime state.
│   ├── geometry.lua                Calculates mask positions and safe window frames.
│   ├── mask_overlay.lua            Renders click-through black masks across Spaces.
│   ├── screen_config.lua           Validates, saves, and restores monitor calibration.
│   └── window_guard.lua            Detects overlaps and corrects eligible windows.
└── tests/
    ├── run.lua                     Runs the complete Lua test suite.
    ├── test_helper.lua             Supplies the dependency-free test harness.
    ├── fake_hs.lua                 Supplies focused Hammerspoon test doubles.
    └── *_test.lua                  Tests each production module and the entry point.
```

## Install the native macOS app

> The standalone Apple Silicon app is not built yet. These steps apply when a release
> includes `ScreenFix-macos-arm64.zip`.

1. Download and open `ScreenFix-macos-arm64.zip`.
2. Drag **ScreenFix.app** into **Applications**.
3. Open ScreenFix. For an unsigned test build, Control-click the app, choose **Open**,
   then confirm once. A signed and notarized release opens normally.
4. When prompted, allow ScreenFix in **System Settings > Privacy & Security >
   Accessibility**. This permission is needed to move or resize other apps' windows;
   the black masks work without it.
5. Choose the ScreenFix menu-bar icon, select the damaged monitor, calibrate the three
   bands, and choose **Save**.

The native app does not require Hammerspoon or a source checkout.

## Hammerspoon version requirements

- macOS 13 Ventura or later.
- The [current stable Hammerspoon release](https://www.hammerspoon.org/).
- Accessibility permission for calibration pointer movement and for moving or resizing
  windows: System Settings > Privacy & Security > Accessibility > Hammerspoon.

The black mask and monitor selection work without Accessibility permission. Calibration
movement and window protection remain unavailable until permission is granted. macOS may
require Hammerspoon to be relaunched afterward.

## Install the Hammerspoon version

From the ScreenFix project directory, inspect the destination first:

```bash
ls -ld ~/.hammerspoon ~/.hammerspoon/ScreenFix ~/.hammerspoon/init.lua 2>/dev/null || true
```

If `~/.hammerspoon/ScreenFix` already exists, stop and inspect it. Do not replace it automatically.

When the destination is free, create the configuration directory and link this project:

```bash
mkdir -p ~/.hammerspoon
ln -s "$PWD" ~/.hammerspoon/ScreenFix
```

Add exactly this line once to `~/.hammerspoon/init.lua`. Preserve all existing
configuration; create the file only if it does not exist.

```lua
dofile(hs.configdir .. "/ScreenFix/init.lua")
```

Launch Hammerspoon, or choose **Reload Config** if it is already running. The ScreenFix
display icon appears in the menu bar.

## First run

1. Select the damaged display in the chooser.
2. Move a band from its red center, or resize it from a white edge, until it covers the
   damaged region. Red bands and white resize edges snap within 12 points of the display
   boundary or another band.
3. With a mouse, hold, drag, and release. With a trackpad, tap the target once, move the
   pointer without holding, then tap again. No Shift key is needed.
4. Choose **Save**. ScreenFix remembers the display and calibration, switches to
   click-through masks, and starts window protection when Accessibility is available.

Choose **Calibrate** again from the ScreenFix menu, or choose the gray **Cancel**
control, to exit and discard calibration changes.

## Menu and startup

Use the ScreenFix menu to:

- **Enable** or **Disable** the saved mask and window protection.
- **Calibrate** the three bands again.
- **Select Monitor** and calibrate a different display.
- **Reset to Defaults** and restore the permanent 1215–1920 horizontal mask span on a
  3440-point display, with the original three vertical sections.
- **Reload** the Hammerspoon configuration.

To start ScreenFix after login, enable Hammerspoon's **Launch at login** preference.
The documented Console equivalent is `hs.autoLaunch(true)`.

## Disable or uninstall

Choose **Disable** to remove the masks and stop window correction without deleting the saved calibration.

To uninstall:

1. Choose **Disable**.
2. Remove only the ScreenFix `dofile` line from `~/.hammerspoon/init.lua`, leaving the rest of the file unchanged.
3. Reload or quit Hammerspoon.
4. Inspect `~/.hammerspoon/ScreenFix` with `ls -ld`. If it is the symbolic link created
   above, remove only the link with `unlink ~/.hammerspoon/ScreenFix`.

Removing the link does not delete the project directory.

## Collaborating

Run the complete test suite from the project root with Lua 5.4 or later:

```bash
lua tests/run.lua
```
