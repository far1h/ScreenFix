# Calibration Reset and Snapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe SF-menu reset and clean 12-point magnetic snapping for mouse and trackpad calibration.

**Architecture:** Implement snapping as pure geometry over an unsnapped drag candidate; integrate it after existing clamp/resize logic. Implement reset in the controller against the persisted live monitor, using existing chooser/calibration invalidation and refresh boundaries. Pure geometry and controller reset can be developed independently before calibration integration.

**Tech Stack:** Lua 5.4, Hammerspoon 1.1.1, existing table-driven test harness.

---

### Task 1: Pure magnetic snapping geometry

**Files:**
- Modify: `screenfix/geometry.lua`
- Modify: `tests/geometry_test.lua`

- [ ] **Step 1: Write a RED screen-target matrix**

Test a pure `snapBand(rawBand, activeIndex, part, bands, fullFrame, 12)` contract.
Cover body left/right/top/bottom edges snapping to either normalized screen edge;
left/top resize snapping only to screen start; right/bottom resize snapping only to
screen end; exact 12-point boundary snaps and 12.01 points does not. Body keeps
size; resize keeps its opposite edge fixed. Add explicit rejection cases for
left/top-to-end and right/bottom-to-start.

- [ ] **Step 2: Run and verify RED**

Run: `lua tests/run.lua`

Expected: missing `snapBand` failures.

- [ ] **Step 3: Implement only legal screen snapping**

Convert the point threshold independently by axis (`12 / fullFrame.w` or
`12 / fullFrame.h`). Generate candidate corrections for the active edge(s), pick
the smallest absolute correction, and return a fresh rectangle without mutating
inputs. Discard body candidates outside `[0,1]` and resize candidates that exceed
bounds or leave either final dimension below 20 points.

- [ ] **Step 4: Verify screen GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 5: Write a RED peer-target/tie matrix**

Exclude the active band. Do not require orthogonal overlap. Cover peer start/end on
both axes, vertically stacked x alignment, side-by-side y alignment, and exact tie
order: screen start, screen end, peer index ascending/start-before-end, active
leading-before-trailing.

- [ ] **Step 6: Run the peer matrix and verify RED**

Run: `lua tests/run.lua`

Expected: peer-edge cases fail because only screen targets exist.

- [ ] **Step 7: Implement peer targets**

Use deterministic candidate insertion order and replace the winner only for a
strictly smaller absolute correction.

- [ ] **Step 8: Run the peer matrix and verify GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 9: Add RED illegal-target and purity tests**

Prove peer targets cannot violate bounds or 20-point minimum; malformed/absent
peers are ignored safely; inputs are not mutated; output tables are fresh.

- [ ] **Step 10: Run illegal-target/purity tests and verify RED**

Run: `lua tests/run.lua`

Expected: the first missing rejection or purity assertion fails.

- [ ] **Step 11: Implement minimal validation**

- [ ] **Step 12: Verify illegal-target/purity GREEN**

Run full suite, `luac -p`, and `git diff --check`. Commit only owned files as
`feat: add magnetic calibration snapping`.

### Task 2: SF dropdown Reset to Defaults

**Files:**
- Create: `assets/screenfix-menubar.png`
- Modify: `screenfix/controller.lua`
- Modify: `tests/controller_test.lua`
- Modify: `tests/fake_hs.lua`
- Modify: `init.lua`
- Modify: `tests/init_test.lua`

- [ ] **Step 0: Verify an isolated baseline**

Run: `git diff --quiet -- screenfix/controller.lua tests/controller_test.lua tests/fake_hs.lua init.lua tests/init_test.lua`

Expected: exit 0 after the lifecycle transaction commit. Stage only exact owned
paths in this task so unrelated files cannot be absorbed.

- [ ] **Step 1: Write RED icon assembly/fallback tests**

Fake menubar records `setIcon(imagePath, template)`. Expect `init.lua` to inject
the project asset path; successful menu creation uses the generated 36-by-36 PNG
with `template=true` and no title; nil/throwing `setIcon` falls back to title `SF`
without losing the dynamic menu.

- [ ] **Step 2: Run icon tests and verify RED**

Run: `lua tests/run.lua`

Expected: no `setIcon` calls and missing path assembly.

- [ ] **Step 3: Implement icon loading with text fallback**

- [ ] **Step 4: Verify icon GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 5: Write RED menu/state tests**

Expect `Reset to Defaults` between `Select Monitor` and `Reload`, with explicit
checked=false. It is disabled when no persisted selected monitor is live and
enabled otherwise, including while the saved mask is disabled.

- [ ] **Step 6: Run menu tests and verify RED**

Run: `lua tests/run.lua`

Expected: the Reset row is absent.

