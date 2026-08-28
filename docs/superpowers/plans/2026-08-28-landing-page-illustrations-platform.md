# ScreenFix Landing Page Illustrations and Platform Recommendation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the ScreenFix landing page with five cohesive editorial illustrations, advisory Windows/macOS download ordering, stronger requirements and privacy layouts, responsive header/footer polish, full verification, and a pull request that closes issue #7.

**Architecture:** Preserve the dependency-free static site and existing semantic HTML/CSS contracts. Add five sanitized JPEG illustrations and one small local ES module whose pure classifier and DOM enhancer are exercised with Node's built-in test runner; static HTML keeps both downloads visible and usable when JavaScript is absent or classification is unknown.

**Tech Stack:** HTML5, CSS3, JavaScript ES modules, Node built-in `node:test`, Python 3 standard library `unittest`, built-in image generation, macOS `sips`, `jpegtran`, GitHub Actions, and GitHub Pages.

**Approved specification:** `docs/superpowers/specs/2026-08-28-landing-page-design.md`

**Execution workspace:** `/Users/farihmuhammad/Downloads/ScreenFix/.worktrees/landing-page` on `feat/landing-page`

---

## File Map

- Modify `tests/site/test_site.py` — exact public tree, eight-image contract, semantic copy/layout contracts, CSS vocabulary/effective-value checks, local-script security contract, workflow and README assertions.
- Create `tests/site/platform.test.mjs` — deterministic Windows, macOS, Safari, touch-capable iPad, unknown, idempotence, DOM-order, and both-options-visible behavior tests using only `node:test`.
- Create `site/platform.mjs` — pure platform classifier, idempotent recommendation enhancer, and guarded browser auto-run; no navigation, download, network, persistence, or tracking APIs.
- Create `site/assets/how-mark-strip.jpg` — 1200×900 metadata-free editorial illustration of calibration guides.
- Create `site/assets/how-mask-strip.jpg` — 1200×900 metadata-free editorial illustration of the opaque mask.
- Create `site/assets/how-use-space.jpg` — 1200×900 metadata-free editorial illustration of windows using the safe areas.
- Create `site/assets/privacy-local.jpg` — 1200×900 metadata-free editorial illustration of local-only geometry processing.
- Create `site/assets/requirements-platforms.jpg` — 1200×900 metadata-free cross-platform editorial illustration.
- Modify `site/index.html` — full-width header shell, platform hooks and recommendation labels, five illustrations, concise privacy copy, four-row requirements list, smaller support-note classes, and footer credit.
- Modify `site/styles.css` — constrained header inner layout, mobile brand correction, non-card illustration layouts, 15px support notes, recommendation state, requirements rows, and final footer row.
- Modify `.github/workflows/pages.yml` — execute both Python and Node built-in site tests before archive validation and publication.
- Modify `README.md` — keep the collaborator section concise while listing both dependency-free site validation commands.

Native application code, release workflow, release assets, version files, existing three photographs, and the canonical icon are outside this increment and must remain byte-identical.

---

### Task 0: Commit the reviewed incremental plan

**Files:**
- Create: `docs/superpowers/plans/2026-08-28-landing-page-illustrations-platform.md`

- [ ] **Step 1: Validate the plan against the approved specification**

Run:

```bash
git diff --check
git diff -- docs/superpowers/plans/2026-08-28-landing-page-illustrations-platform.md
```

Expected: only this plan is uncommitted and it names every new public asset, runtime file, test, workflow command, and manual acceptance width from the specification.

- [ ] **Step 2: Obtain independent whole-plan approval**

Dispatch one plan-document reviewer with only the specification path, plan path, approved user requirements, and current head. Fix every Important issue through a full re-review before proceeding.

- [ ] **Step 3: Commit the reviewed plan**

```bash
git add docs/superpowers/plans/2026-08-28-landing-page-illustrations-platform.md
git diff --cached --check
git commit -m "docs: plan landing page illustrations and platform"
git status --short
```

Expected: the plan commit succeeds and the worktree is clean.

