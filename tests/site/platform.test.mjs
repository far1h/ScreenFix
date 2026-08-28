import assert from "node:assert/strict";
import test from "node:test";

import { applyPlatformRecommendation, detectPlatform } from "../../site/platform.mjs";


class FakeClassList {
  constructor(...tokens) {
    this.tokens = new Set(tokens);
  }

  add(token) {
    this.tokens.add(token);
  }

  contains(token) {
    return this.tokens.has(token);
  }
}


class FakeLabel {
  constructor(textContent, hidden = true) {
    this.hidden = hidden;
    this.textContent = textContent;
  }
}


class FakeOption {
  constructor(platform) {
    this.platform = platform;
    this.classList = new FakeClassList();
    this.hidden = false;
    this.label = new FakeLabel(
      platform === "macos"
        ? "macOS detected — Apple Silicon required"
        : "Recommended for this device",
    );
  }

  querySelector(selector) {
    assert.equal(selector, "[data-device-recommendation]");
    return this.label;
  }
}


class FakeGroup {
  constructor(...platforms) {
    this.children = platforms.map((platform) => new FakeOption(platform));
  }

  querySelector(selector) {
    const match = selector.match(/^\[data-platform-option="(windows|macos)"\]$/);
    assert.ok(match, `unexpected option selector: ${selector}`);
    return this.children.find((option) => option.platform === match[1]) ?? null;
  }

  prepend(option) {
    const index = this.children.indexOf(option);
    assert.notEqual(index, -1, "prepend must move an existing option");
    this.children.splice(index, 1);
    this.children.unshift(option);
  }
}


class FakeDocument {
  constructor(...groups) {
    this.groups = groups;
  }

  querySelectorAll(selector) {
    assert.equal(selector, "[data-platform-group]");
    return this.groups;
  }
}


function platforms(group) {
  return group.children.map((option) => option.platform);
}


test("detects Windows from userAgentData.platform", () => {
  assert.equal(detectPlatform({ userAgentData: { platform: "Windows", mobile: false } }), "windows");
});


test("detects macOS from userAgentData.platform", () => {
  assert.equal(detectPlatform({ userAgentData: { platform: "macOS", mobile: false } }), "macos");
});


test("detects Safari macOS through navigator.platform", () => {
  assert.equal(detectPlatform({ platform: "MacIntel", maxTouchPoints: 0 }), "macos");
});


test("detects Windows through navigator.userAgent", () => {
  assert.equal(detectPlatform({ userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }), "windows");
});


test("prefers userAgentData.platform over platform and userAgent", () => {
  assert.equal(
    detectPlatform({
      userAgentData: { platform: "Windows", mobile: false },
      platform: "MacIntel",
      userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0)",
      maxTouchPoints: 0,
    }),
    "windows",
  );
});


test("rejects a mobile userAgentData client", () => {
  assert.equal(
    detectPlatform({ userAgentData: { platform: "macOS", mobile: true } }),
    null,
  );
});


