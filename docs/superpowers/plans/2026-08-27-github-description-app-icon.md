# GitHub Description and macOS App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set the GitHub repository description and add the approved Screen Patch Finder/Applications icon to the manually packaged macOS app without changing its menu-bar-only runtime behavior.

**Architecture:** Keep one deterministic SVG source and generate the release `.icns` during macOS packaging with built-in `sips` and `iconutil`. Extend the existing bundle assembler and add a black-box package regression test; apply and verify the GitHub metadata separately through `gh`.

**Tech Stack:** Bash, SVG, macOS `sips`, `iconutil`, `plutil`, `codesign`, `ditto`, `unzip`, GitHub CLI.

---

## File Structure

- Create `native/macos/Resources/ScreenFixAppIcon.svg`: canonical Screen Patch vector artwork.
- Create `native/macos/scripts/build-app-icon.sh`: isolated SVG-to-ICNS generator and representation validator.
- Create `native/macos/scripts/test-package-arm64.sh`: black-box regression test for bundle metadata, resources, signatures, and ZIP contents.
- Modify `native/macos/Resources/Info.plist`: associate `ScreenFix.icns` with the app bundle.
- Modify `native/macos/scripts/package-arm64.sh`: generate, copy, verify, sign, and archive the app icon.
- Modify `native/macos/README.md`: document the new source and package test concisely.
- Update GitHub repository metadata through `gh`; no tracked file represents that state.

### Task 1: Reproduce the missing packaged app icon

**Files:**
- Create: `native/macos/scripts/test-package-arm64.sh`
- Test: `native/macos/scripts/test-package-arm64.sh`

- [ ] **Step 1: Write the black-box package regression test**

Create the executable script below. It intentionally tests the release artifact rather
than Swift runtime code.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$MACOS_DIR/artifacts/ScreenFix.app"
ZIP_PATH="$MACOS_DIR/artifacts/ScreenFix-macos-arm64.zip"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenfix-package-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

assert_png_size() {
  local path="$1"
  local expected="$2"
  local width
  local height
  width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  test "$width" = "$expected"
  test "$height" = "$expected"
}

"$SCRIPT_DIR/package-arm64.sh" >/dev/null

test -d "$APP_PATH"
test -f "$ZIP_PATH"
test "$(plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist")" = "ScreenFix.icns"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = "true"
test -s "$APP_PATH/Contents/Resources/ScreenFix.icns"
test -f "$APP_PATH/Contents/Resources/ScreenFixMenuIcon.png"

ICONSET_PATH="$TEMP_DIR/ScreenFix.iconset"
iconutil -c iconset "$APP_PATH/Contents/Resources/ScreenFix.icns" -o "$ICONSET_PATH"

while IFS=: read -r name size; do
  test -f "$ICONSET_PATH/$name"
  assert_png_size "$ICONSET_PATH/$name" "$size"
done <<'SIZES'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
SIZES

codesign --verify --strict --verbose=2 "$APP_PATH"
unzip -t "$ZIP_PATH" >/dev/null
unzip -Z1 "$ZIP_PATH" | grep -q '^ScreenFix.app/Contents/Resources/ScreenFix.icns$'