---

### Task 1: Generate and sanitize the five illustration assets

**Files:**
- Modify: `tests/site/test_site.py`
- Create: `site/assets/how-mark-strip.jpg`
- Create: `site/assets/how-mask-strip.jpg`
- Create: `site/assets/how-use-space.jpg`
- Create: `site/assets/privacy-local.jpg`
- Create: `site/assets/requirements-platforms.jpg`

- [ ] **Step 1: Extend the image contract before generating assets**

Add a separate `EXPECTED_ILLUSTRATIONS` mapping so the existing photograph dimensions and budgets remain explicit:

```python
EXPECTED_ILLUSTRATIONS = {
    "how-mark-strip.jpg": (1200, 900),
    "how-mask-strip.jpg": (1200, 900),
    "how-use-space.jpg": (1200, 900),
    "privacy-local.jpg": (1200, 900),
    "requirements-platforms.jpg": (1200, 900),
}
MAX_ILLUSTRATION_BYTES = 250_000
MAX_ILLUSTRATION_TOTAL_BYTES = 1_100_000
MAX_ALL_JPEG_BYTES = 1_500_000
```

Require every expected illustration to be a regular non-symlink JFIF JPEG accepted by the existing marker parser, to have exact dimensions, and to meet individual/group/all-JPEG budgets. Add the five exact illustration paths to `EXPECTED_SITE_FILES` in the same RED increment so the eventual asset commit can pass the whole repository site suite. Keep the original photograph limits unchanged.

- [ ] **Step 2: Run the focused image contract RED**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k ImageContractTests -v
```

Expected: FAIL only because the five named illustration files are missing. Existing photograph and SVG tests must remain green.

- [ ] **Step 3: Generate the first illustration with the built-in image tool**

Use `@imagegen` in built-in mode, one call per distinct asset. Use this shared style contract in all five prompts:

```text
Use case: illustration-story
Asset type: ScreenFix landing-page editorial illustration, 4:3 landscape
Style/medium: simple hand-drawn editorial cartoon; warm paper texture; confident imperfect ink outlines; restrained flat shapes; polished but clearly human-made
Color palette: cream #F5F0E8 and #FCFAF6, coral #B83D31 and #D9513B, amber accents, dark plum #27212B, muted gray #655D61
Composition/framing: one monitor-focused scene, generous breathing room, readable at small web size
Constraints: no embedded text, letters, numbers, logos, watermarks, real people, faces, hands, private content, browser chrome, glossy 3D, gradients across the background, generic stock characters, glassmorphism, or futuristic AI motifs
```

For `how-mark-strip.jpg`, add: a desktop monitor with a visibly damaged dark vertical strip and three colored calibration guides accurately marking the strip.

- [ ] **Step 4: Inspect the first generated output before using it as a style reference**

Load the generated bitmap with `view_image` at original detail. Reject it if the strip, three guide bands, palette, or monitor silhouette is unclear, or if it contains text-like glyphs, logos, people, UI content, watermark artifacts, glossy rendering, or an AI-stock look. Iterate with one targeted prompt change only if needed.

- [ ] **Step 5: Generate the remaining four distinct illustrations**

Use one built-in image call per asset. Pass the accepted first image only as a style reference and repeat all shared constraints:

- `how-mask-strip.jpg`: the same visual language, one monitor with a fully opaque black mask covering the damaged strip.
- `how-use-space.jpg`: one monitor with the damaged strip dark and ordinary movable windows arranged clearly in usable left/right spaces.
- `privacy-local.jpg`: a monitor and local ScreenFix geometry shapes contained on the computer, with no cloud, network line, screen content, or text.
- `requirements-platforms.jpg`: two distinct desktop-computer silhouettes suggesting Windows and macOS without protected logos, both working around the same damaged vertical strip.

Inspect every accepted output at original detail. Consistency means the same outline weight, paper texture, palette, monitor proportions, and visual restraint—not duplicated composition.

- [ ] **Step 6: Publish sanitized 1200×900 JPEG derivatives through a guarded temporary directory**

Use a validated `mktemp -d` directory. For each accepted generated bitmap, crop/resize with `sips`, then run `jpegtran -copy none -optimize -progressive`. Publish only the final regular files to `site/assets/`; never reference an image left under `$CODEX_HOME/generated_images/`.

Run the parser against temporary outputs before copying. Keep permissions at `0644`. Refuse symlink, directory, unexpected root, and oversized outputs. Use `apply_patch` only for source/test changes; format/conversion commands may produce the binary derivatives.

- [ ] **Step 7: Run image contracts GREEN and inspect committed derivatives**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k ImageContractTests -v
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -v
git diff --check
```

