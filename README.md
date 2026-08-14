# ScreenFix

ScreenFix is a local Hammerspoon configuration for a display with a damaged vertical
region. It places three calibrated black masks over that region and moves or resizes
ordinary windows into the usable space on either side.

Software cannot repair physical screen damage or control dead, leaking, or stuck pixels.
The masks turn responsive pixels black and keep useful content away from the damaged
region; physically black or colored pixels may remain visible.

## Files

```text
.
├── init.lua                         Loads the modules and owns one ScreenFix runtime.
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

## Requirements

- macOS 13 Ventura or later.
- The [current stable Hammerspoon release](https://www.hammerspoon.org/).
- Accessibility permission for moving and resizing windows: System Settings >
  Privacy & Security > Accessibility > Hammerspoon.

The black mask, monitor selection, and calibration work without Accessibility permission.
Until permission is granted, the `SF` menu reports that window protection is paused.
macOS may require Hammerspoon to be relaunched after permission is granted.

## Install

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

Launch Hammerspoon, or choose **Reload Config** if it is already running. The `SF` item appears in the menu bar.

## First run

1. Select the damaged display in the chooser.
2. Move and resize the three black bands until they cover the damaged region.
3. Choose **Save**. ScreenFix remembers the display and calibration, switches to
   click-through masks, and starts window protection when Accessibility is available.

Choose **Cancel** to discard calibration changes.

## Menu and startup

Use the `SF` menu to:

- **Enable** or **Disable** the saved mask and window protection.
- **Calibrate** the three bands again.
- **Select Monitor** and calibrate a different display.
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