ditto -x -k "$ZIP_PATH" "$TEMP_DIR/extracted"
EXTRACTED_APP="$TEMP_DIR/extracted/ScreenFix.app"
test "$(plutil -extract CFBundleIconFile raw "$EXTRACTED_APP/Contents/Info.plist")" = "ScreenFix.icns"
test "$(plutil -extract LSUIElement raw "$EXTRACTED_APP/Contents/Info.plist")" = "true"
test -s "$EXTRACTED_APP/Contents/Resources/ScreenFix.icns"
codesign --verify --strict --verbose=2 "$EXTRACTED_APP"
```

- [ ] **Step 2: Make the regression script executable**

Run:

```bash
chmod 755 native/macos/scripts/test-package-arm64.sh
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
native/macos/scripts/test-package-arm64.sh
```

Expected: FAIL after packaging because `plutil` cannot extract the missing
`CFBundleIconFile` key. Confirm the failure is not from compilation, signing, or a typo.

- [ ] **Step 4: Commit the demonstrated regression**

```bash
git add native/macos/scripts/test-package-arm64.sh
git commit -m "test: reproduce missing macOS app icon"
```

### Task 2: Build the approved Screen Patch ICNS artifact

**Files:**
- Create: `native/macos/Resources/ScreenFixAppIcon.svg`
- Create: `native/macos/scripts/build-app-icon.sh`
- Test: `native/macos/scripts/test-package-arm64.sh`

- [ ] **Step 1: Add the exact approved SVG source**

Create `native/macos/Resources/ScreenFixAppIcon.svg`:

```svg
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 220">
  <defs>
    <linearGradient id="background" x1="28" y1="18" x2="192" y2="207" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFB23E"/>
      <stop offset="0.54" stop-color="#F46744"/>
      <stop offset="1" stop-color="#A92C4D"/>
    </linearGradient>
  </defs>
  <rect x="10" y="10" width="200" height="200" rx="45" fill="url(#background)"/>
  <rect x="38" y="54" width="144" height="103" rx="18" fill="#FFF7E8"/>
  <rect x="50" y="67" width="120" height="77" rx="9" fill="#FFD8A0"/>
  <path d="M57 77L91 134" stroke="#FF9F61" stroke-width="8" stroke-linecap="round" opacity="0.8"/>
  <path d="M133 77L163 126" stroke="#FF9F61" stroke-width="8" stroke-linecap="round" opacity="0.8"/>
  <rect x="96" y="54" width="28" height="103" rx="8" fill="#27212B"/>
  <path d="M88 172H132" stroke="#FFF5E5" stroke-width="10" stroke-linecap="round"/>
  <path d="M110 158V172" stroke="#FFF5E5" stroke-width="10" stroke-linecap="round"/>
  <path d="M103 75H117M103 94H117M103 113H117M103 132H117" stroke="#F7C46C" stroke-width="4" stroke-linecap="round"/>
</svg>
```

- [ ] **Step 2: Add the focused icon builder**

Create `native/macos/scripts/build-app-icon.sh`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_PATH="$MACOS_DIR/Resources/ScreenFixAppIcon.svg"
OUTPUT_DIR="$MACOS_DIR/.build/manual-release"
OUTPUT_PATH="$OUTPUT_DIR/ScreenFix.icns"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenfix-icon.XXXXXX")"
ICONSET_PATH="$TEMP_DIR/ScreenFix.iconset"
ROUNDTRIP_PATH="$TEMP_DIR/roundtrip.iconset"
trap 'rm -rf "$TEMP_DIR"' EXIT

assert_png_size() {
  local path="$1"
  local expected="$2"
  local width
  local height
  width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  test "$width" = "$expected"
  test "$height" = "$expected"
}

command -v sips >/dev/null
command -v iconutil >/dev/null
test -f "$SOURCE_PATH"
mkdir -p "$OUTPUT_DIR" "$ICONSET_PATH"

MASTER_PATH="$TEMP_DIR/ScreenFix-1024.png"
sips -s format png -z 1024 1024 "$SOURCE_PATH" --out "$MASTER_PATH" >/dev/null
assert_png_size "$MASTER_PATH" 1024

while IFS=: read -r name size; do
  sips -z "$size" "$size" "$MASTER_PATH" --out "$ICONSET_PATH/$name" >/dev/null
  assert_png_size "$ICONSET_PATH/$name" "$size"
done <<'SIZES'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
SIZES

TEMP_ICON_PATH="$TEMP_DIR/ScreenFix.icns"
iconutil -c icns "$ICONSET_PATH" -o "$TEMP_ICON_PATH"
test -s "$TEMP_ICON_PATH"
iconutil -c iconset "$TEMP_ICON_PATH" -o "$ROUNDTRIP_PATH"

while IFS=: read -r name size; do
  test -f "$ROUNDTRIP_PATH/$name"
  assert_png_size "$ROUNDTRIP_PATH/$name" "$size"
done <<'SIZES'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
SIZES

TEMP_OUTPUT="$OUTPUT_DIR/.ScreenFix.icns.$$"
cp "$TEMP_ICON_PATH" "$TEMP_OUTPUT"
mv "$TEMP_OUTPUT" "$OUTPUT_PATH"
printf '%s\n' "$OUTPUT_PATH"
```