Expected: every photograph, SVG, parser mutation, new illustration, exact-tree, and existing site test passes. Load all five committed JPEGs with `view_image` at original detail and confirm the sanitized files still satisfy the visual brief.

- [ ] **Step 8: Commit the verified asset slice**

```bash
git add tests/site/test_site.py site/assets/how-mark-strip.jpg \
  site/assets/how-mask-strip.jpg site/assets/how-use-space.jpg \
  site/assets/privacy-local.jpg site/assets/requirements-platforms.jpg
git diff --cached --check
git commit -m "assets: add ScreenFix landing illustrations"
```

Expected: exactly the image-contract edits and five illustration files are committed.

- [ ] **Step 9: Pass the Task 1 review gate before Task 2**

Dispatch a fresh spec-compliance reviewer for the committed asset slice. Only after approval, dispatch a fresh code-quality reviewer. Return every finding to the same implementer, add a focused regression for behavior defects, amend the Task 1 commit, and re-run the corresponding reviewer. Do not start Task 2 until both reviewers approve and the full Python site suite is green.

---

### Task 2: Add deterministic local platform recommendation

**Files:**
- Create: `site/platform.mjs`
- Create: `tests/site/platform.test.mjs`
- Modify: `tests/site/test_site.py`
- Modify: `.github/workflows/pages.yml`
- Modify: `README.md`

- [ ] **Step 1: Write pure classifier and DOM behavior tests first**

Use `node:test` and `node:assert/strict`. Import the planned exports but do not create the module yet:

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import { applyPlatformRecommendation, detectPlatform } from "../../site/platform.mjs";

test("detects Windows from low-entropy user-agent data", () => {
  assert.equal(detectPlatform({
    userAgentData: { platform: "Windows", mobile: false },
    platform: "MacIntel",
    userAgent: "Mozilla/5.0",
    maxTouchPoints: 0,
  }), "windows");
});
```

Add separate cases for macOS through `userAgentData`, macOS through Safari's `platform`, Windows through `userAgent`, precedence of `userAgentData.platform`, Android/iPhone/iPad tokens, `MacIntel` plus `maxTouchPoints > 1`, Linux, empty signals, and missing fields. Return only `"windows"`, `"macos"`, or `null`.

Create small real fake objects for two platform groups. Test that macOS moves the existing macOS node first in each group, Windows remains first, the matching existing label is revealed, the other label remains hidden, both platform option nodes remain present and not hidden, unknown performs no DOM mutation, and a second call is idempotent.

- [ ] **Step 2: Run Node tests RED**

```bash
node --test tests/site/platform.test.mjs
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `site/platform.mjs`, not a test syntax error.

- [ ] **Step 3: Implement the minimal pure ES module**

Export two short functions:

```javascript
export function detectPlatform(client) {
  // Reject mobile/touch-iPad signals, then classify userAgentData.platform,
  // navigator.platform, and userAgent in that exact priority order.
}

export function applyPlatformRecommendation(documentRoot, platform) {
  // For windows/macos only: find each [data-platform-group], move the matching
  // existing [data-platform-option] first, add is-recommended, and reveal only
  // its existing [data-device-recommendation] label. Never create markup.
}
```

At module bottom, guard the browser auto-run with `typeof window` and `typeof document`; imported Node tests must have no side effects.

- [ ] **Step 4: Run behavior tests GREEN**