for (const [device, userAgent] of [
  ["Android", "Mozilla/5.0 (Linux; Android 15)"],
  ["iPhone", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"],
  ["iPad", "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)"],
]) {
  test(`rejects the ${device} user-agent token`, () => {
    assert.equal(detectPlatform({ userAgent }), null, userAgent);
  });
}


test("rejects touch-capable MacIntel clients that may be iPadOS", () => {
  assert.equal(detectPlatform({ platform: "MacIntel", maxTouchPoints: 5 }), null);
});


test("rejects an Apple Safari Mobile token when touch points are unavailable", () => {
  assert.equal(
    detectPlatform({
      platform: "MacIntel",
      userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Mobile/15E148 Safari/604.1",
    }),
    null,
  );
});


test("returns null for Linux, empty, and missing platform information", () => {
  assert.equal(detectPlatform({ platform: "Linux x86_64" }), null);
  assert.equal(detectPlatform({ platform: "", userAgent: "" }), null);
  assert.equal(detectPlatform({}), null);
  assert.equal(detectPlatform(null), null);
});


test("detectPlatform returns only supported result values", () => {
  const results = [
    detectPlatform({ userAgentData: { platform: "Windows", mobile: false } }),
    detectPlatform({ platform: "MacIntel", maxTouchPoints: 0 }),
    detectPlatform({ platform: "Linux x86_64" }),
  ];
  assert.ok(results.every((result) => ["windows", "macos", null].includes(result)));
});


test("macOS recommendation moves existing options first in every group", () => {
  const groups = [new FakeGroup("windows", "macos"), new FakeGroup("windows", "macos")];

  applyPlatformRecommendation(new FakeDocument(...groups), "macos");

  for (const group of groups) {
    assert.deepEqual(platforms(group), ["macos", "windows"]);
    assert.equal(group.children.length, 2);
    assert.ok(group.children.every((option) => option.hidden === false));
    assert.equal(group.children[0].classList.contains("is-recommended"), true);
  }
});


test("Windows recommendation keeps existing Windows options first", () => {
  const groups = [new FakeGroup("windows", "macos"), new FakeGroup("macos", "windows")];

  applyPlatformRecommendation(new FakeDocument(...groups), "windows");

  assert.deepEqual(platforms(groups[0]), ["windows", "macos"]);
  assert.deepEqual(platforms(groups[1]), ["windows", "macos"]);
  assert.equal(groups[0].children[0].classList.contains("is-recommended"), true);
  assert.equal(groups[1].children[0].classList.contains("is-recommended"), true);
});


test("only matched existing recommendation labels are revealed", () => {
  const group = new FakeGroup("windows", "macos");

  applyPlatformRecommendation(new FakeDocument(group), "macos");

  const macos = group.children.find((option) => option.platform === "macos");
  const windows = group.children.find((option) => option.platform === "windows");
  assert.equal(macos.label.hidden, false);
  assert.equal(windows.label.hidden, true);
  assert.equal(macos.label.textContent, "macOS detected — Apple Silicon required");
  assert.equal(windows.label.textContent, "Recommended for this device");
});


test("MacIntel reveals architecture-safe macOS advice in every group", () => {
  const groups = [new FakeGroup("windows", "macos"), new FakeGroup("windows", "macos")];
  const platform = detectPlatform({ platform: "MacIntel", maxTouchPoints: 0 });

  applyPlatformRecommendation(new FakeDocument(...groups), platform);

  const labels = groups.map((group) => group.children[0].label);
  assert.ok(labels.every((label) => label.hidden === false));
  assert.deepEqual(
    labels.map((label) => label.textContent),
    [
      "macOS detected — Apple Silicon required",
      "macOS detected — Apple Silicon required",
    ],
  );
});


test("both download options remain present and visible", () => {
  const group = new FakeGroup("windows", "macos");

  applyPlatformRecommendation(new FakeDocument(group), "windows");

  assert.deepEqual(new Set(platforms(group)), new Set(["windows", "macos"]));
  assert.equal(group.children.length, 2);
  assert.ok(group.children.every((option) => option.hidden === false));
});


test("unknown platform leaves groups unchanged", () => {
  const group = new FakeGroup("windows", "macos");
  const before = platforms(group);

  applyPlatformRecommendation(new FakeDocument(group), null);

  assert.deepEqual(platforms(group), before);
  assert.ok(group.children.every((option) => !option.classList.contains("is-recommended")));
  assert.ok(group.children.every((option) => option.label.hidden));
});


test("repeating the recommendation is idempotent", () => {
  const group = new FakeGroup("windows", "macos");
  const documentRoot = new FakeDocument(group);

  applyPlatformRecommendation(documentRoot, "macos");
  const firstOptions = [...group.children];
  applyPlatformRecommendation(documentRoot, "macos");

  assert.deepEqual(group.children, firstOptions);
  assert.equal(group.children[0].classList.tokens.size, 1);
});
