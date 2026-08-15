# Calibration Controls Polish Design

## Goal

Polish the existing macOS calibration controls without changing their placement or
interaction model. The instruction badge stays at the top-left of the selected display,
and Save and Cancel stay at the bottom-left.

The change must fix the uneven button spacing and clipped instruction text shown in the
user's screenshots while preserving all mask, dragging, snapping, persistence, and
lifecycle behavior.

## Visual contract

- Keep a 24-point inset from the selected display's left, top, and bottom edges.
- Render Save and Cancel as equal 104 by 42-point buttons when the display has room.
- Use a 12-point horizontal gap between the buttons.
- Use a consistent 9-point button corner radius.
- Render button labels at 16 points with the existing centered, high-contrast treatment.
- Use `#16A34A` for Save and an opaque charcoal equivalent to `#353A42` for Cancel.
- On a normal display, render the instruction background at local
  `{ x = 24, y = 24, w = 330, h = 42 }`. Use black at `0.88` alpha, a one-point
  white stroke at `0.28` alpha, and a 10-point corner radius.
- Render an 8 by 8-point `#FF643B` accent dot at local
  `{ x = 40, y = 41, w = 8, h = 8 }`.
- Render `Drag red bands or white edges` left-aligned at 15 points in local frame
  `{ x = 58, y = 24, w = 280, h = 42 }`. This leaves 16 points of right padding and
  enough text width to prevent the clipping shown in the screenshot.
- Keep the existing translucent red bands, orange outlines, and white resize handles.

The supported calibration canvas is at least 260 by 180 points. Reject a smaller canvas
with `display is too small for calibration controls` before allocating an editor.

For every supported width, keep the 24-point horizontal insets and 12-point button gap.
Calculate each button width as
`min(104, floor((fullFrame.w - 48 - 12) / 2))`; this is at least 100 points at the
minimum supported width. Keep the 42-point button height and set local `y` to
`fullFrame.h - 24 - 42`.

At widths below 378 points, use a narrow instruction background at
`{ x = 24, y = 24, w = fullFrame.w - 48, h = 58 }`, keep the accent dot centered
vertically, and render the full instruction in a left-aligned 13-point text frame at
`{ x = 58, y = 24, w = fullFrame.w - 98, h = 58 }`, allowing it to wrap. At widths
of 378 points or greater, use the exact normal-display frames above.

As a narrow negative-origin oracle, a display with absolute frame
`{ x = -500, y = -200, w = 260, h = 180 }` uses local Save frame
`{ x = 24, y = 114, w = 100, h = 42 }`, local Cancel frame
`{ x = 136, y = 114, w = 100, h = 42 }`, instruction background
`{ x = 24, y = 24, w = 212, h = 58 }`, accent dot
`{ x = 40, y = 49, w = 8, h = 8 }`, and instruction text
`{ x = 58, y = 24, w = 162, h = 58 }`.

## Interaction and lifecycle

The rendered Save and Cancel frames remain the hit-test source of truth. Clicking the
restyled controls must invoke the existing save or cancel path exactly once. No new
mouse tracking is attached to visual elements; the existing full-canvas input surface
remains the sole tracker.

Candidate construction and replacement remain transactional. If any new control element
cannot be configured, the candidate editor is deleted and the previously committed
editor remains live. Stop, Save, Cancel, replacement, and stale callbacks retain their
existing ownership and cleanup guarantees.

## Scope boundaries

This change does not modify band defaults, geometry, snapping thresholds, mask rendering,
window correction, menu behavior, or saved configuration. Windows support and packaged
Windows/macOS releases are separate follow-up workstreams.

## Verification

Automated tests will prove:

- exact control frames, gap, insets, radii, colors, and label sizes on a 3440 by 1440
  normal display;
- exact instruction background, stroke, dot, text frame, and type size on normal and
  narrow displays;
- the 260 by 180 negative-origin oracle above remains fully inside local bounds;
- smaller displays fail before allocating an editor;
- Save and Cancel hit testing still uses the rendered frames;
- visual elements do not claim mouse tracking;
- a replacement failure while assigning or configuring a new control or instruction
  element deletes the candidate and stops its input while preserving the prior canvas,
  event tap, frames, callbacks, and ownership;
- the complete existing Lua suite remains green.

Manual Hammerspoon verification will confirm the polished controls on the selected
3440 by 1440 display and verify Save, Cancel, mouse dragging, and trackpad-latched dragging.