- [ ] **Step 3: Make the builder executable**

```bash
chmod 755 native/macos/scripts/build-app-icon.sh
```

- [ ] **Step 4: Run and inspect the builder increment**

Run:

```bash
native/macos/scripts/build-app-icon.sh
sips -g pixelWidth -g pixelHeight native/macos/.build/manual-release/ScreenFix.icns
```

Expected: the builder exits 0, prints the `.build/manual-release/ScreenFix.icns` path,
and `sips` reports a valid multi-representation ICNS. This does not make the package test
green yet because the plist and bundle assembly are still missing.

- [ ] **Step 5: Render and inspect the master at normal and small sizes**

Render the SVG at 1024, 32, and 16 pixels with `sips`, then inspect all three images.
Confirm the warm field, cream monitor, dark center mask, and stand match the approved
Screen Patch geometry and remain distinguishable at both small sizes.

### Task 3: Integrate the icon into the signed app bundle

**Files:**
- Modify: `native/macos/Resources/Info.plist`
- Modify: `native/macos/scripts/package-arm64.sh`
- Test: `native/macos/scripts/test-package-arm64.sh`

- [ ] **Step 1: Reference the ICNS resource from the plist**

Add immediately after `CFBundleDisplayName`:

```xml
    <key>CFBundleIconFile</key>
    <string>ScreenFix.icns</string>
```

- [ ] **Step 2: Generate and constrain the icon builder output**

Immediately after `BINARY_PATH` is validated in `package-arm64.sh`, add:

```bash
ICON_OUTPUT="$("$MACOS_DIR/scripts/build-app-icon.sh")"
ICON_PATH="$(printf '%s\n' "$ICON_OUTPUT" | tail -n 1)"
case "$ICON_PATH" in
    "$RELEASE_DIR"/*) ;;
    *) printf 'Unexpected icon path: %s\n' "$ICON_PATH" >&2; exit 1 ;;
esac
test -s "$ICON_PATH"
```

- [ ] **Step 3: Copy and validate the app icon before signing**

Copy the generated icon beside the menu icon:

```bash
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/ScreenFix.icns"
```

Add these assertions with the existing plist and resource checks:

```bash
test "$(plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist")" = "ScreenFix.icns"
test -s "$APP_PATH/Contents/Resources/ScreenFix.icns"
```

- [ ] **Step 4: Require the icon in the ZIP**

Add with the existing exact ZIP-entry assertions:

```bash
printf '%s\n' "$ZIP_ENTRIES" | grep -q '^ScreenFix.app/Contents/Resources/ScreenFix.icns$'
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
native/macos/scripts/test-package-arm64.sh
```

Expected: PASS with exit 0 after verifying both the source bundle and freshly extracted
ZIP bundle, every icon representation, `LSUIElement=true`, and strict signatures.

- [ ] **Step 6: Verify the test really guards the fix**

Temporarily remove or change the `CFBundleIconFile` value, run the focused test, and
confirm it fails at the exact association assertion. Restore the correct value and run
the test again to confirm PASS.

- [ ] **Step 7: Commit the icon implementation**

```bash
git add native/macos/Resources/ScreenFixAppIcon.svg \
  native/macos/Resources/Info.plist \
  native/macos/scripts/build-app-icon.sh \
  native/macos/scripts/package-arm64.sh
git commit -m "fix: add native macOS app icon"
```