- [ ] **Step 7: Add the menu row**

The action calls protected `Controller:resetDefaults()`; no reset logic yet.

- [ ] **Step 8: Verify menu-row GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 9: Write RED success/lifecycle tests**

On invocation revoke chooser/calibration tokens and stop the adapter before any
fallible load/find/default/save call. Then reload persisted config and re-resolve
its screen, build defaults for that persisted screen (not an unsaved calibration
target), preserve persisted `enabled`, save immediately, set `self.value`, and
refresh. Include order-sensitive assertions and a chooser-only state. Prove stale
chooser, Save, and Cancel callbacks cannot overwrite/clear the result.

- [ ] **Step 10: Run success/lifecycle tests and verify RED**

Run: `lua tests/run.lua`

Expected: missing method/action behavior fails before production reset logic.

- [ ] **Step 11: Implement success path**

Reuse existing invalidation helpers and config APIs. Do not duplicate default
band values in the controller.

- [ ] **Step 12: Verify reset-success GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 13: Write RED failure-episode tests**

Cover disconnect after menu construction, load/default/find/save nil and thrown
failures. No new value is persisted; calibration remains canceled; prior saved
configuration is refreshed; one reset-failure notification is emitted per episode;
a later successful reset clears the episode and permits a future notification.
Use a freshly loaded persisted value different from cached `self.value` and prove
that fresh value is retained/refreshed after findScreen nil/throw and downstream
default/save failure.

- [ ] **Step 14: Run failure-episode tests and verify RED**

Run: `lua tests/run.lua`

Expected: the first missing failure boundary fails.

- [ ] **Step 15: Implement failure containment**

- [ ] **Step 16: Verify failure containment GREEN**

Run full suite, `luac -p`, and `git diff --check`. Commit only owned files as
`feat: reset mask defaults from the menu`.

### Task 3: Apply snapping to both input modes

**Files:**
- Modify: `screenfix/calibration.lua`
- Modify: `tests/calibration_test.lua`
- Modify: `README.md`

- [ ] **Step 1: Write all RED snapping integration matrices**

For body/left/right/top/bottom, use real calibration callbacks and eventtap
`leftMouseDragged`. Assert screen and peer snapping through `geometry.snapBand`,
including exact seams and legal bounds.

For both axes, prove repeated sub-threshold pointer deltas accumulate in raw state,
the visible edge stays snapped through 12 points, and movement beyond 12 releases
it. Repeat body/four-edge coverage through tap-up then eventtap `mouseMoved`.

Inject `snapBand` failure and prove `rawBand`, visible working band, `lastPoint`, and
`moved` remain at the last coherent state so the next valid delta is applied once.
If redraw fails after geometry commits, prove the coherent state remains and the
next delta is incremental. Existing injected geometry doubles must expose a
`snapBand` passthrough.

- [ ] **Step 2: Run all snapping matrices and verify RED**

Run: `lua tests/run.lua`

Expected: held/latched candidates remain unsnapped and failure doubles expose the
missing raw/snap boundary.

- [ ] **Step 3: Implement the shared raw/snap path atomically**

Initialize `drag.rawBand` as a fresh copy of the selected working band. Compute raw
and snapped candidates in locals for both held and latched input. Only after both succeed assign
`drag.rawBand`, the visible working band, `lastPoint`, and `moved`, then redraw.
Never feed the snapped visible band back into raw accumulation. Drop, Save, Cancel,
replacement, and stop clear raw state with existing drag/session teardown.

- [ ] **Step 4: Verify all snapping matrices GREEN**

Run: `lua tests/run.lua`

- [ ] **Step 5: Update concise README instructions**

Document 12-point screen/peer snapping and the new dropdown reset. Preserve the
existing before photo and mouse/trackpad instructions.

- [ ] **Step 6: Automated verification and commit**

Run:

```bash
lua tests/run.lua
for file in init.lua screenfix/*.lua tests/*.lua; do luac -p "$file"; done
git diff --check
```

Commit owned files as `feat: snap calibration bands cleanly`.

### Task 4: Live acceptance and persisted safety

**Files:**
- No production changes unless a new reproducible failure receives a RED test.

- [ ] Reload Hammerspoon and verify the generated template icon, `SF` fallback probe, and Reset placement/state.
- [ ] With a held drag, snap a white edge to a peer edge and a body edge to screen.
- [ ] With tap-move-tap, repeat peer and screen snaps, then move beyond 12 points to release each snap.
- [ ] Cancel and verify all three persisted bands remain exactly `1215–1920`.
- [ ] Invoke Reset once, verify built-in defaults apply, then restore and save `1215–1920` for the user.
- [ ] Run the full automated/syntax/diff gate again.