```bash
node --test tests/site/platform.test.mjs
```

Expected: every classifier, DOM ordering, label, visibility, unknown, and idempotence test passes without warnings.

- [ ] **Step 5: Add a strict Python source/security contract RED then GREEN**

Add only `platform.mjs` to the exact site-tree contract; Task 1 already added the five JPEGs. Keep the current one-GoatCounter-script HTML contract unchanged until Task 3 introduces the local module tag. Validate the local module itself independently as a bounded regular UTF-8 file.

Reject forbidden source tokens or member calls covering navigation, automatic click/download, URL mutation, `fetch`, XHR, `sendBeacon`, WebSocket, EventSource, cookies, local/session storage, IndexedDB, service workers, dynamic import, `eval`, `Function`, timers, `innerHTML`, `outerHTML`, and `insertAdjacentHTML`. Require all five permitted browser properties: the three precedence sources `userAgentData.platform`, `platform`, and `userAgent`, plus the two mobile-rejection signals `userAgentData.mobile` and `maxTouchPoints`. Reject any other navigator-property read. Require the exact platform-group/data-label selectors. Add one mutation regression per behavior class so every rule is proven RED before GREEN.

- [ ] **Step 6: Wire both built-in test commands into CI through RED→GREEN**

First extend the workflow contract and its mutation tests to require `node --test tests/site/platform.test.mjs` exactly once immediately after the Python command in both validation and publish jobs. Run the focused workflow test and record RED against the current YAML. Then edit `.github/workflows/pages.yml` and run the focused test GREEN. Keep job permissions, source-SHA checkout, archive checks, action versions, and deployment conditions unchanged.

- [ ] **Step 7: Add the collaborator command through RED→GREEN**

Extend `_validate_readme_collaboration` and its mutation tests to require the exact Node command exactly once in the `Collaborating` section beside the existing Python command. Run the focused README test and record RED. Then add the Node command to README without duplicating landing-page marketing copy and run the focused README tests GREEN.

- [ ] **Step 8: Run focused and full non-rendered tests**

```bash
node --test tests/site/platform.test.mjs
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -v
ruby -e 'require "yaml"; YAML.safe_load(File.read(".github/workflows/pages.yml"), aliases: true)'
git diff --check
```

Expected: Node and Python suites pass; YAML parses; no workflow permission or archive regression changes.

- [ ] **Step 9: Commit the platform slice**

```bash
git add site/platform.mjs tests/site/platform.test.mjs tests/site/test_site.py \
  .github/workflows/pages.yml README.md
git diff --cached --check
git commit -m "feat: recommend the matching ScreenFix download"
```

- [ ] **Step 10: Pass the Task 2 review gate before Task 3**

Dispatch a fresh spec-compliance reviewer for the committed module/test/workflow/README slice, followed only after approval by a fresh code-quality reviewer. The same implementer fixes and amends any finding. Do not begin Task 3 until both reviewers approve and Node, Python, YAML, and diff checks are green.

---

### Task 3: Add the revised semantic content and platform hooks

**Files:**
- Modify: `site/index.html`
- Modify: `tests/site/test_site.py`

- [ ] **Step 1: Add failing header and illustration markup contracts**

Require `.site-header` to contain exactly one `.site-header-inner`, and require the brand and nav as its direct children. Require each How article to contain its exact number, one 1200×900 illustration with descriptive alt text plus `loading="lazy" decoding="async"`, and one `.how-step-copy` containing the unchanged heading and paragraph.

Require `privacy-local.jpg` and `requirements-platforms.jpg` once each with the same dimension/loading contract. Run each new test and record the expected structural failure against current HTML before editing it.

In the same HTML-contract slice, tighten `_validate_script` from the existing one exact GoatCounter script to exactly two reviewed scripts: that unchanged external async tag plus one local `<script type="module" src="platform.mjs">` with no inline body. Run this focused test RED before adding the module tag.

- [ ] **Step 2: Add failing copy, requirements, note, and footer contracts**

