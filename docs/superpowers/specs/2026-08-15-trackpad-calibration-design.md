# Trackpad-Friendly Calibration Design

## Problem

The calibration canvas recognizes a press on a band or white edge, but its canvas
callback does not reliably deliver movement while the pointer is dragged. A quick
trackpad tap also releases the band before the pointer can move.

## Interaction

Calibration supports both input styles:

- Mouse or pressed trackpad: press a target, move, and release.
- Tap-based trackpad: tap a target once to pick it up, move the pointer, and tap
  again to drop it.

Target behavior stays distinct:

- The red center moves the whole band without changing its size.
- The left and right white edges resize the band's width.
- The top and bottom white edges resize the band's height.

Save and Cancel remain normal single-click controls. No modifier key or macOS
trackpad setting is required.

## Implementation

The canvas owns only hit testing for mouse-down events. Canvas mouse-move and
mouse-up tracking are disabled. A calibration-scoped `hs.eventtap` is the sole
owner of `leftMouseDragged`, `mouseMoved`, and `leftMouseUp`; it converts each
event's global location to canvas-local coordinates and updates the selected band.
Every event-tap callback path returns `false`, including caught errors, so
calibration never consumes a system mouse event.

A drag records whether it has moved and whether it is latched:

- Movement must reach four points from the press before it counts as a drag; the
  first accepted update applies the full accumulated delta so precision is not
  lost to the threshold.
- A held-button movement updates the band and release drops it.
- A release before accepted movement latches the selection.
- Pointer movement updates a latched selection without a held button.
- Save and Cancel execute immediately even while a selection is latched.
- Any other next press drops a latched selection without starting another one.

Each editor and event tap captures a monotonically increasing session token and
ignores callbacks after that token is invalidated. Candidate startup is
transactional: failure stops and deletes only the candidate and restores the old
editor with its event tap still enabled; success retires the old event tap and
canvas after committing the replacement.

Teardown invalidates the session first, stops and clears its event tap, clears drag
and editor state, and then deletes the canvas. It is idempotent and contains stop
or delete errors. Runtime movement errors are reported and leave the editor live;
Save callback errors also retain the editor, matching existing behavior. Cancel,
successful Save, replacement, and controller teardown fully stop the event tap.

## Verification

Automated tests cover mouse hold-drag-release, trackpad tap-move-tap, body movement,
all four resize edges, controls, replacement rollback, and teardown. Live
verification must move a body and resize a white edge through real Hammerspoon
mouse events, then cancel and prove the saved `1215–1920` mask is unchanged.
Tests also assert the four-point threshold, stale-session rejection, event
pass-through, candidate rollback, successful replacement retirement, contained
errors, and idempotent stop ordering.
