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
- Render the instruction as a 42-point-high dark translucent badge with a 10-point
  corner radius and a subtle light border.
- Give the instruction badge enough width and smaller 15-point type so
  `Drag red bands or white edges` is fully visible.
- Keep the existing translucent red bands, orange outlines, and white resize handles.

On an unusually narrow display, calculate smaller equal button widths and a bounded
instruction width so every control remains inside the local canvas. Normal displays use
the exact measurements above.

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

- exact control frames, gap, insets, radii, colors, and label sizes on a normal display;
- instruction text and frame fit without clipping;
- all controls remain inside a narrow, negative-origin display;
- Save and Cancel hit testing still uses the rendered frames;
- visual elements do not claim mouse tracking;
- candidate construction failures preserve the prior live editor;
- the complete existing Lua suite remains green.

Manual Hammerspoon verification will confirm the polished controls on the selected
3440 by 1440 display and verify Save, Cancel, mouse dragging, and trackpad-latched dragging.