Require Privacy to contain exactly the approved heading, illustration, and app-local paragraph. Reject visible case-insensitive matches for `GoatCounter`, `analytics`, `visit`, `visitor`, `tracking`, `cookie`, `IP address`, and `user agent`.

Require a four-row `<dl>` in exact order: `Windows`, `macOS`, `What ScreenFix does`, `Window limitations`. Preserve every existing supported-platform, signing, Gatekeeper, Accessibility, physical-damage, maximized-window, administrator/protected/custom/fixed/non-movable/borderless/exclusive/full-screen fact in the correct row.

Require exactly three `.download-note` paragraphs: SmartScreen, Windows fallback, and macOS Accessibility. Require the footer's final child to be a dedicated row reading `Built by farihmhmd.com` with one exact `https://farihmhmd.com/` link.

Run the new focused test before editing HTML:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' \
  -k test_privacy_requirements_notes_and_footer_revision -v
```

Expected: FAIL against the current visible GoatCounter paragraph, five-item Requirements list, ordinary-size notes, and missing credit row. The failure must name the first unmet approved fact rather than a parser error.

- [ ] **Step 3: Add failing static progressive-enhancement markup contracts**

Require exactly two `[data-platform-group]` containers: the hero download group and detailed download pair. Each contains exactly one Windows and one macOS `[data-platform-option]`, with both visible in source HTML and the existing exact URLs unchanged. Each option contains one pre-authored hidden `[data-device-recommendation]` label with exact text `Recommended for this device`.

Mutation controls must reject missing alternatives, hidden platform options, recommendation labels exposed in static HTML, duplicate platform values, labels outside their option, changed URLs, or CSS-only `order` attributes.

Run the new focused test before editing HTML:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' \
  -k test_platform_groups_are_static_and_complete -v
```

Expected: FAIL because the current hero and detailed downloads have no platform-group, option, or recommendation-label markup while both existing URLs remain valid.

- [ ] **Step 4: Implement semantic HTML incrementally**

Use `apply_patch` and run the corresponding focused test after each small edit:

1. Wrap current brand/nav in `.site-header-inner`.
2. Wrap hero platform buttons in `[data-platform-group]`, mark each option, and add hidden labels.
3. Add one illustration and `.how-step-copy` to each numbered How row.
4. Add platform attributes/hidden labels and `.download-note` classes to the detailed pair.
5. Replace the visible analytics paragraph with only the approved app-local Privacy content and illustration.
6. Replace the Requirements `<ul>` with the approved illustration and four-row `<dl>`.
7. Add the final footer credit row.
8. Add `<script type="module" src="platform.mjs"></script>` while retaining the exact GoatCounter tag.

- [ ] **Step 5: Run semantic tests GREEN and commit**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k LandingPageContractTests -v
node --test tests/site/platform.test.mjs
git diff --check
```

Expected: exact tree, scripts, copy, platforms, illustrations, requirements, notes, downloads, privacy exclusions, FAQ, and footer contracts pass.

```bash
git add site/index.html tests/site/test_site.py
git commit -m "feat: illustrate the ScreenFix landing page"
```

- [ ] **Step 6: Pass the Task 3 review gate before Task 4**

Dispatch a fresh spec-compliance reviewer for the committed semantic HTML slice, followed only after approval by a fresh code-quality reviewer. The same implementer fixes and amends findings. Do not begin styling until both reviewers approve and semantic, Node, and full Python tests are green.

---

### Task 4: Style the responsive editorial revision

**Files:**
- Modify: `site/styles.css`
- Modify: `tests/site/test_site.py`

- [ ] **Step 1: Prove the two reported header defects before fixing them**

Add effective-style tests at 375px proving the brand is centered and has `text-decoration: none`, and at every reviewed width proving the divider belongs to a full-width `.site-header` while content width/gutters belong to `.site-header-inner`. Mutation controls must reproduce the current selector-specific underline and constrained-border failures.

Run only those tests. Expected: RED with current CSS because `a:not(.download-primary)` outranks `.brand` and the border sits on the constrained header.

- [ ] **Step 2: Implement the minimal full-width header shell**

Move the shared `max-width`, margin, and horizontal padding contract from `.site-header` to `.site-header-inner`. Keep `.site-header` width 100% with the border. Give `.site-header-inner` the existing flex/wrap/alignment behavior. Exclude `.brand` from the global underlined-link selector and explicitly keep brand hover underline-free. At `max-width: 700px`, give the brand a centered full row and center the visible nav below it.

Run the focused header tests GREEN before continuing.

- [ ] **Step 3: Add failing editorial illustration layout tests**

Extend the fixed CSS selector/property vocabulary before production CSS. At 375px require each How row to use number + image + copy without overflow; at 900px require number/image/copy columns. Require privacy and requirements to stack at mobile widths and use balanced two-column grids at 900px+. Require illustration images to be full-width, 4:3, contained, and at most the existing 8px radius with no shadow/card/background wrapper.

Run the focused layout test before adding any matching CSS:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' \
  -k test_editorial_illustration_layout_values -v
```