### Task 4: Document the reproducible icon workflow

**Files:**
- Modify: `native/macos/README.md`

- [ ] **Step 1: Add the focused package test to collaborator commands**

Update the Build and test command block to include:

```bash
native/macos/scripts/test-package-arm64.sh
```

- [ ] **Step 2: Explain the source/generated boundary concisely**

Add one short paragraph: `Resources/ScreenFixAppIcon.svg` is the editable source;
`build-app-icon.sh` creates the `.icns` during packaging with macOS system tools, so no
generated icon files are committed and full Xcode is not required.

- [ ] **Step 3: Verify and commit the docs increment**

Run:

```bash
git diff --check
```

Expected: exit 0.

```bash
git add native/macos/README.md
git commit -m "docs: explain macOS icon packaging"
```

### Task 5: Apply and verify the GitHub repository description

**Files:**
- External state: `github.com/far1h/ScreenFix` repository metadata

- [ ] **Step 1: Confirm issue #1 and current metadata are still open/empty**

Run:

```bash
gh issue view 1 --json number,state,title,body,url
gh repo view --json description
```

Expected: issue #1 is OPEN and the description is empty.

- [ ] **Step 2: Set the exact description**

Run:

```bash
gh repo edit --description "Masks damaged display regions and keeps ordinary windows in the usable area on either side."
```

- [ ] **Step 3: Read back and compare exact state**

Run:

```bash
test "$(gh repo view --json description --jq .description)" = \
  "Masks damaged display regions and keeps ordinary windows in the usable area on either side."
```

Expected: exit 0.

- [ ] **Step 4: Close issue #1 with the verified outcome**

Run:

```bash
gh issue close 1 --comment "Set the repository description and verified the exact GitHub metadata value."
gh issue view 1 --json state --jq .state
```

Expected: `CLOSED`.

### Task 6: Complete verification and open the pull request

**Files:**
- Verify all tracked changes and external issue state.

- [ ] **Step 1: Run focused package verification**

```bash
native/macos/scripts/test-package-arm64.sh
```

Expected: exit 0.

- [ ] **Step 2: Run the complete native suite**

```bash
native/macos/scripts/run-tests.sh
```

Expected: `Executed 244 tests, 0 failures`.

- [ ] **Step 3: Run the complete Lua suite**

```bash
lua tests/run.lua
```

Expected: exit 0 with every test reporting PASS.

- [ ] **Step 4: Verify the clean patch and ignored-artifact boundary**

```bash
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
git ls-files native/macos/.build native/macos/artifacts
```

Expected: no whitespace errors, no unintended uncommitted files, and no generated
release artifacts tracked.

- [ ] **Step 5: Inspect a fresh extracted app in Finder**

Open the app extracted by `test-package-arm64.sh` or extract a new copy from the ZIP.
Confirm Finder/Applications shows the Screen Patch icon at normal and small sizes. Launch
it and confirm it remains menu-bar-only with no Dock icon.

- [ ] **Step 6: Request independent code review and fix important findings**

Review the full `origin/main...HEAD` diff for correctness, simplicity, shell safety,
project conventions, and issue coverage. Re-run affected verification after fixes.

- [ ] **Step 7: Push the branch**

```bash
git push -u origin fix/remaining-github-issues
```

- [ ] **Step 8: Open the pull request**

Create a PR targeting `main` whose body summarizes the Screen Patch icon pipeline,
records the exact verification commands, notes that issue #1 was completed as GitHub
metadata, and includes:

```text
Fixes #2
```

- [ ] **Step 9: Verify PR and issue state**

Run:

```bash
gh pr view --json number,title,url,state,baseRefName,headRefName
gh issue list --state open --limit 100 --json number,title,url
```

Expected: the PR is OPEN against `main`, issue #1 is closed, and issue #2 remains open
until the PR merges.
