/** Return the supported desktop platform reported by a Navigator-like client. */
export function detectPlatform(client) {
  if (!client) {
    return null;
  }

  const userAgentData = client.userAgentData;
  const userAgent = client.userAgent || "";
  if (
    userAgentData?.mobile === true
    || /Android|iPhone|iPad|Mobile/i.test(userAgent)
    || (client.platform === "MacIntel" && client.maxTouchPoints > 1)
  ) {
    return null;
  }

  const platform = userAgentData?.platform || client.platform || userAgent;
  if (/Windows|Win(?:32|64|CE)/i.test(platform)) {
    return "windows";
  }
  if (/macOS|MacIntel|Macintosh/i.test(platform)) {
    return "macos";
  }
  return null;
}


/** Move the matching existing download option first and reveal its label. */
export function applyPlatformRecommendation(documentRoot, platform) {
  if (platform !== "windows" && platform !== "macos") {
    return;
  }

  for (const group of documentRoot.querySelectorAll("[data-platform-group]")) {
    const option = group.querySelector(`[data-platform-option="${platform}"]`);
    if (!option) {
      continue;
    }
    group.prepend(option);
    option.classList.add("is-recommended");
    const label = option.querySelector("[data-device-recommendation]");
    if (label) {
      label.hidden = false;
    }
  }
}


if (typeof window !== "undefined" && typeof document !== "undefined") {
  applyPlatformRecommendation(document, detectPlatform(window.navigator));
}
