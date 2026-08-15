# Calibration Polish Design

## Dropdown reset

The SF menu adds `Reset to Defaults` between `Select Monitor` and `Reload`. It is
disabled when the persisted selected monitor is not connected. Invocation reloads
the persisted configuration and re-resolves that monitor; an unsaved monitor being
previewed in calibration is never treated as the reset target. The action first
revokes chooser/calibration sessions and stops the editor, then restores the
built-in three-band layout for the live persisted monitor, preserves the persisted
Enable/Disable state, saves immediately, and refreshes mask/window-guard state.
Stale chooser and calibration callbacks cannot overwrite the reset.

If the monitor disconnects after the menu opens, defaults cannot be constructed,
or saving fails, no new value is persisted. Calibration stays canceled, the prior
saved configuration is refreshed, and one reset-failure notification is shown for
that failure episode. A later successful reset clears the episode.

## Magnetic snapping

Calibration uses a 12-point magnetic threshold:

- Red-body movement preserves size and may snap its left/right and top/bottom
  edges to the screen or any edge of another band.
- White-edge resizing snaps only the edge being resized; the opposite edge stays
  fixed and the existing 20-point minimum remains enforced.
- Horizontal and vertical snapping are independent.
- The active band is excluded from targets. Orthogonal overlap is not required, so
  vertically stacked bands can align their left/right edges and side-by-side bands
  can align top/bottom edges.
- A closest correction wins. Equal-distance ties use: screen start, screen end,
  peer band index ascending with peer start before peer end, then active leading
  edge before active trailing edge.
- Illegal targets are discarded: body translations must stay within the screen;
  resize results must stay within the screen and remain at least 20 points wide
  and high.
- A snapped edge stays snapped until raw movement exceeds 12 points, avoiding
  one-pixel seams without trapping the pointer.

Each drag stores an unsnapped `rawBand`. Every accepted pointer delta updates that
raw band through ordinary clamp/resize geometry; snapping then derives the visible
working band from the raw candidate, the other two visible bands, and the screen
size. Because discarded deltas still accumulate in `rawBand`, moving more than 12
points away releases a snap. The raw band is initialized on selection and cleared
on drop, Cancel, Save, replacement, and stop.

## Verification

Tests cover menu placement/state/action/error boundaries; reset during calibration;
disabled-state preservation; stale callbacks; all body/edge snap directions;
screen and peer edges; exact 12-point boundary; outside-threshold behavior; ties;
20-point minimum; and both held and latched integration. Live acceptance checks a
screen-edge snap and a peer-band seam in both the held-drag and tap-move-tap event
streams before Cancel restores saved settings. macOS normalizes mouse and trackpad
input into those same two event streams.