Expected: FAIL because the new selectors have no effective grid/image values. It must not fail because of malformed test CSS parsing.

- [ ] **Step 4: Add failing support-note, recommendation, requirements, and footer tests**

Require `.download-note` effective `font-size: 15px`, readable line-height, muted accessible color, and fallback link target height at least 44px. Require recommendation text to remain at least 14px and visible without color alone. Require four ruled requirement rows with coral numbers, larger term labels, and no card borders/radii/shadows. Require `.footer-credit` to occupy the final full row without reducing link target sizes.

Run the focused supporting-style test before adding any matching CSS:

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' \
  -k test_supporting_revision_style_values -v
```

Expected: FAIL on the missing 15px note, recommendation, requirement-row, or footer-credit style contract while existing contrast helpers continue to run.

- [ ] **Step 5: Implement CSS one selector group at a time**

Use the existing tokens and spacing rhythm. Do not add external fonts, glassmorphism, large gradients, badges, card shadows, entrance animation, or new color tokens. Add only the selector/property combinations proven by the failing tests, updating `APPROVED_CSS_RULE_VOCABULARY` alongside each group.

- [ ] **Step 6: Run focused CSS tests after every group, then the whole site suite**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -k StyleContractTests -v
python3 -B -m unittest discover -s tests/site -p 'test_site.py' -v
node --test tests/site/platform.test.mjs
git diff --check
```

Expected: all CSS vocabulary, effective layout, contrast, target-size, source-order, reduced-motion, semantic, image, script, workflow, and README tests pass without warnings or skips.

- [ ] **Step 7: Commit the responsive style slice**

```bash
git add site/styles.css tests/site/test_site.py
git diff --cached --check
git commit -m "feat: polish the ScreenFix landing layout"
```

- [ ] **Step 8: Pass the Task 4 review gate before whole-branch verification**

Dispatch a fresh spec-compliance reviewer for the committed style slice, followed only after approval by a fresh code-quality reviewer. The same implementer adds focused regressions, fixes, and amends any finding. Do not enter Task 5 until both reviewers approve and the full Python and Node suites are green.

---

### Task 5: Whole-branch review and complete local verification

**Files:**
- Review the complete branch diff from `ed68d02d16014a6fae418bfb2f99fc649102cf4e` through current head.
- Modify only files needed to resolve reviewed findings.

- [ ] **Step 1: Run a final whole-branch reviewer**

Give the reviewer the exact base/head SHAs, approved specification, incremental plan, user-visible requirements, and full diff. Require findings ordered by severity with exact file references. Fix and re-review until Ready: YES.

- [ ] **Step 2: Run fresh automated verification at the reviewed head**

```bash
python3 -B -m unittest discover -s tests/site -p 'test_*.py' -v
node --test tests/site/platform.test.mjs
lua tests/run.lua
native/macos/scripts/run-tests.sh
ruby -e 'require "yaml"; YAML.safe_load(File.read(".github/workflows/pages.yml"), aliases: true)'
git diff --check ed68d02d16014a6fae418bfb2f99fc649102cf4e..HEAD
git status --short
```

Expected: every suite passes, macOS native output reports zero failures, YAML parses, the branch diff is clean, and the worktree is clean.

- [ ] **Step 3: Rebuild and inspect the exact Pages archive locally**

Use the same hidden-file and dereference behavior as `.github/workflows/pages.yml`. Compare the sorted regular-file manifest against the current `site/` tree; require exact equality, empty `.nojekyll`, no symlink/hardlink escape, and no tests, repository metadata, or unexpected file. Use a guarded temporary directory and prove cleanup.

- [ ] **Step 4: Serve locally and perform rendered acceptance**

Start a loopback-only static server on an available explicit port. Check `/`, CSS, module, SVG, all eight JPEGs, and anchors return 200. In a real browser inspect:

- 375×812: centered underline-free brand, visible wrapped nav, full-width header divider, no horizontal overflow, readable illustrations and requirements rows;
- 768×1024: balanced stacking and readable targets;
- 1024×768 and 1440×900: aligned 1200px content grid, full viewport divider, two-column editorial layouts, and non-card How rows;
- keyboard-only order from skip link through nav, both hero downloads, sections, FAQ summaries, and footer;
- visible focus, all FAQ disclosures, reduced-motion mode, JavaScript-disabled fallback, Windows/macOS/unknown recommendation states, and both downloads visible in every state; and
- zero page-owned console errors.

Stop the server and prove the port no longer has a listener.

---

### Task 6: Push, open the pull request, and monitor exact-SHA checks

**Files:**
- No source changes unless remote verification reveals a real defect.

- [ ] **Step 1: Push the reviewed branch and verify the remote SHA**

```bash
git push origin feat/landing-page
local_sha="$(git rev-parse HEAD)"
remote_sha="$(git ls-remote origin refs/heads/feat/landing-page | awk '{print $1}')"
test "$local_sha" = "$remote_sha"
```

Expected: local and remote exact SHAs match.

- [ ] **Step 2: Inspect exact remote source bytes**

Fetch `site/index.html` and `site/platform.mjs` through exact-SHA raw GitHub URLs and compare their SHA-256 hashes to the local files. Rendered acceptance remains the Task 5 loopback result because pull requests intentionally do not publish Pages and no third-party preview is part of the deployment architecture.

- [ ] **Step 3: Open one pull request against `main`**

Use a factual title and body that summarize the static landing page, generated/sanitized assets, advisory platform recommendation, Pages workflow, and verification commands. Include `Fixes #7`. Do not claim the Pages production deployment has already occurred.

- [ ] **Step 4: Read the pull request back**

Require state OPEN, base `main`, head `feat/landing-page`, exact reviewed head SHA, mergeable/no conflict, and `Fixes #7` in the body. Confirm issue #7 remains open before merge.

- [ ] **Step 5: Monitor every check to completion**

Use `gh pr checks --watch` and inspect every exact-SHA run and failed/skipped job. Require the landing validation, Node platform tests, native Windows tests triggered by README changes, and all repository-required checks to pass. On PRs, Pages publish/deploy must be absent or intentionally skipped while validation passes with read-only permissions.

If a check fails, identify the root cause from logs, add a focused regression, fix through review, re-run the complete relevant gate, push the new exact SHA, and monitor again. Do not merge the PR.

- [ ] **Step 6: Final handoff**

Read and use `superpowers:finishing-a-development-branch`. Preserve the isolated worktree and open PR for user review. Report the PR URL, exact head SHA, test totals, check statuses, and any post-merge one-time Pages setting. Keep the later `.NET` cleanup request outside this PR.

Provide a user-authorized post-merge checklist rather than merging autonomously: monitor the Pages workflow at the exact merge SHA, read back that GitHub Actions is the Pages source, test `https://far1h.github.io/ScreenFix/` in a private session with JavaScript enabled and disabled at 375×812, 768×1024, 1024×768, and 1440×900, and confirm issue #7 closed through the merged `Fixes #7` reference.
