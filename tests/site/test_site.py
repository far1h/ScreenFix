from __future__ import annotations

import math
import re
import shutil
import stat
import tempfile
import unittest
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "site" / "assets"

EXPECTED_SITE_FILES = {
    ".nojekyll",
    "index.html",
    "styles.css",
    "assets/screenfix-icon.svg",
    "assets/damaged-display.jpg",
    "assets/how-mark-strip.jpg",
    "assets/how-mask-strip.jpg",
    "assets/how-use-space.jpg",
    "assets/privacy-local.jpg",
    "assets/requirements-platforms.jpg",
    "assets/result-calibration.jpg",
    "assets/result-mask.jpg",
}
PAGES_WORKFLOW = ROOT / ".github" / "workflows" / "pages.yml"
PAGES_CONCURRENCY_GROUP = (
    "${{ github.event_name == 'pull_request' && "
    "format('screenfix-pages-pr-{0}', github.event.pull_request.number) "
    "|| 'screenfix-pages-deploy' }}"
)
README = ROOT / "README.md"
README_SITE_URL = "https://far1h.github.io/ScreenFix/"
README_RELEASES_URL = "https://github.com/far1h/ScreenFix/releases"
README_ROOT_SITE_PATTERN = re.compile(r"^[├└]──[ \t]+site/(?:[ \t]+.*)?$", re.MULTILINE)
README_VALIDATION_COMMAND = "python3 -m unittest discover -s tests/site -p 'test_*.py' -v"
README_COPY_BLOCK_MIN_LENGTH = 60


class ReadmeContractError(AssertionError):
    """Report a README contract violation."""


class WorkflowContractError(AssertionError):
    """Report a GitHub Pages workflow contract violation."""


def _require_readme(condition: bool, message: str) -> None:
    """Raise a focused contract failure when a README rule is false."""
    if not condition:
        raise ReadmeContractError(message)


def _readme_section(source: str, heading: str) -> str:
    """Return the body of one level-two README section."""
    match = re.search(rf"(?ms)^{re.escape(heading)}\n(.*?)(?=^## |\Z)", source)
    _require_readme(match is not None, f"README must keep the {heading} section")
    return match.group(1)


def _markdown_links(source: str) -> tuple[tuple[str, str], ...]:
    """Return ordinary inline Markdown link labels and targets."""
    return tuple(re.findall(r"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)\)", source))


def _validate_readme_links(source: str) -> None:
    """Require one descriptive public-site link and the Releases link."""
    _require_readme(
        source.count(README_SITE_URL) == 1,
        "README must contain the exact default Pages URL exactly once",
    )
    links = _markdown_links(source)
    site_labels = [label.strip() for label, target in links if target == README_SITE_URL]
    _require_readme(
        len(site_labels) == 1,
        "README must link the exact default Pages URL exactly once",
    )
    _require_readme(
        bool(site_labels[0])
        and re.search(r"\b(?:ScreenFix|website)\b", site_labels[0], re.IGNORECASE) is not None,
        "README Pages link must have a descriptive ScreenFix or website label",
    )
    _require_readme(
        any(target == README_RELEASES_URL for _, target in links),
        "README must keep the GitHub Releases URL",
    )


def _validate_readme_file_tree(source: str) -> None:
    """Require the dependency-free site in the root file tree."""
    files = _readme_section(source, "## Files")
    tree = re.search(r"(?ms)^```text\n(.*?)\n```$", files)
    _require_readme(tree is not None, "README Files must keep its text file tree")
    _require_readme(
        len(README_ROOT_SITE_PATTERN.findall(tree.group(1))) == 1,
        "README root file tree must contain one site/ entry",
    )


def _validate_readme_collaboration(source: str) -> None:
    """Require the exact site validation command under Collaborating."""
    _require_readme(
        source.count(README_VALIDATION_COMMAND) == 1,
        "README must contain the exact site validation command exactly once",
    )
    collaborating = _readme_section(source, "## Collaborating")
    command_block = f"```bash\n{README_VALIDATION_COMMAND}\n```"
    _require_readme(
        collaborating.count(command_block) == 1,
        "README Collaborating must contain the site command in its own bash block",
    )
    context = collaborating[: collaborating.index(command_block)].rstrip().split("\n\n")[-1]
    _require_readme(
        "validat" in context.lower() and "landing page" in context.lower(),
        "README must identify the command as landing-page validation",
    )


def _validate_readme_native_content(source: str) -> None:
    """Require existing Releases and native installation content to remain."""
    required_once = (
        "## Install the native Windows app",
        "## Install the native macOS app",
        "1. Download `ScreenFix-Windows-x64.exe` from the Releases page.",
        "1. Extract `ScreenFix-macos-arm64.zip`.",
    )
    _require_readme(
        any(target == README_RELEASES_URL for _, target in _markdown_links(source)),
        "README must keep the GitHub Releases URL",
    )
    for required in required_once:
        _require_readme(
            source.count(required) == 1,
            f"README must keep exactly one native installation entry: {required}",
        )


def _markdown_headings(source: str) -> tuple[str, ...]:
    """Return Markdown headings outside fenced code blocks."""
    headings: list[str] = []
    in_fence = False
    for line in source.splitlines():
        if re.match(r"^\s*```", line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = re.match(r"^#{1,6}[ \t]+(.+?)(?:[ \t]+#+)?$", line)
        if match:
            headings.append(match.group(1).strip())
    return tuple(headings)


def _validate_readme_scope(source: str) -> None:
    """Reject substantive copied landing-page sections while allowing isolated mentions."""
    copied_section_headings = {
        "faq",
        "privacy",
        "Questions before you download.",
        "ScreenFix stays on your computer.",
        "Work around a damaged screen.",
        "Give the damage its own space.",
        "What it looks like in use.",
        "Download ScreenFix.",
    }
    headings = {heading.casefold() for heading in _markdown_headings(source)}
    copied_headings = {heading for heading in copied_section_headings if heading.casefold() in headings}
    _require_readme(
        not copied_headings,
        f"README must not copy landing-page section headings: {sorted(copied_headings)}",
    )
    copied_blocks, faq_summaries = _landing_page_readme_copy()
    normalized_source = " ".join(source.split())
    _require_readme(
        not any(block in normalized_source for block in copied_blocks),
        "README must not copy full landing-page privacy, FAQ, or download blocks",
    )
    copied_questions = sum(summary in normalized_source for summary in faq_summaries)
    _require_readme(copied_questions < 2, "README must not copy the landing-page FAQ block")


@dataclass(frozen=True)
class _WorkflowLine:
    """Represent one significant YAML source line."""

    number: int
    indent: int
    content: str


@dataclass(frozen=True)
class _WorkflowEntry:
    """Represent one source-aware YAML mapping entry."""

    value: str
    children: tuple[_WorkflowLine, ...]
    number: int


def _workflow_lines(source: str) -> tuple[_WorkflowLine, ...]:
    """Return significant YAML lines while preserving source structure."""
    lines: list[_WorkflowLine] = []
    for number, raw_line in enumerate(source.splitlines(), start=1):
        if "\t" in raw_line[: len(raw_line) - len(raw_line.lstrip())]:
            raise WorkflowContractError(f"line {number}: tabs are not allowed for YAML indentation")
        content = raw_line.lstrip(" ")
        if not content or content.startswith("#"):
            continue
        lines.append(_WorkflowLine(number, len(raw_line) - len(content), content.rstrip()))
    return tuple(lines)


def _workflow_mapping(lines: tuple[_WorkflowLine, ...], label: str) -> dict[str, _WorkflowEntry]:
    """Parse one YAML mapping level and reject duplicate source keys."""
    if not lines:
        raise WorkflowContractError(f"{label} must be a non-empty mapping")
    indent = min(line.indent for line in lines)
    entry_indexes = [index for index, line in enumerate(lines) if line.indent == indent]
    entries: dict[str, _WorkflowEntry] = {}
    for offset, index in enumerate(entry_indexes):
        line = lines[index]
        match = re.fullmatch(r"([A-Za-z0-9_-]+):(?:\s*(.*))?", line.content)
        if not match:
            raise WorkflowContractError(f"line {line.number}: invalid {label} mapping entry")
        key, value = match.group(1), match.group(2) or ""
        if key in entries:
            raise WorkflowContractError(f"line {line.number}: duplicate {label} key {key!r}")
        end = entry_indexes[offset + 1] if offset + 1 < len(entry_indexes) else len(lines)
        children = tuple(lines[index + 1 : end])
        if any(child.indent <= indent for child in children):
            raise WorkflowContractError(f"line {line.number}: malformed {label} block")
        entries[key] = _WorkflowEntry(value, children, line.number)
    return entries


def _workflow_sequence(lines: tuple[_WorkflowLine, ...], label: str) -> list[dict[str, _WorkflowEntry]]:
    """Parse a YAML sequence of mapping items."""
    if not lines:
        raise WorkflowContractError(f"{label} must be a non-empty sequence")
    indent = min(line.indent for line in lines)
    item_indexes = [
        index for index, line in enumerate(lines) if line.indent == indent and line.content.startswith("- ")
    ]
    if not item_indexes or any(
        line.indent == indent and not line.content.startswith("- ") for line in lines
    ):
        raise WorkflowContractError(f"{label} must contain only mapping items")
    items: list[dict[str, _WorkflowEntry]] = []
    for offset, index in enumerate(item_indexes):
        end = item_indexes[offset + 1] if offset + 1 < len(item_indexes) else len(lines)
        item_lines = list(lines[index:end])
        first = item_lines[0]
        nested_indent = min(
            (line.indent for line in item_lines[1:] if line.indent > indent),
            default=indent + 2,
        )
        item_lines[0] = _WorkflowLine(first.number, nested_indent, first.content[2:])
        items.append(_workflow_mapping(tuple(item_lines), f"{label} item"))
    return items


def _require_workflow(condition: bool, message: str) -> None:
    """Raise a focused contract failure when a workflow rule is false."""
    if not condition:
        raise WorkflowContractError(message)


def _require_keys(mapping: dict[str, _WorkflowEntry], expected: set[str], label: str) -> None:
    """Require a mapping to expose exactly the expected keys."""
    actual = set(mapping)
    _require_workflow(actual == expected, f"{label} keys must be {sorted(expected)}; got {sorted(actual)}")


def _scalar_list(entry: _WorkflowEntry, label: str) -> list[str]:
    """Return the scalar values from a YAML block sequence."""
    _require_workflow(entry.value == "" and bool(entry.children), f"{label} must be a block sequence")
    indent = min(line.indent for line in entry.children)
    values: list[str] = []
    for line in entry.children:
        _require_workflow(
            line.indent == indent and line.content.startswith("- "),
            f"line {line.number}: {label} must contain only scalar items",
        )
        values.append(line.content[2:].strip())
    return values


def _run_lines(step: dict[str, _WorkflowEntry], label: str) -> tuple[str, ...]:
    """Return normalized shell lines from a workflow run step."""
    run = step.get("run")
    _require_workflow(run is not None, f"{label} must be a run step")
    if run.value in {"|", "|-", "|+"}:
        _require_workflow(bool(run.children), f"{label} run block must not be empty")
        return tuple(line.content for line in run.children)
    _require_workflow(not run.children, f"{label} has malformed run syntax")
    return (run.value,)


def _validate_checkout_step(step: dict[str, _WorkflowEntry], label: str) -> None:
    """Require a pinned, PR-head-safe checkout with credentials disabled."""
    _require_keys(step, {"name", "uses", "with"}, label)
    _require_workflow(step["uses"].value == "actions/checkout@v7", f"{label} must use checkout@v7")
    checkout_with = _workflow_mapping(step["with"].children, f"{label} with")
    _require_keys(checkout_with, {"ref", "persist-credentials"}, f"{label} with")
    _require_workflow(
        checkout_with["ref"].value == "${{ github.event.pull_request.head.sha || github.sha }}",
        f"{label} must checkout the triggering commit",
    )
    _require_workflow(
        checkout_with["persist-credentials"].value == "false",
        f"{label} must disable persisted credentials",
    )


def _validate_permissions(entry: _WorkflowEntry, expected: dict[str, str], label: str) -> None:
    """Require an exact least-privilege permissions mapping."""
    permissions = _workflow_mapping(entry.children, label)
    _require_keys(permissions, set(expected), label)
    for key, value in expected.items():
        _require_workflow(permissions[key].value == value, f"{label} must set {key}: {value}")


def validate_pages_workflow(source: str) -> None:
    """Validate the Pages workflow contract."""
    lines = _workflow_lines(source)
    top = _workflow_mapping(lines, "top-level")
    _require_keys(top, {"name", "on", "permissions", "concurrency", "jobs"}, "top-level")
    _require_workflow(top["name"].value == "ScreenFix Pages", "workflow name must be ScreenFix Pages")

    triggers = _workflow_mapping(top["on"].children, "triggers")
    _require_keys(triggers, {"pull_request", "push", "workflow_dispatch"}, "triggers")
    _require_workflow(
        triggers["pull_request"].value == "{}" and not triggers["pull_request"].children,
        "pull_request must be unfiltered",
    )
    _require_workflow(
        triggers["workflow_dispatch"].value == "{}" and not triggers["workflow_dispatch"].children,
        "workflow_dispatch must be unfiltered",
    )
    push = _workflow_mapping(triggers["push"].children, "push trigger")
    _require_keys(push, {"branches"}, "push trigger")
    _require_workflow(_scalar_list(push["branches"], "push branches") == ["main"], "push must target only main")
    _require_workflow(not re.search(r"(?m)^\s*paths(?:-ignore)?:", source), "path filters are forbidden")

    _validate_permissions(top["permissions"], {"contents": "read"}, "top-level permissions")
    concurrency = _workflow_mapping(top["concurrency"].children, "concurrency")
    _require_keys(concurrency, {"group", "cancel-in-progress"}, "concurrency")
    _require_workflow(
        concurrency["group"].value == PAGES_CONCURRENCY_GROUP,
        "concurrency must isolate each PR from the shared deployment group",
    )
    _require_workflow(concurrency["cancel-in-progress"].value == "false", "concurrency cancellation must be false")

    jobs = _workflow_mapping(top["jobs"].children, "jobs")
    _require_keys(jobs, {"validate", "publish", "deploy"}, "jobs")
    validate = _workflow_mapping(jobs["validate"].children, "validate job")
    publish = _workflow_mapping(jobs["publish"].children, "publish job")
    deploy = _workflow_mapping(jobs["deploy"].children, "deploy job")
    _require_keys(validate, {"runs-on", "permissions", "steps"}, "validate job")
    _require_keys(publish, {"needs", "if", "runs-on", "permissions", "steps"}, "publish job")
    _require_keys(deploy, {"needs", "if", "runs-on", "permissions", "environment", "steps"}, "deploy job")
    for job_name, job in (("validate", validate), ("publish", publish), ("deploy", deploy)):
        _require_workflow(job["runs-on"].value == "ubuntu-latest", f"{job_name} must run on ubuntu-latest")

    _validate_permissions(validate["permissions"], {"contents": "read"}, "validate permissions")
    _validate_permissions(
        publish["permissions"],
        {"contents": "read", "pages": "read"},
        "publish permissions",
    )
    _validate_permissions(
        deploy["permissions"],
        {"pages": "write", "id-token": "write"},
        "deploy permissions",
    )
    condition = "github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')"
    _require_workflow(publish["needs"].value == "validate", "publish must need validate")
    _require_workflow(publish["if"].value == condition, "publish condition must be main push or manual dispatch")
    _require_workflow(deploy["needs"].value == "publish", "deploy must need publish")
    _require_workflow(deploy["if"].value == condition, "deploy condition must be main push or manual dispatch")

    validate_steps = _workflow_sequence(validate["steps"].children, "validate steps")
    _require_workflow(len(validate_steps) == 3, "validate must have exactly three steps")
    _validate_checkout_step(validate_steps[0], "validate checkout")
    _require_keys(validate_steps[1], {"name", "run"}, "validate test step")
    test_command = "python3 -m unittest discover -s tests/site -p 'test_*.py' -v"
    _require_workflow(_run_lines(validate_steps[1], "validate test step") == (test_command,), "validate must run all site tests")
    _require_keys(validate_steps[2], {"name", "shell", "run"}, "validate archive step")
    _require_workflow(validate_steps[2]["shell"].value == "bash", "validate archive step must use bash")
    validate_archive_lines = (
        "set -euo pipefail",
        'validation_archive="$RUNNER_TEMP/pages-validation.tar"',
        'expected_manifest="$RUNNER_TEMP/pages-expected.txt"',
        'actual_manifest="$RUNNER_TEMP/pages-actual.txt"',
        'tar --dereference --hard-dereference --directory site -cf "$validation_archive" .',
        'find site -type f -print | sed \'s#^site/##\' | LC_ALL=C sort > "$expected_manifest"',
        'tar -tf "$validation_archive" | sed -e \'s#^\\./##\' -e \'/\\/$/d\' -e \'/^$/d\' | LC_ALL=C sort > "$actual_manifest"',
        'diff -u "$expected_manifest" "$actual_manifest"',
    )
    _require_workflow(
        _run_lines(validate_steps[2], "validate archive step") == validate_archive_lines,
        "validate must build and inspect the exact Pages-equivalent archive",
    )

    publish_steps = _workflow_sequence(publish["steps"].children, "publish steps")
    _require_workflow(len(publish_steps) == 5, "publish must have exactly five steps")
    _validate_checkout_step(publish_steps[0], "publish checkout")
    _require_keys(publish_steps[1], {"name", "run"}, "publish test step")
    _require_workflow(_run_lines(publish_steps[1], "publish test step") == (test_command,), "publish must rerun all site tests")
    _require_keys(publish_steps[2], {"name", "uses"}, "configure Pages step")
    _require_workflow(
        publish_steps[2]["uses"].value == "actions/configure-pages@v6",
        "publish must use configure-pages@v6",
    )
    _require_keys(publish_steps[3], {"name", "uses", "with"}, "upload Pages artifact step")
    _require_workflow(
        publish_steps[3]["uses"].value == "actions/upload-pages-artifact@v5",
        "publish must use upload-pages-artifact@v5",
    )
    upload_with = _workflow_mapping(publish_steps[3]["with"].children, "upload Pages artifact with")
    _require_keys(upload_with, {"path", "include-hidden-files"}, "upload Pages artifact with")
    _require_workflow(upload_with["path"].value == "site", "Pages artifact path must be site")
    _require_workflow(upload_with["include-hidden-files"].value == "true", "Pages artifact must include hidden files")
    _require_keys(publish_steps[4], {"name", "shell", "run"}, "inspect uploaded artifact step")
    _require_workflow(publish_steps[4]["shell"].value == "bash", "artifact inspection must use bash")
    publish_archive_lines = (
        "set -euo pipefail",
        'expected_manifest="$RUNNER_TEMP/pages-expected.txt"',
        'actual_manifest="$RUNNER_TEMP/pages-actual.txt"',
        'find site -type f -print | sed \'s#^site/##\' | LC_ALL=C sort > "$expected_manifest"',
        'tar -tf "$RUNNER_TEMP/artifact.tar" | sed -e \'s#^\\./##\' -e \'/\\/$/d\' -e \'/^$/d\' | LC_ALL=C sort > "$actual_manifest"',
        'diff -u "$expected_manifest" "$actual_manifest"',
    )
    _require_workflow(
        _run_lines(publish_steps[4], "inspect uploaded artifact step") == publish_archive_lines,
        "publish must inspect the upload action's actual artifact.tar",
    )

    environment = _workflow_mapping(deploy["environment"].children, "deploy environment")
    _require_keys(environment, {"name", "url"}, "deploy environment")
    _require_workflow(environment["name"].value == "github-pages", "deploy environment must be github-pages")
    _require_workflow(
        environment["url"].value == "${{ steps.deployment.outputs.page_url }}",
        "deploy environment URL must use the deployment output",
    )
    deploy_steps = _workflow_sequence(deploy["steps"].children, "deploy steps")
    _require_workflow(len(deploy_steps) == 1, "deploy must have exactly one step")
    _require_keys(deploy_steps[0], {"name", "id", "uses"}, "deploy Pages step")
    _require_workflow(deploy_steps[0]["id"].value == "deployment", "deploy step id must be deployment")
    _require_workflow(deploy_steps[0]["uses"].value == "actions/deploy-pages@v5", "deploy must use deploy-pages@v5")

    all_steps = [*validate_steps, *publish_steps, *deploy_steps]
    actions = [step["uses"].value for step in all_steps if "uses" in step]
    _require_workflow(
        actions
        == [
            "actions/checkout@v7",
            "actions/checkout@v7",
            "actions/configure-pages@v6",
            "actions/upload-pages-artifact@v5",
            "actions/deploy-pages@v5",
        ],
        "workflow actions must be exact and unique",
    )
    _require_workflow(not re.search(r"\bpull_request_target\b|\bsecrets(?:\.|\[)", source), "unsafe PR inputs are forbidden")

EXPECTED_IMAGES = {
    "damaged-display.jpg": (1200, 900),
    "result-calibration.jpg": (1200, 675),
    "result-mask.jpg": (1200, 675),
}
EXPECTED_ILLUSTRATIONS = {
    "how-mark-strip.jpg": (1200, 900),
    "how-mask-strip.jpg": (1200, 900),
    "how-use-space.jpg": (1200, 900),
    "privacy-local.jpg": (1200, 900),
    "requirements-platforms.jpg": (1200, 900),
}
MAX_IMAGE_BYTES = 400_000
MAX_TOTAL_IMAGE_BYTES = 1_000_000
MAX_ILLUSTRATION_BYTES = 250_000
MAX_ILLUSTRATION_TOTAL_BYTES = 1_100_000
MAX_ALL_JPEG_BYTES = 1_500_000
SVG_NAMESPACE = "http://www.w3.org/2000/svg"
ALLOWED_SVG_TAGS = frozenset({"svg", "defs", "linearGradient", "stop", "rect", "path"})
LOCAL_CSS_URL = re.compile(r"#[A-Za-z][A-Za-z0-9_-]*")
CSS_URL = re.compile(r"url\((.*?)\)", re.IGNORECASE)
CSS_CUSTOM_PROPERTY = re.compile(r"(--[a-z][a-z0-9-]*)\s*:\s*(#[0-9A-Fa-f]{6})\s*;")
EXPECTED_STYLE_TOKENS = {
    "--paper": "#F5F0E8",
    "--surface": "#FCFAF6",
    "--ink": "#27212B",
    "--muted": "#655D61",
    "--rule": "#CFC5BA",
    "--button": "#B83D31",
    "--button-hover": "#A92C4D",
    "--button-text": "#FFF7E8",
    "--focus": "#D9513B",
}
ALLOWED_CSS_PROPERTIES = frozenset(
    {
        "align-items",
        "aspect-ratio",
        "background",
        "background-color",
        "border",
        "border-bottom",
        "border-left",
        "border-radius",
        "border-top",
        "box-sizing",
        "color",
        "cursor",
        "display",
        "flex",
        "flex-direction",
        "flex-wrap",
        "font-family",
        "font-size",
        "font-weight",
        "gap",
        "grid-column",
        "grid-row",
        "grid-template-columns",
        "height",
        "justify-content",
        "left",
        "letter-spacing",
        "line-height",
        "margin",
        "margin-block",
        "margin-bottom",
        "margin-inline",
        "margin-top",
        "max-width",
        "min-height",
        "min-width",
        "object-fit",
        "outline",
        "outline-color",
        "outline-offset",
        "overflow",
        "overflow-wrap",
        "padding",
        "padding-block",
        "padding-inline",
        "padding-inline-start",
        "position",
        "scroll-behavior",
        "scroll-padding-top",
        "text-align",
        "text-decoration",
        "text-decoration-color",
        "text-decoration-thickness",
        "text-underline-offset",
        "top",
        "transform",
        "transition",
        "vertical-align",
        "width",
        "z-index",
    }
)
APPROVED_CSS_RULE_VOCABULARY = """
base || :root || --paper --surface --ink --muted --rule --button --button-hover --button-text --focus
base || *, *::before, *::after || box-sizing
base || html || scroll-padding-top
base || body || margin color background font-family font-size line-height overflow-wrap
base || main || background
base || main, section, figure, .download-option || min-width
base || img || max-width height display
base || h1, h2, h3, p || margin-top
base || figure || margin
base || a || color
base || a:not(.download-primary) || text-decoration text-underline-offset
base || a:hover || text-decoration-thickness
base || figcaption || margin-top color font-size line-height
base || .site-header, main > *, .site-footer || width max-width margin-inline padding-inline
base || .site-header || min-height display flex-wrap align-items justify-content gap padding-block border-bottom
base || .brand || min-height display align-items gap color font-size font-weight text-decoration
base || .brand img || width height flex
base || .site-header nav || display flex-wrap align-items gap
base || .download-primary || min-height display align-items justify-content padding border-radius color font-weight line-height text-align text-decoration transition
base || .download-windows || background
base || .download-windows:hover || background
base || .download-macos || background
base || .download-primary:hover || transform
base || .download-primary:active || transform
base || .site-header nav a, .site-footer a || display min-height align-items
base || .site-header nav a || color font-weight text-decoration text-decoration-color text-underline-offset
base || .skip-link || position top left z-index min-height padding color background transform
base || .skip-link:focus || transform
base || :focus-visible || outline outline-offset
base || summary:focus-visible || outline-color
base || .hero || display grid-template-columns gap align-items padding-block border-bottom
base || .hero-copy || display flex-direction align-items
base || h1 || max-width margin-bottom font-size line-height letter-spacing
base || h2 || margin-bottom font-size line-height letter-spacing
base || h3 || margin-bottom font-size line-height
base || .hero-explanation || max-width margin-bottom color font-size line-height
base || .hero-copy .download-primary || width max-width margin-bottom
base || .secondary-link || min-height display align-items margin-top
base || .hero-figure || margin-bottom
base || .hero-image, #results img || width border-radius
base || .hero-image || aspect-ratio object-fit
base || main > section || padding-block border-bottom
base || .how-step || display grid-template-columns gap padding-block border-top
base || .how-step:last-child || border-bottom
base || .step-number || grid-row color font-size font-weight
base || .how-step h3, .how-step p || margin-bottom
base || .how-step p || color
base || #results || display grid-template-columns gap
base || #results h2 || margin-bottom
base || #results figure || margin-bottom
base || .download-pair || display grid-template-columns border border-radius overflow
base || .download-option || padding
base || .download-option p || max-width
base || .download-option .download-primary || margin-block
base || .download-fallback || min-height display align-items margin-block vertical-align
base || #privacy p || max-width
base || #requirements ul || max-width margin padding-inline-start border-top
base || #requirements li || padding border-bottom
base || #requirements li::marker || color
base || #faq details || border-top
base || #faq details:last-child || border-bottom
base || #faq summary || min-height padding-block cursor font-weight
base || #faq details p || max-width padding color
base || .site-footer || display flex-wrap align-items gap padding-block font-size
base || .site-footer p || flex margin-bottom color
max700 || .site-header || align-items
max700 || .site-header nav || width
max700 || .site-header nav a || flex justify-content
max700 || .download-option + .download-option || border-top
min701 || .download-pair || grid-template-columns
min701 || .download-option + .download-option || border-left
min900 || .hero || grid-template-columns
min900 || .how-step || grid-template-columns gap
min900 || .how-step p || grid-column
min900 || #results || grid-template-columns align-items
min900 || #results h2 || grid-column
min900 || #results figure:last-of-type || margin-top
min1024 || .site-header, main > *, .site-footer || padding-inline
reduced || html || scroll-behavior
reduced || *, *::before, *::after || transition
""".strip()
PUBLIC_VISIT_NUMBER = re.compile(
    r"^(?:(?:visits?|visitors?|views?)\s*:?\s*\d[\d,. ]*|\d[\d,. ]*\s+(?:visits?|visitors?|views?))$",
    re.IGNORECASE,
)
VOID_ELEMENTS = frozenset({"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"})


@dataclass
class HtmlNode:
    """Represent one parsed HTML element and its descendants."""

    tag: str
    attrs: dict[str, str | None]
    parent: HtmlNode | None = None
    children: list[HtmlNode] = field(default_factory=list)
    data: list[str] = field(default_factory=list)

    def text(self) -> str:
        """Return normalized descendant text."""
        chunks = [*self.data]
        for child in self.children:
            if child.tag not in {"script", "style"}:
                chunks.append(child.text())
        return " ".join(" ".join(chunks).split())


class LandingPageParser(HTMLParser):
    """Parse the landing page into a small semantic inspection model."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.doctype = ""
        self.elements: list[HtmlNode] = []
        self.stack: list[HtmlNode] = []
        self.errors: list[str] = []

    def handle_decl(self, decl: str) -> None:
        """Record the document type declaration."""
        self.doctype = decl.lower()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Record an element and connect it to its parent."""
        normalized_attrs: list[tuple[str, str | None]] = []
        attribute_names: set[str] = set()
        for name, value in attrs:
            normalized_name = name.lower()
            if normalized_name in attribute_names:
                raise ContractError(f"duplicate HTML attribute: {normalized_name}")
            attribute_names.add(normalized_name)
            normalized_attrs.append((normalized_name, value))
        parent = self.stack[-1] if self.stack else None
        node = HtmlNode(tag, dict(normalized_attrs), parent)
        if parent is not None:
            parent.children.append(node)
        self.elements.append(node)
        if tag not in VOID_ELEMENTS:
            self.stack.append(node)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Record an explicitly self-closing HTML void element."""
        if tag.lower() not in VOID_ELEMENTS:
            raise ContractError(f"self-closing HTML tag is not void: {tag.lower()}")
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        """Require properly nested closing tags."""
        if not self.stack or self.stack[-1].tag != tag:
            self.errors.append(f"unexpected closing tag: {tag}")
            return
        self.stack.pop()

    def handle_data(self, data: str) -> None:
        """Record element text for accessible-name and copy checks."""
        if self.stack:
            self.stack[-1].data.append(data)

    def nodes(self, tag: str) -> list[HtmlNode]:
        """Return every node with the requested tag."""
        return [node for node in self.elements if node.tag == tag]

    def by_id(self, identifier: str) -> list[HtmlNode]:
        """Return every node with the requested ID."""
        return [node for node in self.elements if node.attrs.get("id") == identifier]

    @property
    def landmarks(self) -> dict[str, list[HtmlNode]]:
        """Return the semantic page landmarks grouped by tag."""
        return {tag: self.nodes(tag) for tag in ("header", "nav", "main", "footer")}

    @property
    def headings(self) -> list[HtmlNode]:
        """Return all HTML headings in source order."""
        return [node for node in self.elements if re.fullmatch(r"h[1-6]", node.tag)]

    @property
    def ids(self) -> list[str]:
        """Return all element IDs in source order."""
        return [identifier for node in self.elements if (identifier := node.attrs.get("id"))]

    @property
    def links(self) -> list[HtmlNode]:
        """Return all anchors in source order."""
        return self.nodes("a")

    @property
    def images(self) -> list[HtmlNode]:
        """Return all images in source order."""
        return self.nodes("img")

    @property
    def scripts(self) -> list[HtmlNode]:
        """Return all scripts in source order."""
        return self.nodes("script")

    @property
    def details_summaries(self) -> list[tuple[HtmlNode, list[HtmlNode]]]:
        """Return native disclosure elements with their direct summaries."""
        return [
            (detail, [child for child in detail.children if child.tag == "summary"])
            for detail in self.nodes("details")
        ]

    @property
    def class_tokens(self) -> set[str]:
        """Return every token from class attributes."""
        return {
            token
            for node in self.elements
            for token in (node.attrs.get("class") or "").split()
        }

    @property
    def visible_text_nodes(self) -> list[str]:
        """Return normalized non-script and non-style text nodes."""
        return [
            normalized
            for node in self.elements
            if node.tag not in {"script", "style"}
            for value in node.data
            if (normalized := " ".join(value.split()))
        ]


def parse_landing_page(path: Path = ROOT / "site" / "index.html") -> LandingPageParser:
    """Parse one landing-page file and require balanced HTML elements."""
    parser = LandingPageParser()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    if parser.stack:
        parser.errors.append(f"unclosed tag: {parser.stack[-1].tag}")
    if parser.errors:
        raise ContractError("; ".join(parser.errors))
    return parser


def _descendant_nodes(root: HtmlNode) -> tuple[HtmlNode, ...]:
    """Return all descendants of one parsed HTML node."""
    descendants: list[HtmlNode] = []
    for child in root.children:
        descendants.append(child)
        descendants.extend(_descendant_nodes(child))
    return tuple(descendants)


def _landing_page_readme_copy() -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return substantive page blocks and FAQ summaries relevant to README duplication."""
    page = parse_landing_page()
    privacy_nodes = _descendant_nodes(page.by_id("privacy")[0])
    faq_nodes = _descendant_nodes(page.by_id("faq")[0])
    download_nodes = _descendant_nodes(page.by_id("downloads")[0])
    download_articles = [
        node
        for node in download_nodes
        if node.tag == "article" and "download-option" in (node.attrs.get("class") or "").split()
    ]
    block_nodes = [node for node in privacy_nodes + faq_nodes if node.tag == "p"]
    block_nodes.extend(
        node
        for article in download_articles
        for node in _descendant_nodes(article)
        if node.tag == "p"
    )
    blocks = tuple(
        dict.fromkeys(
            text
            for node in block_nodes
            if len(text := node.text()) >= README_COPY_BLOCK_MIN_LENGTH
        )
    )
    summaries = tuple(node.text() for node in faq_nodes if node.tag == "summary" and node.text())
    return blocks, summaries


def validate_landing_page(path: Path) -> None:
    """Validate mutation-sensitive landing-page semantics."""
    page = parse_landing_page(path)
    _validate_hero(page)
    _validate_marketing_exclusions(page)
    _validate_required_visibility(page)
    _validate_label_references(page)
    _validate_nonempty_aria_labels(page)
    _validate_public_counter(page)
    _validate_sections(page)
    _validate_references(page)
    _validate_script(page)
    _validate_faq(page)
    _validate_downloads(page)
    _validate_image_alts(page)


def _validate_hero(page: LandingPageParser) -> None:
    """Require the direct reviewed hero opening."""
    hero_copy = [node for node in page.elements if "hero-copy" in (node.attrs.get("class") or "").split()]
    if len(hero_copy) != 1:
        raise ContractError("hero copy must appear exactly once")
    substantive = [child for child in hero_copy[0].children if child.text()]
    if not substantive or substantive[0].tag != "h1":
        raise ContractError("hero heading must be first visible content")
    forbidden = {"eyebrow", "kicker", "preheading"}
    if page.class_tokens & forbidden:
        raise ContractError("hero heading must be first without promotional preheading")


def _validate_marketing_exclusions(page: LandingPageParser) -> None:
    """Reject standalone claims and generic proof-region patterns."""
    standalone_claims = {"Free and MIT licensed", "Runs locally", "No app telemetry"}
    if standalone_claims.intersection(page.visible_text_nodes):
        raise ContractError("standalone trust claim is forbidden")
    forbidden = ("trust-strip", "statistic-strip", "badge-cloud", "testimonial", "social-proof")
    names = page.class_tokens | set(page.ids)
    if any(term in name.lower() for name in names for term in forbidden):
        raise ContractError("generic marketing proof regions are forbidden")


def _validate_required_visibility(page: LandingPageParser) -> None:
    """Keep the reviewed header, content, and footer exposed to assistive technology."""
    scopes = page.nodes("header") + page.nodes("main") + page.nodes("footer")
    required_tags = {
        "a",
        "article",
        "details",
        "figcaption",
        "figure",
        "footer",
        "header",
        "img",
        "li",
        "main",
        "nav",
        "p",
        "section",
        "summary",
    }
    required_classes = {
        "download-option",
        "download-pair",
        "hero",
        "hero-copy",
        "hero-figure",
        "how-step",
        "step-number",
    }
    for node in page.elements:
        is_heading = re.fullmatch(r"h[1-6]", node.tag) is not None
        classes = set((node.attrs.get("class") or "").split())
        is_required = node.tag in required_tags or is_heading or bool(classes & required_classes)
        if is_required and _is_within_any(node, scopes) and _is_hidden(node):
            raise ContractError("required content must remain visible")


def _is_within_any(node: HtmlNode, ancestors: list[HtmlNode]) -> bool:
    """Return whether a node is or descends from one of the supplied elements."""
    current: HtmlNode | None = node
    while current is not None:
        if any(current is ancestor for ancestor in ancestors):
            return True
        current = current.parent
    return False


def _is_hidden(node: HtmlNode) -> bool:
    """Return whether HTML or ARIA hides a node through its ancestor chain."""
    current: HtmlNode | None = node
    while current is not None:
        aria_hidden = (current.attrs.get("aria-hidden") or "").strip().lower()
        if "hidden" in current.attrs or "inert" in current.attrs or aria_hidden == "true":
            return True
        current = current.parent
    return False


def _name_from_contents(node: HtmlNode, include_hidden: bool = False) -> str:
    """Return normalized text and descendant image alternatives for a name."""
    if not include_hidden and _is_hidden(node):
        return ""
    if node.tag == "img":
        return (node.attrs.get("alt") or "").strip()
    chunks = [*node.data]
    chunks.extend(
        _name_from_contents(child, include_hidden)
        for child in node.children
        if child.tag not in {"script", "style"}
    )
    return " ".join(" ".join(chunks).split())


def _validate_label_references(page: LandingPageParser) -> None:
    """Require every ARIA labelled-by token to resolve to one named element."""
    for node in page.elements:
        if "aria-labelledby" not in node.attrs:
            continue
        _labelledby_text(page, node)


def _labelledby_text(page: LandingPageParser, node: HtmlNode) -> str:
    """Resolve one element's labelled-by references to visible normalized text."""
    tokens = (node.attrs.get("aria-labelledby") or "").split()
    labels: list[str] = []
    for token in tokens:
        targets = page.by_id(token)
        if len(targets) != 1:
            raise ContractError("aria-labelledby target must resolve to one named element")
        label = _name_from_contents(targets[0], include_hidden=True).strip()
        if not label:
            raise ContractError("aria-labelledby target must resolve to one named element")
        labels.append(label)
    if not labels:
        raise ContractError("aria-labelledby target must resolve to one named element")
    return " ".join(labels)


def _validate_nonempty_aria_labels(page: LandingPageParser) -> None:
    """Reject blank labels where this page requires an explicit landmark name."""
    for node in page.elements:
        has_blank_label = (
            "aria-label" in node.attrs
            and not (node.attrs.get("aria-label") or "").strip()
        )
        if has_blank_label and node.tag != "a":
            raise ContractError("accessible name attribute must be non-empty")


def _validate_public_counter(page: LandingPageParser) -> None:
    """Reject known public visit-counter identifiers and data attributes."""
    prefixes = ("gc-number", "public-counter", "visit-counter", "visitor-counter")
    data_attributes = {
        "data-public-counter",
        "data-visit-counter",
        "data-visitor-counter",
        "data-gc-number",
    }
    for node in page.elements:
        identifiers = [(node.attrs.get("id") or "").lower()]
        identifiers.extend(token.lower() for token in (node.attrs.get("class") or "").split())
        if any(_is_counter_identifier(identifier, prefixes) for identifier in identifiers):
            raise ContractError("public visit counter markup is forbidden")
        attribute_names = {name.lower() for name in node.attrs}
        has_counter_data = bool(attribute_names & data_attributes)
        has_goatcounter_data = node.tag != "script" and any(
            name.startswith("data-goatcounter") for name in attribute_names
        )
        if has_counter_data or has_goatcounter_data:
            raise ContractError("public visit counter markup is forbidden")
    rendered_text = [node.text() for node in page.elements if node.tag not in {"script", "style"}]
    if any(PUBLIC_VISIT_NUMBER.fullmatch(text) for text in rendered_text):
        raise ContractError("rendered visit number is forbidden")


def _is_counter_identifier(identifier: str, prefixes: tuple[str, ...]) -> bool:
    """Return whether an ID or class token denotes a public counter."""
    return any(
        identifier == prefix or identifier.startswith((f"{prefix}-", f"{prefix}_"))
        for prefix in prefixes
    )


def _validate_script(page: LandingPageParser) -> None:
    """Require only the exact privacy-reviewed GoatCounter script."""
    if len(page.scripts) != 1:
        raise ContractError("landing page must contain exactly one script")
    expected = {
        "data-goatcounter": "https://farihmhmd.goatcounter.com/count",
        "async": None,
        "src": "https://gc.zgo.at/count.js",
    }
    if page.scripts[0].attrs != expected or page.scripts[0].text():
        raise ContractError("GoatCounter script attributes must match the privacy contract")


def _validate_references(page: LandingPageParser) -> None:
    """Require contained local references and explicit HTTPS external URLs."""
    references = [
        reference
        for node in page.elements
        for attribute in ("href", "src")
        if (reference := node.attrs.get(attribute))
    ]
    if any(reference.startswith("//") for reference in references):
        raise ContractError("protocol-relative URL is forbidden")
    for reference in references:
        parsed = urlsplit(reference)
        if parsed.scheme and parsed.scheme != "https":
            raise ContractError("external references must use HTTPS")
        if parsed.hostname in {"localhost", "127.0.0.1", "::1"}:
            raise ContractError("localhost references are forbidden")
        if not parsed.scheme and (parsed.netloc or parsed.path.startswith("/") or ".." in Path(parsed.path).parts):
            raise ContractError("internal reference escapes the site directory")
        if not parsed.scheme and parsed.fragment and parsed.fragment not in page.ids:
            raise ContractError("internal anchor does not resolve")
    if any(not _accessible_name(page, link) for link in page.links):
        raise ContractError("link accessible names must be descriptive")


def _accessible_name(page: LandingPageParser, node: HtmlNode) -> str:
    """Return the first available explicit or content-derived name."""
    aria_label = (node.attrs.get("aria-label") or "").strip()
    if aria_label:
        return aria_label
    if "aria-labelledby" in node.attrs:
        return _labelledby_text(page, node)
    return _name_from_contents(node)


def _validate_sections(page: LandingPageParser) -> None:
    """Require the six unique content sections in reviewed order."""
    section_ids = [node.attrs.get("id") for node in page.nodes("section") if node.attrs.get("id")]
    if len(section_ids) != len(set(section_ids)):
        raise ContractError("duplicate section ID is forbidden")
    expected = ["how", "results", "downloads", "privacy", "requirements", "faq"]
    if section_ids != expected:
        raise ContractError("section IDs do not match the approved order")


def _validate_faq(page: LandingPageParser) -> None:
    """Require four ordered native disclosures with answers."""
    faq_sections = page.by_id("faq")
    if len(faq_sections) != 1:
        raise ContractError("FAQ section must appear exactly once")
    faq_details = [node for node in faq_sections[0].children if node.tag == "details"]
    relationships = [
        (detail, summaries)
        for detail, summaries in page.details_summaries
        if any(detail is candidate for candidate in faq_details)
    ]
    questions = [summaries[0].text() if summaries else "" for _, summaries in relationships]
    expected = [
        "Does ScreenFix repair the damaged panel?",
        "Which windows may remain unchanged?",
        "Why does my operating system warn about ScreenFix?",
        "When does ScreenFix need macOS Accessibility permission?",
    ]
    if len(relationships) != 4 or any(not question for question in questions):
        raise ContractError("FAQ summary must be non-empty in each of four details")
    for detail, summaries in relationships:
        if len(summaries) != 1 or detail.children[0] is not summaries[0]:
            raise ContractError("FAQ summary must be non-empty and first in details")
        if not any(child.text() for child in detail.children[1:]):
            raise ContractError("FAQ answer must be non-empty")
    if questions != expected:
        raise ContractError("FAQ order does not match the approved contract")


def _validate_downloads(page: LandingPageParser) -> None:
    """Require stable native release filenames and placement."""
    windows_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe"
    macos_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip"
    fallback_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe"
    primary = [
        node.attrs.get("href")
        for node in page.nodes("a")
        if "download-primary" in (node.attrs.get("class") or "").split()
    ]
    fallback = [
        node.attrs.get("href")
        for node in page.nodes("a")
        if "download-fallback" in (node.attrs.get("class") or "").split()
    ]
    if primary != [windows_url, macos_url, windows_url, macos_url] or fallback != [fallback_url]:
        raise ContractError("native download filename does not match the release contract")


def _validate_image_alts(page: LandingPageParser) -> None:
    """Require alt attributes and descriptions for product photographs."""
    for image in page.images:
        if "alt" not in image.attrs:
            raise ContractError("image alt attribute must describe each product photograph")
        if (image.attrs.get("alt") or "").strip():
            continue
        parent_classes = (image.parent.attrs.get("class") or "").split() if image.parent else []
        is_brand_icon = image.attrs.get("src") == "assets/screenfix-icon.svg" and "brand" in parent_classes
        if not is_brand_icon:
            raise ContractError("empty image alt is reserved for the brand icon")


class ContractError(AssertionError):
    """Reports a stable landing-page contract failure."""


@dataclass(frozen=True)
class CssNode:
    """Describe the small element context needed by the CSS contract."""

    tag: str
    classes: frozenset[str] = frozenset()
    identifier: str = ""
    states: frozenset[str] = frozenset()
    parent: CssNode | None = None


@dataclass(frozen=True)
class CssRule:
    """Represent one parsed rule with width applicability and source order."""

    selectors: tuple[str, ...]
    declarations: dict[str, str]
    minimum_width: float
    maximum_width: float
    source_order: int
    reduced_motion: bool


def _parse_css_declarations(body: str) -> dict[str, str]:
    """Consume every byte in one declaration list or fail closed."""
    declarations: dict[str, str] = {}
    cursor = 0
    while cursor < len(body):
        while cursor < len(body) and body[cursor].isspace():
            cursor += 1
        if cursor == len(body):
            break
        name_match = re.match(r"(?:--)?[A-Za-z][A-Za-z0-9-]*", body[cursor:])
        if name_match is None:
            raise ContractError("CSS declaration contains unparsed residue")
        property_name = name_match.group().lower()
        cursor += len(name_match.group())
        while cursor < len(body) and body[cursor].isspace():
            cursor += 1
        if cursor == len(body) or body[cursor] != ":":
            raise ContractError("CSS declaration requires a property and value")
        cursor += 1
        value_start = cursor
        quote = ""
        parentheses = 0
        while cursor < len(body):
            character = body[cursor]
            if quote:
                if character == "\\":
                    cursor += 2
                    continue
                if character == quote:
                    quote = ""
            elif character in {'"', "'"}:
                quote = character
            elif character == "(":
                parentheses += 1
            elif character == ")":
                if parentheses == 0:
                    raise ContractError("CSS declaration has unbalanced parentheses")
                parentheses -= 1
            elif character in "{}":
                raise ContractError("CSS declaration contains an unexpected block")
            elif character == ";" and parentheses == 0:
                break
            cursor += 1
        if quote or parentheses:
            raise ContractError("CSS declaration has an unbalanced value")
        value = body[value_start:cursor].strip()
        if not value:
            raise ContractError("CSS declaration requires a non-empty value")
        if property_name in declarations:
            raise ContractError(f"CSS declaration repeats property: {property_name}")
        declarations[property_name] = value
        if cursor < len(body):
            cursor += 1
    return declarations


def parse_css_rules(styles: str) -> list[CssRule]:
    """Parse the fixed stylesheet, rejecting unconsumed declaration syntax."""
    source = re.sub(r"/\*.*?\*/", "", styles, flags=re.DOTALL)
    rules: list[CssRule] = []
    source_order = 0

    def walk(
        fragment: str,
        minimum_width: float,
        maximum_width: float,
        reduced_motion: bool,
        media_context: str,
    ) -> None:
        nonlocal source_order
        cursor = 0
        while True:
            opening = fragment.find("{", cursor)
            if opening < 0:
                if fragment[cursor:].strip():
                    raise ContractError("CSS rule contains unparsed residue")
                return
            prelude = fragment[cursor:opening].strip()
            depth = 1
            closing = opening + 1
            while closing < len(fragment) and depth:
                if fragment[closing] == "{":
                    depth += 1
                elif fragment[closing] == "}":
                    depth -= 1
                closing += 1
            if depth:
                raise ContractError("CSS rule is unbalanced")
            body = fragment[opening + 1 : closing - 1]
            if prelude.startswith("@media"):
                if media_context != "base":
                    raise ContractError("nested CSS media context is unreviewed")
                condition = prelude.removeprefix("@media").strip()
                if "prefers-reduced-motion" in condition:
                    walk(body, minimum_width, maximum_width, True, condition)
                else:
                    minimum = re.search(r"min-width\s*:\s*([0-9.]+)px", condition)
                    maximum = re.search(r"max-width\s*:\s*([0-9.]+)px", condition)
                    nested_minimum = max(minimum_width, float(minimum.group(1)) if minimum else 0)
                    nested_maximum = min(maximum_width, float(maximum.group(1)) if maximum else float("inf"))
                    walk(body, nested_minimum, nested_maximum, reduced_motion, condition)
            elif prelude.startswith("@"):
                raise ContractError("unsupported CSS at-rule")
            else:
                declarations = _parse_css_declarations(body)
                selectors = tuple(selector.strip() for selector in prelude.split(",") if selector.strip())
                if not selectors or not declarations:
                    raise ContractError("CSS rule requires selectors and declarations")
                rules.append(
                    CssRule(
                        selectors,
                        declarations,
                        minimum_width,
                        maximum_width,
                        source_order,
                        reduced_motion,
                    )
                )
                source_order += 1
            cursor = closing

    walk(source, 0, float("inf"), False, "base")
    return rules


def _normalized_selector_group(selectors: tuple[str, ...] | str) -> tuple[str, ...]:
    """Return one order-independent selector-group key with stable spacing."""
    raw_selectors = selectors.split(",") if isinstance(selectors, str) else selectors
    normalized = []
    for selector in raw_selectors:
        spaced = re.sub(r"\s*([>+~])\s*", r" \1 ", selector.strip())
        normalized.append(re.sub(r"\s+", " ", spaced))
    return tuple(sorted(normalized))


def _rule_media_context(rule: CssRule) -> str:
    """Map one parsed rule to the exact reviewed media context."""
    if rule.reduced_motion:
        return "reduced"
    bounds = rule.minimum_width, rule.maximum_width
    contexts = {
        (0, float("inf")): "base",
        (0, 700): "max700",
        (701, float("inf")): "min701",
        (900, float("inf")): "min900",
        (1024, float("inf")): "min1024",
    }
    if bounds not in contexts:
        raise ContractError("CSS rule uses an unreviewed media context")
    return contexts[bounds]


def _approved_rule_vocabulary() -> dict[tuple[str, tuple[str, ...]], frozenset[str]]:
    """Parse the explicit selector, media, and property vocabulary fixture."""
    approved: dict[tuple[str, tuple[str, ...]], frozenset[str]] = {}
    for line in APPROVED_CSS_RULE_VOCABULARY.splitlines():
        context, selector_source, property_source = (part.strip() for part in line.split("||"))
        key = context, _normalized_selector_group(selector_source)
        if key in approved:
            raise ContractError("approved CSS vocabulary contains a duplicate selector")
        approved[key] = frozenset(property_source.split())
    return approved


def _validate_rule_vocabulary_contract(styles: str) -> None:
    """Fail closed on unreviewed, duplicate, or repurposed selector blocks."""
    approved = _approved_rule_vocabulary()
    observed: set[tuple[str, tuple[str, ...]]] = set()
    for rule in parse_css_rules(styles):
        key = _rule_media_context(rule), _normalized_selector_group(rule.selectors)
        if key in observed:
            raise ContractError("CSS rule repeats a reviewed selector in one media context")
        observed.add(key)
        if key not in approved:
            raise ContractError("CSS rule uses an unreviewed selector or media context")
        if frozenset(rule.declarations) != approved[key]:
            raise ContractError("CSS rule uses unreviewed properties for its selector")
    if observed != set(approved):
        raise ContractError("CSS rule vocabulary is incomplete")


def _selector_parts(selector: str) -> tuple[list[str], list[str]]:
    """Split the supported descendant and child selectors into compounds."""
    if "+" in selector or "~" in selector:
        return [], []
    segments = re.sub(r"\s*>\s*", ">", selector.strip()).split(">")
    compounds: list[str] = []
    combinators: list[str] = []
    for segment_index, segment in enumerate(segments):
        descendants = segment.split()
        for descendant_index, compound in enumerate(descendants):
            if compounds:
                is_child = segment_index > 0 and descendant_index == 0
                combinators.append(">" if is_child else " ")
            compounds.append(compound)
    return compounds, combinators


def _compound_matches(compound: str, node: CssNode) -> bool:
    """Match one limited type, ID, class, state, and :not compound."""
    for excluded in re.findall(r":not\(([^)]+)\)", compound):
        if _compound_matches(excluded, node):
            return False
    normalized = re.sub(r":not\([^)]+\)", "", compound)
    if "::" in normalized:
        return False
    identifiers = re.findall(r"#([\w-]+)", normalized)
    if identifiers and any(identifier != node.identifier for identifier in identifiers):
        return False
    if any(name not in node.classes for name in re.findall(r"\.([\w-]+)", normalized)):
        return False
    states = re.findall(r"(?<!:):([\w-]+)", normalized)
    if any(state not in node.states for state in states):
        return False
    type_name = re.match(r"^[A-Za-z][\w-]*|^\*", normalized)
    return type_name is None or type_name.group() == "*" or type_name.group().lower() == node.tag.lower()


def selector_matches(selector: str, node: CssNode) -> bool:
    """Return whether a supported selector matches a described element tree."""
    compounds, combinators = _selector_parts(selector)
    if not compounds or not _compound_matches(compounds[-1], node):
        return False
    current = node
    for index in range(len(compounds) - 2, -1, -1):
        combinator = combinators[index]
        candidate = current.parent
        if combinator == ">":
            if candidate is None or not _compound_matches(compounds[index], candidate):
                return False
        else:
            while candidate is not None and not _compound_matches(compounds[index], candidate):
                candidate = candidate.parent
            if candidate is None:
                return False
        current = candidate
    return True


def selector_specificity(selector: str) -> tuple[int, int, int]:
    """Return CSS ID, class/state, and type specificity for supported selectors."""
    identifiers = len(re.findall(r"#[\w-]+", selector))
    classes = len(re.findall(r"\.[\w-]+", selector))
    states = len(
        [
            state
            for state in re.findall(r"(?<!:):([\w-]+)", selector)
            if state != "not"
        ]
    )
    types = sum(
        1
        for compound in re.split(r"\s+|>", re.sub(r":not\([^)]+\)", "", selector))
        if re.match(r"^[A-Za-z][\w-]*", compound)
    )
    return identifiers, classes + states, types


def _cascade_property_name(property_name: str) -> str:
    """Normalize the color shorthands modeled by this fixed stylesheet."""
    if property_name in {"background", "background-color"}:
        return "background-color"
    if property_name in {"outline", "outline-color"}:
        return "outline-color"
    return property_name


def effective_declarations(styles: str, node: CssNode, viewport: float) -> dict[str, str]:
    """Resolve supported declarations by applicability, specificity, and order."""
    winners: dict[str, tuple[tuple[int, int, int], int, str]] = {}
    for rule in parse_css_rules(styles):
        if rule.reduced_motion or not rule.minimum_width <= viewport <= rule.maximum_width:
            continue
        matching = [selector for selector in rule.selectors if selector_matches(selector, node)]
        if not matching:
            continue
        specificity = max(selector_specificity(selector) for selector in matching)
        for property_name, value in rule.declarations.items():
            cascade_name = _cascade_property_name(property_name)
            previous = winners.get(cascade_name)
            if previous is None or (specificity, rule.source_order) >= previous[:2]:
                winners[cascade_name] = specificity, rule.source_order, value
    return {property_name: winner[2] for property_name, winner in winners.items()}


def parse_style_tokens(styles: str) -> dict[str, str]:
    """Return unique literal hexadecimal custom properties from CSS source."""
    declarations = CSS_CUSTOM_PROPERTY.findall(styles)
    names = [name for name, _ in declarations]
    if len(names) != len(set(names)):
        raise ContractError("style color tokens must be declared once")
    return dict(declarations)


def _validate_custom_property_contract(styles: str) -> None:
    """Allow exactly the reviewed literal tokens in one global :root rule."""
    rules = parse_css_rules(styles)
    root_rules = [rule for rule in rules if rule.selectors == (":root",)]
    custom_rules = [
        rule
        for rule in rules
        if any(name.startswith("--") for name in rule.declarations)
    ]
    if len(root_rules) != 1 or custom_rules != root_rules:
        raise ContractError("custom properties must be declared only in one :root rule")
    root_tokens = {
        name: value
        for name, value in root_rules[0].declarations.items()
        if name.startswith("--")
    }
    source = re.sub(r"/\*.*?\*/", "", styles, flags=re.DOTALL)
    declarations = re.findall(r"(--[\w-]+)\s*:\s*([^;{}]+);", source)
    if len(declarations) != len(EXPECTED_STYLE_TOKENS) or root_tokens != EXPECTED_STYLE_TOKENS:
        raise ContractError("style color tokens must match the reviewed palette")


def relative_luminance(color: str) -> float:
    """Return WCAG relative luminance for a six-digit hexadecimal color."""
    channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        channel / 12.92
        if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    """Return the WCAG contrast ratio between two hexadecimal colors."""
    lighter, darker = sorted(
        (relative_luminance(first), relative_luminance(second)),
        reverse=True,
    )
    return (lighter + 0.05) / (darker + 0.05)


def _validate_color_contract(styles: str) -> None:
    """Require the reviewed palette, its uses, and measured contrast floors."""
    _validate_custom_property_contract(styles)
    tokens = parse_style_tokens(styles)
    if any(tokens.get(name) != value for name, value in EXPECTED_STYLE_TOKENS.items()):
        raise ContractError("style color tokens must match the reviewed palette")
    if any(f"var({name})" not in styles for name in EXPECTED_STYLE_TOKENS):
        raise ContractError("style color tokens must be used")
    _validate_contrast_contract(tokens)


def _validate_contrast_contract(tokens: dict[str, str]) -> None:
    """Require measured WCAG floors for every approved color pairing."""
    pairs = {
        "Windows button": ("--button", "--button-text", 5.25),
        "Windows hover": ("--button-hover", "--button-text", 6.25),
        "macOS button": ("--ink", "--button-text", 14.7),
    }
    for foreground in ("--ink", "--muted", "--button-hover"):
        for background in ("--paper", "--surface"):
            pairs[f"{foreground} on {background}"] = (foreground, background, 4.5)
    for background in ("--paper", "--surface"):
        pairs[f"focus on {background}"] = ("--focus", background, 3.0)
    for label, (foreground, background, minimum) in pairs.items():
        measured = contrast_ratio(tokens[foreground], tokens[background])
        if measured < minimum:
            raise ContractError(f"{label} contrast must be at least {minimum}:1")


def _resolve_css_color(value: str, tokens: dict[str, str]) -> str:
    """Resolve one color component from a supported longhand or shorthand."""
    variables = re.findall(r"var\((--[\w-]+)\)", value)
    literals = re.findall(r"#[0-9A-Fa-f]{6}", value)
    if len(variables) + len(literals) != 1:
        raise ContractError("effective color must resolve to one literal reviewed color")
    if variables:
        if variables[0] not in tokens:
            raise ContractError("effective color references an unknown token")
        return tokens[variables[0]]
    return literals[0]


def _validate_effective_color_contract(styles: str) -> None:
    """Resolve the reviewed page colors after the supported cascade."""
    tokens = parse_style_tokens(styles)
    body = CssNode("body")
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    downloads = CssNode("section", identifier="downloads", parent=main)
    pair = CssNode("div", frozenset({"download-pair"}), parent=downloads)
    windows_option = CssNode(
        "article",
        frozenset({"download-option", "download-option-windows"}),
        parent=pair,
    )
    macos_option = CssNode(
        "article",
        frozenset({"download-option", "download-option-macos"}),
        parent=pair,
    )
    windows = frozenset({"download-primary", "download-windows"})
    macos = frozenset({"download-primary", "download-macos"})
    cases = [("body", body, "--ink", "--paper", 4.5)]
    for context, windows_parent, macos_parent in (
        ("hero", hero_copy, hero_copy),
        ("downloads", windows_option, macos_option),
    ):
        cases.extend(
            [
                (
                    f"{context} Windows default",
                    CssNode("a", windows, parent=windows_parent),
                    "--button-text",
                    "--button",
                    5.25,
                ),
                (
                    f"{context} Windows hover",
                    CssNode("a", windows, states=frozenset({"hover"}), parent=windows_parent),
                    "--button-text",
                    "--button-hover",
                    6.25,
                ),
                (
                    f"{context} macOS default",
                    CssNode("a", macos, parent=macos_parent),
                    "--button-text",
                    "--ink",
                    14.7,
                ),
                (
                    f"{context} macOS hover",
                    CssNode("a", macos, states=frozenset({"hover"}), parent=macos_parent),
                    "--button-text",
                    "--ink",
                    14.7,
                ),
            ]
        )
    fallback_parent = CssNode("p", parent=windows_option)
    links = {
        "paper link": (CssNode("a", parent=CssNode("footer", frozenset({"site-footer"}), parent=body)), "--paper"),
        "surface hero link": (CssNode("a", frozenset({"secondary-link"}), parent=hero_copy), "--surface"),
        "surface fallback link": (CssNode("a", frozenset({"download-fallback"}), parent=fallback_parent), "--surface"),
    }
    focus_nodes = (
        CssNode("a", frozenset({"secondary-link"}), states=frozenset({"focus-visible"}), parent=hero_copy),
        CssNode("a", frozenset({"download-fallback"}), states=frozenset({"focus-visible"}), parent=fallback_parent),
        CssNode("a", windows, states=frozenset({"focus-visible"}), parent=windows_option),
        CssNode(
            "summary",
            states=frozenset({"focus-visible"}),
            parent=CssNode("details", parent=CssNode("section", identifier="faq", parent=main)),
        ),
    )
    for viewport in (375, 768, 1024, 1440):
        main_styles = effective_declarations(styles, main, viewport)
        main_background = _resolve_css_color(main_styles.get("background-color", ""), tokens)
        if main_background.upper() != tokens["--surface"]:
            raise ContractError("effective color contract for main background requires --surface")
        for label, node, foreground_token, background_token, minimum in cases:
            declarations = effective_declarations(styles, node, viewport)
            foreground = _resolve_css_color(declarations.get("color", ""), tokens)
            background = _resolve_css_color(declarations.get("background-color", ""), tokens)
            expected = tokens[foreground_token], tokens[background_token]
            if (foreground.upper(), background.upper()) != expected:
                raise ContractError(f"effective color contract for {label} contrast requires reviewed tokens")
            if contrast_ratio(foreground, background) < minimum:
                raise ContractError(f"effective color contract for {label} contrast requires {minimum}:1")
        for label, (node, background_token) in links.items():
            declarations = effective_declarations(styles, node, viewport)
            foreground = _resolve_css_color(declarations.get("color", ""), tokens)
            background = tokens[background_token]
            if foreground.upper() != tokens["--button-hover"] or contrast_ratio(foreground, background) < 4.5:
                raise ContractError(f"effective color contract for {label} contrast requires --button-hover")
        for focus in focus_nodes:
            focus_styles = effective_declarations(styles, focus, viewport)
            focus_color = _resolve_css_color(focus_styles.get("outline-color", ""), tokens)
            if focus_color.upper() != tokens["--focus"]:
                raise ContractError("effective color contract for focus color requires --focus")
            for background_token in ("--paper", "--surface"):
                if contrast_ratio(focus_color, tokens[background_token]) < 3:
                    raise ContractError("effective color contract for focus contrast requires 3:1")


def _inherited_effective_value(
    styles: str,
    node: CssNode,
    viewport: float,
    property_name: str,
) -> str:
    """Resolve one inherited property through the modeled ancestor chain."""
    current: CssNode | None = node
    while current is not None:
        declarations = effective_declarations(styles, current, viewport)
        if property_name in declarations:
            return declarations[property_name]
        current = current.parent
    raise ContractError(f"effective inherited {property_name} is missing")


def _validate_text_contrast_contract(styles: str) -> None:
    """Validate every explicit text color in its reviewed page context."""
    tokens = parse_style_tokens(styles)
    contexts = {
        _normalized_selector_group("body"): ("--ink", ("--paper", "--surface")),
        _normalized_selector_group("a"): ("--button-hover", ("--paper", "--surface")),
        _normalized_selector_group("figcaption"): ("--muted", ("--surface",)),
        _normalized_selector_group(".brand"): ("--ink", ("--paper",)),
        _normalized_selector_group(".download-primary"): (
            "--button-text",
            ("--button", "--button-hover", "--ink"),
        ),
        _normalized_selector_group(".site-header nav a"): ("--ink", ("--paper",)),
        _normalized_selector_group(".skip-link"): ("--button-text", ("--ink",)),
        _normalized_selector_group(".hero-explanation"): ("--muted", ("--surface",)),
        _normalized_selector_group(".step-number"): ("--button-hover", ("--surface",)),
        _normalized_selector_group(".how-step p"): ("--muted", ("--surface",)),
        _normalized_selector_group("#requirements li::marker"): (
            "--button-hover",
            ("--surface",),
        ),
        _normalized_selector_group("#faq details p"): ("--muted", ("--surface",)),
        _normalized_selector_group(".site-footer p"): ("--muted", ("--paper",)),
    }
    color_rules = [rule for rule in parse_css_rules(styles) if "color" in rule.declarations]
    if len(color_rules) != len(contexts):
        raise ContractError("every explicit text color must have one reviewed context")
    for rule in color_rules:
        selector_key = _normalized_selector_group(rule.selectors)
        if selector_key not in contexts:
            raise ContractError("explicit text color uses an unknown page context")
        foreground_token, background_tokens = contexts[selector_key]
        foreground = _resolve_css_color(rule.declarations["color"], tokens)
        if foreground.upper() != tokens[foreground_token]:
            raise ContractError("explicit text color must use its reviewed foreground token")
        for background_token in background_tokens:
            if contrast_ratio(foreground, tokens[background_token]) < 4.5:
                raise ContractError("explicit text color must retain 4.5:1 contrast")

    body = CssNode("body")
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    headings = (
        CssNode("h1", parent=hero_copy),
        CssNode("h2", parent=CssNode("section", identifier="results", parent=main)),
        CssNode("h3", parent=CssNode("div", frozenset({"how-step"}), parent=main)),
    )
    skip_link = CssNode("a", frozenset({"skip-link"}), parent=body)
    for viewport in (375, 768, 1024, 1440):
        for heading in headings:
            color = _resolve_css_color(
                _inherited_effective_value(styles, heading, viewport, "color"),
                tokens,
            )
            if color.upper() != tokens["--ink"] or contrast_ratio(color, tokens["--surface"]) < 4.5:
                raise ContractError("headings must inherit reviewed ink on the page surface")
        skip_styles = effective_declarations(styles, skip_link, viewport)
        skip_foreground = _resolve_css_color(skip_styles.get("color", ""), tokens)
        skip_background = _resolve_css_color(skip_styles.get("background-color", ""), tokens)
        if (
            skip_foreground.upper() != tokens["--button-text"]
            or skip_background.upper() != tokens["--ink"]
            or contrast_ratio(skip_foreground, skip_background) < 4.5
        ):
            raise ContractError("skip link must keep button text on the ink background")


def _css_block(styles: str, selector: str) -> str:
    """Return declarations for one literal selector block."""
    pieces = re.split(r"\s+", selector.strip())
    selector_pattern = r"\s*".join(re.escape(piece) for piece in pieces)
    match = re.search(rf"(?:^|\}})\s*{selector_pattern}\s*\{{([^{{}}]*)\}}", styles, re.MULTILINE)
    if match is None:
        raise ContractError(f"required CSS selector is missing: {selector}")
    return match.group(1)


def _css_pixels(block: str, property_name: str) -> float:
    """Return one pixel-valued declaration from a CSS block."""
    match = re.search(rf"\b{re.escape(property_name)}\s*:\s*([0-9]+(?:\.[0-9]+)?)px\s*;", block)
    if match is None:
        raise ContractError(f"{property_name} must use an explicit pixel floor")
    return float(match.group(1))


def _validate_foundation_contract(styles: str) -> None:
    """Require native typography, resilient sizing, and readable copy."""
    lowered = styles.lower()
    if "@font-face" in lowered or re.search(r"url\([^)]*\.(?:woff2?|ttf|otf)", lowered):
        raise ContractError("remote and embedded font requests are forbidden")
    box_sizing = _css_block(styles, "*,\n*::before,\n*::after")
    if re.search(r"\bbox-sizing\s*:\s*border-box\s*;", box_sizing) is None:
        raise ContractError("global border-box sizing is required")

    body = _css_block(styles, "body")
    required_stack = '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif'
    if required_stack not in body:
        raise ContractError("body must use the native system font stack")
    if re.search(r"\bmargin\s*:\s*0\s*;", body) is None:
        raise ContractError("body margin must be zero")
    if _css_pixels(body, "font-size") < 16:
        raise ContractError("normal body copy must be at least 16px")
    line_height = re.search(r"\bline-height\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*;", body)
    if line_height is None or float(line_height.group(1)) < 1.5:
        raise ContractError("body line height must remain readable")
    if "overflow-wrap: anywhere;" not in body:
        raise ContractError("body copy must wrap overflow safely")
    for size in re.findall(r"\bfont-size\s*:\s*([0-9]+(?:\.[0-9]+)?)px\s*;", styles):
        if float(size) < 14:
            raise ContractError("small notes must not fall below 14px")

    image = _css_block(styles, "img")
    image_contract = ("max-width: 100%;", "height: auto;", "display: block;")
    if any(declaration not in image for declaration in image_contract):
        raise ContractError("images must scale without horizontal overflow")
    resilient = _css_block(styles, "main,\nsection,\nfigure,\n.download-option")
    if "min-width: 0;" not in resilient:
        raise ContractError("layout children must allow overflow-safe sizing")


def _validate_figure_margin_contract(styles: str) -> None:
    """Require figures to fill their grid track without browser margins."""
    figure = effective_declarations(styles, CssNode("figure"), 1024)
    if figure.get("margin") != "0":
        raise ContractError("figures must reset the full browser margin")
    caption = effective_declarations(styles, CssNode("figcaption"), 1024)
    if caption.get("margin-top") != "12px":
        raise ContractError("figure captions must keep 12px spacing")


def _validate_requirements_list_contract(styles: str) -> None:
    """Keep native requirements-list semantics and an approved visible marker."""
    requirements = CssNode("section", identifier="requirements")
    list_styles = effective_declarations(styles, CssNode("ul", parent=requirements), 1024)
    if any(list_styles.get(name, "").strip().lower() == "none" for name in ("list-style", "list-style-type")):
        raise ContractError("requirements must keep native list markers")
    marker_colors = [
        rule.declarations["color"]
        for rule in parse_css_rules(styles)
        if "#requirements li::marker" in rule.selectors and "color" in rule.declarations
    ]
    if marker_colors != ["var(--button-hover)"]:
        raise ContractError("requirements markers must use the legible dark accent")


def _validate_interaction_contract(styles: str) -> None:
    """Require visible keyboard focus, link cues, and usable action targets."""
    lowered = styles.lower()
    if re.search(r"\boutline\s*:\s*(?:0|none)\b", lowered):
        raise ContractError("focus outlines must not be removed")

    skip = _css_block(styles, ".skip-link")
    skip_focus = _css_block(styles, ".skip-link:focus")
    if "position: fixed;" not in skip or "transform: translateY(-150%);" not in skip:
        raise ContractError("skip link must be visually hidden without being removed")
    if "transform: translateY(0);" not in skip_focus:
        raise ContractError("skip link must become visible on focus")

    focus = _css_block(styles, ":focus-visible")
    outline = re.search(r"\boutline\s*:\s*([0-9]+(?:\.[0-9]+)?)px\s+solid\s+var\(--focus\)\s*;", focus)
    offset = re.search(r"\boutline-offset\s*:\s*([0-9]+(?:\.[0-9]+)?)px\s*;", focus)
    if outline is None or float(outline.group(1)) < 3 or offset is None or float(offset.group(1)) < 2:
        raise ContractError("focus-visible must use a visible focus outline")
    summary_focus = _css_block(styles, "summary:focus-visible")
    if "outline-color: var(--focus);" not in summary_focus:
        raise ContractError("summary focus must remain visible")

    primary = _css_block(styles, ".download-primary")
    if "display: inline-flex;" not in primary or _css_pixels(primary, "min-height") < 44:
        raise ContractError("download action target must be at least 44px")
    nav_links = _css_block(styles, ".site-header nav a,\n.site-footer a")
    if "display: inline-flex;" not in nav_links or _css_pixels(nav_links, "min-height") < 44:
        raise ContractError("navigation link target must be at least 44px")
    linked_copy = _css_block(styles, "a:not(.download-primary)")
    if "text-decoration: underline;" not in linked_copy or "text-underline-offset:" not in linked_copy:
        raise ContractError("text links need a non-color underline cue")


def _css_signed_pixels(value: str) -> float:
    """Resolve the fixed stylesheet's signed pixel position or unitless zero."""
    if value.strip() == "0":
        return 0
    pixels = re.fullmatch(r"(-?[0-9]+(?:\.[0-9]+)?)px", value.strip())
    if pixels is None:
        raise ContractError("skip link position must use a reviewed pixel value")
    return float(pixels.group(1))


def _validate_skip_link_visibility_contract(styles: str) -> None:
    """Keep the focused skip link on-screen and above page content."""
    body = CssNode("body")
    skip = CssNode("a", frozenset({"skip-link"}), parent=body)
    focused_skip = CssNode(
        "a",
        frozenset({"skip-link"}),
        states=frozenset({"focus"}),
        parent=body,
    )
    for viewport in (375, 768, 1024, 1440):
        base = effective_declarations(styles, skip, viewport)
        focused = effective_declarations(styles, focused_skip, viewport)
        top = _css_signed_pixels(base.get("top", ""))
        left = _css_signed_pixels(base.get("left", ""))
        if not 0 <= top <= 64 or not 0 <= left <= 64:
            raise ContractError("skip link position must remain reasonably on-screen")
        z_index = re.fullmatch(r"[0-9]+", base.get("z-index", ""))
        if z_index is None or int(z_index.group()) < 10:
            raise ContractError("skip link z-index must remain above page content")
        if base.get("position") != "fixed" or base.get("transform") != "translateY(-150%)":
            raise ContractError("skip link base hiding must remain vertical")
        if focused.get("transform") != "translateY(0)":
            raise ContractError("skip link focus must restore its on-screen position")


def _css_media_block(styles: str, condition: str) -> str:
    """Return the balanced body of one literal media query."""
    match = re.search(rf"@media\s*{re.escape(condition)}\s*\{{", styles)
    if match is None:
        raise ContractError(f"required media query is missing: {condition}")
    start = match.end()
    depth = 1
    for index in range(start, len(styles)):
        if styles[index] == "{":
            depth += 1
        elif styles[index] == "}":
            depth -= 1
            if depth == 0:
                return styles[start:index]
    raise ContractError(f"media query is unbalanced: {condition}")


def _validate_supported_cascade_contract(styles: str) -> None:
    """Reject cascade features outside this fixed stylesheet evaluator's scope."""
    source = re.sub(r"/\*.*?\*/", "", styles, flags=re.DOTALL)
    allowed_media = {
        "(max-width: 700px)",
        "(min-width: 701px)",
        "(min-width: 900px)",
        "(min-width: 1024px)",
        "(prefers-reduced-motion: reduce)",
    }
    at_rules = re.findall(r"@([A-Za-z-]+)\b", source)
    if any(at_rule.lower() != "media" for at_rule in at_rules):
        raise ContractError("unsupported cascade at-rule is forbidden")
    conditions = [condition.strip() for condition in re.findall(r"@media\s*([^{}]+?)\s*\{", source)]
    if any(condition not in allowed_media for condition in conditions):
        raise ContractError("unsupported cascade media condition is forbidden")
    if re.search(r"(?:^|[;{])\s*all\s*:", source, re.MULTILINE):
        raise ContractError("unsupported cascade all shorthand is forbidden")

    rules = parse_css_rules(source)
    for rule in rules:
        for property_name in rule.declarations:
            if property_name.startswith("--"):
                continue
            if property_name not in ALLOWED_CSS_PROPERTIES:
                raise ContractError(f"unsupported CSS property: {property_name}")

    required_properties = {
        "align-items",
        "background",
        "background-color",
        "color",
        "display",
        "font-size",
        "gap",
        "grid-template-columns",
        "max-width",
        "min-height",
        "outline",
        "outline-color",
        "padding-inline",
        "width",
    }
    for rule in rules:
        if required_properties.isdisjoint(rule.declarations):
            continue
        for selector in rule.selectors:
            if selector == "#requirements li::marker" and set(rule.declarations) == {"color"}:
                continue
            functions = re.findall(r":([\w-]+)\(", selector)
            unsupported_syntax = any(character in selector for character in "+~[]&\\")
            if unsupported_syntax or "::" in selector or any(name != "not" for name in functions):
                raise ContractError("unsupported cascade selector is forbidden for required properties")

    reduced = _css_media_block(source, "(prefers-reduced-motion: reduce)")
    outside_reduced = source.replace(reduced, "", 1)
    if re.search(r"!\s*important\b", outside_reduced, re.IGNORECASE):
        raise ContractError("unsupported cascade important declaration is forbidden")
    important_declarations = re.findall(
        r"([\w-]+)\s*:\s*([^;]*!\s*important[^;]*);",
        reduced,
        re.IGNORECASE,
    )
    if len(important_declarations) != len(re.findall(r"!\s*important\b", reduced, re.IGNORECASE)):
        raise ContractError("unsupported cascade important declaration is malformed")
    for property_name, value in important_declarations:
        normalized = re.sub(r"\s+", " ", value.strip().lower()).replace("! important", "!important")
        if property_name.lower() != "transition" or normalized != "none !important":
            raise ContractError("unsupported cascade important declaration is forbidden")


def _validate_global_style_invariants(styles: str) -> None:
    """Enforce safety boundaries for this fixed, dependency-free stylesheet."""
    rules = parse_css_rules(styles)
    body = CssNode("body")
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    results = CssNode("section", identifier="results", parent=main)
    downloads = CssNode("section", identifier="downloads", parent=main)
    pair = CssNode("div", frozenset({"download-pair"}), parent=downloads)
    option = CssNode("article", frozenset({"download-option"}), parent=pair)
    protected_nodes = (
        hero,
        hero_copy,
        CssNode("h1", parent=hero_copy),
        results,
        CssNode("h2", parent=results),
        downloads,
        pair,
        option,
        CssNode("h3", parent=option),
    )
    normal_transitions: list[tuple[tuple[str, ...], str]] = []
    reduced_transitions: list[tuple[tuple[str, ...], str]] = []
    for rule in rules:
        for property_name, value in rule.declarations.items():
            normalized = re.sub(r"\s+", " ", value.strip().lower())
            if property_name == "display" and normalized == "none":
                raise ContractError("production selectors must not hide content")
            if property_name == "min-width":
                reviewed_group = ("main", "section", "figure", ".download-option")
                if (
                    rule.selectors != reviewed_group
                    or normalized != "0"
                    or rule.minimum_width != 0
                    or rule.maximum_width != float("inf")
                    or rule.reduced_motion
                ):
                    raise ContractError("only the reviewed min-width: 0 layout group is allowed")
            cascade_name = _cascade_property_name(property_name)
            if cascade_name in {"color", "background-color"}:
                matches_protected = any(
                    selector_matches(selector, node)
                    for selector in rule.selectors
                    for node in protected_nodes
                )
                approved_main_background = (
                    rule.selectors == ("main",)
                    and cascade_name == "background-color"
                )
                if matches_protected and not approved_main_background:
                    raise ContractError("heading and layout ancestors must not override reviewed colors")
            if property_name == "transition":
                target = reduced_transitions if rule.reduced_motion else normal_transitions
                target.append((rule.selectors, normalized))

    expected_primary = (
        (".download-primary",),
        "background-color 160ms ease, transform 160ms ease",
    )
    expected_reduced = (
        ("*", "*::before", "*::after"),
        "none !important",
    )
    if normal_transitions != [expected_primary] or reduced_transitions != [expected_reduced]:
        raise ContractError("only the exact reviewed download and reduced-motion transitions are allowed")


def _validate_layout_contract(styles: str) -> None:
    """Require the approved editorial layouts at mobile and desktop widths."""
    container = _css_block(styles, ".site-header,\nmain > *,\n.site-footer")
    container_contract = (
        "width: 100%;",
        "max-width: 1200px;",
        "margin-inline: auto;",
        "padding-inline: 24px;",
    )
    if any(declaration not in container for declaration in container_contract):
        raise ContractError("content container must be fluid and no wider than 1200px")

    header = _css_block(styles, ".site-header")
    if _css_pixels(header, "min-height") < 76:
        raise ContractError("header must keep an approximately 78px minimum height")
    if any(value not in header for value in ("display: flex;", "flex-wrap: wrap;", "align-items: center;")):
        raise ContractError("header must wrap without hiding navigation")
    navigation = _css_block(styles, ".site-header nav")
    if "display: flex;" not in navigation or "flex-wrap: wrap;" not in navigation:
        raise ContractError("navigation must remain visible and wrap")
    logo = _css_block(styles, ".brand img")
    if _css_pixels(logo, "width") < 36 or _css_pixels(logo, "height") < 36:
        raise ContractError("brand must use the real icon at a readable size")

    hero = _css_block(styles, ".hero")
    if "display: grid;" not in hero or "grid-template-columns: minmax(0, 1fr);" not in hero:
        raise ContractError("hero must preserve one-column source order on mobile")
    hero_actions = _css_block(styles, ".hero-copy .download-primary")
    if "width: 100%;" not in hero_actions or "max-width: 360px;" not in hero_actions:
        raise ContractError("hero platform actions must receive equal placement")
    heading = _css_block(styles, "h1")
    if "font-size: clamp(" not in heading or "max-width: 16ch;" not in heading:
        raise ContractError("hero heading must scale to about two desktop lines")
    if "font-size: clamp(" not in _css_block(styles, "h2"):
        raise ContractError("section headings must use fluid type")

    steps = _css_block(styles, ".how-step")
    if "display: grid;" not in steps or "border-top: 1px solid var(--rule);" not in steps:
        raise ContractError("how steps must be numbered rows separated by rules")
    if re.search(r"\b(?:background|box-shadow|border-radius)\s*:", steps):
        raise ContractError("how steps must not become cards")
    results = _css_block(styles, "#results")
    if "grid-template-columns: minmax(0, 1fr);" not in results:
        raise ContractError("results must remain one column on mobile")
    downloads = _css_block(styles, ".download-pair")
    if "grid-template-columns: minmax(0, 1fr);" not in downloads:
        raise ContractError("download pair must stack on narrow screens")
    if "border: 1px solid var(--rule);" not in downloads or "border-radius: 8px;" not in downloads:
        raise ContractError("downloads must share one bordered pair")
    requirements = _css_block(styles, "#requirements li")
    if "border-bottom: 1px solid var(--rule);" not in requirements:
        raise ContractError("requirements must use plain documentation rows")
    details = _css_block(styles, "#faq details")
    if "border-top: 1px solid var(--rule);" not in details:
        raise ContractError("FAQ details must be separated by borders")
    if "cursor: pointer;" not in _css_block(styles, "#faq summary"):
        raise ContractError("native FAQ summaries must show pointer affordance")

    mobile = _css_media_block(styles, "(max-width: 700px)")
    if "width: 100%;" not in _css_block(mobile, ".site-header nav"):
        raise ContractError("mobile navigation must stack without hidden links")
    if "border-top: 1px solid var(--rule);" not in _css_block(mobile, ".download-option + .download-option"):
        raise ContractError("stacked downloads must retain a separating rule")
    tablet = _css_media_block(styles, "(min-width: 701px)")
    if "grid-template-columns: repeat(2, minmax(0, 1fr));" not in _css_block(tablet, ".download-pair"):
        raise ContractError("download pair must become two columns above 700px")
    desktop = _css_media_block(styles, "(min-width: 900px)")
    desktop_hero = _css_block(desktop, ".hero")
    if "grid-template-columns: minmax(0, 1.2fr) minmax(0, 0.8fr);" not in desktop_hero:
        raise ContractError("desktop hero must use asymmetric columns")
    desktop_results = _css_block(desktop, "#results")
    if "grid-template-columns: minmax(0, 1.08fr) minmax(0, 0.92fr);" not in desktop_results:
        raise ContractError("desktop results must use an asymmetric two-figure grid")
    wide = _css_media_block(styles, "(min-width: 1024px)")
    if "padding-inline: 48px;" not in _css_block(wide, ".site-header,\nmain > *,\n.site-footer"):
        raise ContractError("desktop container must use fluid wide gutters")


def _validate_effective_responsive_contract(styles: str) -> None:
    """Resolve required layout declarations at the four reviewed widths."""
    main = CssNode("main")
    nodes = {
        "header": CssNode("header", frozenset({"site-header"})),
        "hero": CssNode("div", frozenset({"hero"}), parent=main),
        "results": CssNode("section", identifier="results", parent=main),
        "footer": CssNode("footer", frozenset({"site-footer"})),
        "downloads": CssNode(
            "div",
            frozenset({"download-pair"}),
            parent=CssNode("section", identifier="downloads", parent=main),
        ),
    }
    profiles = {
        375: (
            "minmax(0, 1fr)",
            "minmax(0, 1fr)",
            "minmax(0, 1fr)",
            "24px",
        ),
        768: (
            "minmax(0, 1fr)",
            "minmax(0, 1fr)",
            "repeat(2, minmax(0, 1fr))",
            "24px",
        ),
        1024: (
            "minmax(0, 1.2fr) minmax(0, 0.8fr)",
            "minmax(0, 1.08fr) minmax(0, 0.92fr)",
            "repeat(2, minmax(0, 1fr))",
            "48px",
        ),
        1440: (
            "minmax(0, 1.2fr) minmax(0, 0.8fr)",
            "minmax(0, 1.08fr) minmax(0, 0.92fr)",
            "repeat(2, minmax(0, 1fr))",
            "48px",
        ),
    }
    for viewport, (hero_columns, result_columns, download_columns, gutter) in profiles.items():
        computed = {
            name: effective_declarations(styles, node, viewport)
            for name, node in nodes.items()
        }
        for name in ("header", "hero", "results", "footer"):
            expected = {
                "width": "100%",
                "max-width": "1200px",
                "padding-inline": gutter,
            }
            for property_name, value in expected.items():
                if computed[name].get(property_name) != value:
                    raise ContractError(
                        f"effective responsive {name} {property_name} at {viewport}px "
                        f"must be {value}"
                    )
        expected_layout = {
            "hero": ("grid", hero_columns),
            "results": ("grid", result_columns),
            "downloads": ("grid", download_columns),
        }
        for name, (display, columns) in expected_layout.items():
            if computed[name].get("display") != display:
                raise ContractError(f"effective responsive {name} display at {viewport}px must be grid")
            if computed[name].get("grid-template-columns") != columns:
                raise ContractError(
                    f"effective responsive {name} columns at {viewport}px must be {columns}"
                )


def _css_length_pixels(value: str, viewport: float) -> float:
    """Resolve the fixed stylesheet's pixel and px/vw clamp lengths."""
    if value.strip() == "0":
        return 0
    pixels = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)px", value.strip())
    if pixels:
        return float(pixels.group(1))
    clamp = re.fullmatch(
        r"clamp\(\s*([0-9.]+)px\s*,\s*([0-9.]+)vw\s*,\s*([0-9.]+)px\s*\)",
        value.strip(),
    )
    if clamp:
        minimum, fluid, maximum = (float(component) for component in clamp.groups())
        return min(maximum, max(minimum, viewport * fluid / 100))
    raise ContractError("effective target contract uses an unsupported length")


def _css_gap_pixels(value: str, viewport: float) -> tuple[float, ...]:
    """Resolve one or two fixed-stylesheet gap components to pixels."""
    normalized = re.sub(r"\s+", " ", value.strip())
    components = re.findall(r"clamp\([^()]*\)|[^\s]+", normalized)
    if not 1 <= len(components) <= 2 or " ".join(components) != normalized:
        raise ContractError("CSS gap must use one or two reviewed length values")
    return tuple(_css_length_pixels(component, viewport) for component in components)


def _css_length_maximum_pixels(value: str) -> float:
    """Return the explicit maximum of one reviewed gap length."""
    if value.strip() == "0":
        return 0
    pixels = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)px", value.strip())
    if pixels:
        return float(pixels.group(1))
    clamp = re.fullmatch(
        r"clamp\(\s*([0-9.]+)px\s*,\s*([0-9.]+)vw\s*,\s*([0-9.]+)px\s*\)",
        value.strip(),
    )
    if clamp is None:
        raise ContractError("CSS gaps use an unsupported length")
    minimum, fluid, maximum = (float(component) for component in clamp.groups())
    if not 0 <= minimum <= maximum or fluid < 0:
        raise ContractError("CSS gaps require a finite ordered clamp")
    return maximum


def _css_font_size_minimum(value: str) -> float:
    """Return the minimum size from a reviewed px or px/vw clamp value."""
    pixels = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)px", value.strip())
    if pixels:
        return float(pixels.group(1))
    clamp = re.fullmatch(
        r"clamp\(\s*([0-9.]+)px\s*,\s*([0-9.]+)vw\s*,\s*([0-9.]+)px\s*\)",
        value.strip(),
    )
    if clamp is None:
        raise ContractError("CSS font-size must use px or the reviewed px/vw clamp")
    minimum, fluid, maximum = (float(component) for component in clamp.groups())
    if not 0 <= minimum <= maximum or fluid < 0:
        raise ContractError("CSS font-size clamp must be finite and ordered")
    return minimum


def _validate_spacing_typography_contract(styles: str) -> None:
    """Bound every gap, font size, and line height in the fixed vocabulary."""
    copy_line_height_selectors = {
        _normalized_selector_group(selector)
        for selector in ("body", "figcaption", ".hero-explanation")
    }
    heading_line_height_selectors = {
        _normalized_selector_group(selector)
        for selector in ("h1", "h2", "h3")
    }
    for rule in parse_css_rules(styles):
        for property_name, value in rule.declarations.items():
            if property_name in {"gap", "row-gap", "column-gap"}:
                components = re.findall(r"clamp\([^()]*\)|[^\s]+", value.strip())
                if any(_css_length_maximum_pixels(component) > 100 for component in components):
                    raise ContractError("CSS gaps must have an explicit maximum no larger than 100px")
                for viewport in (375, 768, 1024, 1440):
                    gaps = _css_gap_pixels(value, viewport)
                    if any(not math.isfinite(gap) or not 0 <= gap <= 100 for gap in gaps):
                        raise ContractError("CSS gaps must remain finite and no larger than 100px")
            elif property_name == "font-size":
                if _css_font_size_minimum(value) < 14:
                    raise ContractError("CSS font sizes must keep a 14px minimum")
            elif property_name == "line-height":
                line_height = re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", value.strip())
                if line_height is None or float(line_height.group()) <= 0:
                    raise ContractError("CSS line heights must be positive unitless values")
                selector_key = _normalized_selector_group(rule.selectors)
                numeric_line_height = float(line_height.group())
                if selector_key in heading_line_height_selectors and numeric_line_height < 1:
                    raise ContractError("CSS heading line heights must remain at least 1.0")
                if selector_key in copy_line_height_selectors and numeric_line_height < 1.5:
                    raise ContractError("CSS copy line heights must remain readable")

    body = CssNode("body")
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    how = CssNode("section", identifier="how", parent=main)
    how_step = CssNode("div", frozenset({"how-step"}), parent=how)
    results = CssNode("section", identifier="results", parent=main)
    type_nodes = {
        "body": (body, 16),
        "hero heading": (CssNode("h1", parent=hero_copy), 46),
        "section heading": (CssNode("h2", parent=results), 32),
        "row heading": (CssNode("h3", parent=how_step), 20),
        "hero explanation": (CssNode("p", frozenset({"hero-explanation"}), parent=hero_copy), 18),
    }
    for viewport in (375, 768, 1024, 1440):
        if effective_declarations(styles, hero_copy, viewport).get("flex-direction") != "column":
            raise ContractError("effective hero copy must remain a column at every width")
        expected_gaps = {
            hero: "clamp(36px, 6vw, 76px)",
            how_step: "2px 18px" if viewport < 900 else "28px",
            results: "36px",
        }
        for node, expected in expected_gaps.items():
            if effective_declarations(styles, node, viewport).get("gap") != expected:
                raise ContractError("effective grid gaps must match the reviewed editorial layout")
        for label, (node, minimum) in type_nodes.items():
            font_size = effective_declarations(styles, node, viewport).get("font-size", "")
            if _css_length_pixels(font_size, viewport) < minimum:
                raise ContractError(f"effective {label} font size is below its reviewed floor")


def _validate_effective_action_target(styles: str, class_name: str) -> None:
    """Require one secondary action to retain its effective 44px target."""
    body = CssNode("body")
    main = CssNode("main", parent=body)
    if class_name == "secondary-link":
        hero = CssNode("div", frozenset({"hero"}), parent=main)
        parent = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    else:
        downloads = CssNode("section", identifier="downloads", parent=main)
        pair = CssNode("div", frozenset({"download-pair"}), parent=downloads)
        option = CssNode(
            "article",
            frozenset({"download-option", "download-option-windows"}),
            parent=pair,
        )
        parent = CssNode("p", parent=option)
    node = CssNode("a", frozenset({class_name}), parent=parent)
    for viewport in (375, 768, 1024, 1440):
        declarations = effective_declarations(styles, node, viewport)
        if declarations.get("display") != "inline-flex" or declarations.get("align-items") != "center":
            raise ContractError(f"effective target contract for .{class_name} requires inline flex")
        minimum_height = _css_length_pixels(declarations.get("min-height", ""), viewport)
        if minimum_height < 44:
            raise ContractError(f"effective target contract for .{class_name} requires 44px")


def _validate_effective_interaction_targets(styles: str) -> None:
    """Require every reviewed interactive element to retain a 44px target."""
    body = CssNode("body")
    header = CssNode("header", frozenset({"site-header"}), parent=body)
    navigation = CssNode("nav", parent=header)
    footer = CssNode("footer", frozenset({"site-footer"}), parent=body)
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    downloads = CssNode("section", identifier="downloads", parent=main)
    pair = CssNode("div", frozenset({"download-pair"}), parent=downloads)
    option = CssNode("article", frozenset({"download-option"}), parent=pair)
    option_copy = CssNode("p", parent=option)
    faq = CssNode("section", identifier="faq", parent=main)
    targets = {
        "skip link": CssNode("a", frozenset({"skip-link"}), parent=body),
        "brand": CssNode("a", frozenset({"brand"}), parent=header),
        "navigation link": CssNode("a", parent=navigation),
        "footer link": CssNode("a", parent=footer),
        "hero primary": CssNode(
            "a",
            frozenset({"download-primary", "download-windows"}),
            parent=hero_copy,
        ),
        "download primary": CssNode(
            "a",
            frozenset({"download-primary", "download-macos"}),
            parent=option,
        ),
        "secondary action": CssNode("a", frozenset({"secondary-link"}), parent=hero_copy),
        "fallback action": CssNode("a", frozenset({"download-fallback"}), parent=option_copy),
        "FAQ summary": CssNode("summary", parent=CssNode("details", parent=faq)),
    }
    for viewport in (375, 768, 1024, 1440):
        for label, node in targets.items():
            minimum_height = effective_declarations(styles, node, viewport).get("min-height")
            if minimum_height is None or _css_length_pixels(minimum_height, viewport) < 44:
                raise ContractError(f"effective interaction target for {label} requires 44px")


def _validate_effective_heading_contract(styles: str) -> None:
    """Require the effective desktop heading to retain a two-line measure."""
    main = CssNode("main")
    hero_node = CssNode("div", frozenset({"hero"}), parent=main)
    heading_node = CssNode(
        "h1",
        identifier="hero-title",
        parent=CssNode("div", frozenset({"hero-copy"}), parent=hero_node),
    )
    for viewport in (1200, 1440):
        hero = effective_declarations(styles, hero_node, viewport)
        heading = effective_declarations(styles, heading_node, viewport)
        font_size = _css_length_pixels(heading.get("font-size", ""), viewport)
        if not 64 <= font_size <= 74:
            raise ContractError("effective target contract for h1 requires editorial desktop type")
        heading_measure = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)ch", heading.get("max-width", ""))
        if heading_measure is None:
            raise ContractError("effective target contract for h1 requires a ch measure")
        columns = re.fullmatch(
            r"minmax\(0,\s*([0-9.]+)fr\)\s*minmax\(0,\s*([0-9.]+)fr\)",
            hero.get("grid-template-columns", ""),
        )
        if columns is None:
            raise ContractError("effective target contract for h1 requires two hero tracks")
        copy_fraction, photo_fraction = (float(component) for component in columns.groups())
        outer_width = min(viewport, _css_length_pixels(hero.get("max-width", ""), viewport))
        gutter = _css_length_pixels(hero.get("padding-inline", ""), viewport)
        gap = _css_length_pixels(hero.get("gap", ""), viewport)
        track_width = outer_width - 2 * gutter - gap
        copy_width = track_width * copy_fraction / (copy_fraction + photo_fraction)
        photo_width = track_width * photo_fraction / (copy_fraction + photo_fraction)
        maximum_measure = float(heading_measure.group(1)) * font_size * 0.5
        effective_measure = min(copy_width, maximum_measure)
        minimum_measure = len("damaged screen.") * font_size * 0.5
        if effective_measure < minimum_measure or photo_width < 400:
            raise ContractError("effective target contract for h1 requires a two-line editorial measure")


def _validate_effective_layout_safety_contract(styles: str) -> None:
    """Keep figures, hero copy, heading, and results within reviewed tracks."""
    body = CssNode("body")
    main = CssNode("main", parent=body)
    hero = CssNode("div", frozenset({"hero"}), parent=main)
    hero_copy = CssNode("div", frozenset({"hero-copy"}), parent=hero)
    hero_figure = CssNode("figure", frozenset({"hero-figure"}), parent=hero)
    heading = CssNode("h1", identifier="hero-title", parent=hero_copy)
    results = CssNode("section", identifier="results", parent=main)
    results_figure = CssNode("figure", parent=results)
    for viewport in (375, 768, 1024, 1440):
        hero_styles = effective_declarations(styles, hero, viewport)
        copy_styles = effective_declarations(styles, hero_copy, viewport)
        heading_styles = effective_declarations(styles, heading, viewport)
        results_styles = effective_declarations(styles, results, viewport)
        for figure in (hero_figure, results_figure):
            figure_styles = effective_declarations(styles, figure, viewport)
            if figure_styles.get("margin") != "0":
                raise ContractError("effective layout requires figures to fill their grid track")
        hero_figure_styles = effective_declarations(styles, hero_figure, viewport)
        if hero_figure_styles.get("margin-bottom") != "0":
            raise ContractError("effective layout requires the hero figure margin to remain zero")
        if "height" in heading_styles or heading_styles.get("overflow", "visible") != "visible":
            raise ContractError("effective layout requires a visible, unclipped hero heading")

        outer_width = min(viewport, _css_length_pixels(hero_styles.get("max-width", ""), viewport))
        gutter = _css_length_pixels(hero_styles.get("padding-inline", ""), viewport)
        available_width = outer_width - 2 * gutter
        columns = re.fullmatch(
            r"minmax\(0,\s*([0-9.]+)fr\)(?:\s+minmax\(0,\s*([0-9.]+)fr\))?",
            hero_styles.get("grid-template-columns", ""),
        )
        if columns is None:
            raise ContractError("effective layout requires reviewed hero tracks")
        first_fraction, second_fraction = columns.groups()
        copy_track = available_width
        if second_fraction is not None:
            gap = _css_length_pixels(hero_styles.get("gap", ""), viewport)
            copy_track = (available_width - gap) * float(first_fraction) / (
                float(first_fraction) + float(second_fraction)
            )
        declared_copy_width = copy_styles.get("width")
        copy_width = (
            copy_track
            if declared_copy_width is None
            else _css_length_pixels(declared_copy_width, viewport)
        )
        if copy_width > copy_track:
            raise ContractError("effective layout requires hero copy to fit its grid track")
        results_gap = _css_length_pixels(results_styles.get("gap", ""), viewport)
        if not 0 <= results_gap <= 100:
            raise ContractError("effective layout requires an editorial results gap no larger than 100px")


def _validate_effective_target_contract(styles: str) -> None:
    """Validate the cascade-sensitive secondary actions and hero heading."""
    _validate_effective_action_target(styles, "secondary-link")
    _validate_effective_action_target(styles, "download-fallback")
    _validate_effective_heading_contract(styles)


def _validate_forbidden_style_contract(styles: str) -> None:
    """Reject template aesthetics, unsafe motion, and hidden overflow."""
    source = re.sub(r"/\*.*?\*/", "", styles, flags=re.DOTALL)
    lowered = source.lower()
    forbidden = {
        "@import": "external CSS imports are forbidden",
        "@font-face": "remote and embedded font requests are forbidden",
        "@keyframes": "keyframe animation is forbidden",
        "backdrop-filter": "backdrop blur and glass effects are forbidden",
        "blur(": "blur effects are forbidden",
        "linear-gradient(": "large background gradients are forbidden",
        "radial-gradient(": "large background gradients are forbidden",
        "box-shadow": "shadow stacks are forbidden",
        "text-shadow": "glow and text shadows are forbidden",
        "text-transform: uppercase": "uppercase label styling is forbidden",
        "background-attachment: fixed": "fixed decorative backgrounds are forbidden",
        "overflow-x: hidden": "horizontal overflow must be prevented by sizing",
        "display: none": "essential links and content must not be hidden",
        "carousel": "carousel patterns are forbidden",
        "parallax": "parallax patterns are forbidden",
        "glass": "glass effects are forbidden",
        "glow": "glow effects are forbidden",
    }
    for pattern, message in forbidden.items():
        if pattern in lowered:
            raise ContractError(message)
    if re.search(r"\banimation(?:-name)?\s*:", lowered):
        raise ContractError("animation declarations are forbidden")
    for value in re.findall(r"\bborder-radius\s*:\s*([^;]+);", lowered):
        pixels = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)px", value.strip())
        if pixels is None or float(pixels.group(1)) > 8:
            raise ContractError("giant pill radii are forbidden")

    primary = _css_block(styles, ".download-primary")
    transition = "transition: background-color 160ms ease, transform 160ms ease;"
    if transition not in primary:
        raise ContractError("motion must be short color and position feedback")
    for duration in re.findall(r"([0-9]+(?:\.[0-9]+)?)ms", primary):
        if float(duration) > 200:
            raise ContractError("motion feedback must remain short")
    reduced = _css_media_block(styles, "(prefers-reduced-motion: reduce)")
    reduced_html = _css_block(reduced, "html")
    reduced_all = _css_block(reduced, "*,\n*::before,\n*::after")
    if "scroll-behavior: auto;" not in reduced_html or "transition: none !important;" not in reduced_all:
        raise ContractError("reduced motion must remove smooth scroll and transitions")


def validate_stylesheet(styles: str) -> None:
    """Validate the landing-page stylesheet source contract."""
    _validate_supported_cascade_contract(styles)
    _validate_global_style_invariants(styles)
    _validate_color_contract(styles)
    _validate_effective_color_contract(styles)
    _validate_text_contrast_contract(styles)
    _validate_foundation_contract(styles)
    _validate_spacing_typography_contract(styles)
    _validate_figure_margin_contract(styles)
    _validate_requirements_list_contract(styles)
    _validate_interaction_contract(styles)
    _validate_skip_link_visibility_contract(styles)
    _validate_layout_contract(styles)
    _validate_effective_responsive_contract(styles)
    _validate_effective_target_contract(styles)
    _validate_effective_interaction_targets(styles)
    _validate_effective_layout_safety_contract(styles)
    _validate_forbidden_style_contract(styles)
    _validate_rule_vocabulary_contract(styles)


class _SvgTreeBuilder(ET.TreeBuilder):
    """Build SVG XML while rejecting every processing instruction."""

    def pi(self, target: str, text: str | None) -> None:
        """Reject stylesheet and other XML processing instructions."""
        raise ContractError("SVG processing instructions are forbidden")


def validate_svg(svg: bytes) -> None:
    """Validate the site icon's XML namespace and active-content boundaries."""
    try:
        parser = ET.XMLParser(target=_SvgTreeBuilder())
        root = ET.fromstring(svg, parser=parser)
    except ET.ParseError as error:
        raise ContractError("SVG XML is malformed") from error
    if root.tag != f"{{{SVG_NAMESPACE}}}svg":
        raise ContractError("SVG root namespace is invalid")
    for element in root.iter():
        if not element.tag.startswith(f"{{{SVG_NAMESPACE}}}"):
            raise ContractError("SVG element namespace is invalid")
        local_tag = element.tag.rsplit("}", 1)[-1]
        if local_tag not in ALLOWED_SVG_TAGS:
            raise ContractError("SVG element is not allowed")
        for raw_name, value in element.attrib.items():
            if raw_name.startswith("{") and not raw_name.startswith(f"{{{SVG_NAMESPACE}}}"):
                raise ContractError("SVG attribute namespace is invalid")
            name = raw_name.rsplit("}", 1)[-1].lower()
            if name.startswith("on") or name in {"href", "src", "style"}:
                raise ContractError("SVG external references are forbidden")
            _validate_css_urls(value)
        _validate_css_urls(element.text or "")
        _validate_css_urls(element.tail or "")


def _validate_css_urls(value: str) -> None:
    """Allow CSS URL references only when they target a local fragment."""
    if "\\" in value:
        raise ContractError("SVG CSS escapes are forbidden")
    if re.search(r"@import\b", value, re.IGNORECASE):
        raise ContractError("SVG CSS imports are forbidden")
    matches = CSS_URL.findall(value)
    if value.lower().count("url(") != len(matches):
        raise ContractError("SVG CSS URL is malformed")
    for target in matches:
        normalized = target.strip()
        if len(normalized) >= 2 and normalized[0] == normalized[-1] and normalized[0] in {'"', "'"}:
            normalized = normalized[1:-1]
        if LOCAL_CSS_URL.fullmatch(normalized) is None:
            raise ContractError("SVG CSS URL must use a local fragment")


def parse_jpeg(source: Path | bytes) -> tuple[int, int]:
    """Return JPEG dimensions after validating a metadata-free marker stream."""
    data = _read_jpeg_path(source) if isinstance(source, Path) else source
    width, height = _walk_jpeg(data)
    return width, height


def _read_jpeg_path(path: Path) -> bytes:
    """Read one bounded regular JPEG file without following symlinks."""
    path_status = path.lstat()
    if not stat.S_ISREG(path_status.st_mode):
        raise ContractError("JPEG path must be a regular non-symlink file")
    if path_status.st_size > MAX_IMAGE_BYTES:
        raise ContractError("JPEG file exceeds the size limit")
    return path.read_bytes()


def read_u16(data: bytes, offset: int) -> int:
    """Read one big-endian JPEG integer inside validated bounds."""
    if offset < 0 or offset + 2 > len(data):
        raise ContractError("JPEG marker is truncated")
    return int.from_bytes(data[offset : offset + 2], "big")


def _segment(data: bytes, offset: int) -> tuple[bytes, int]:
    """Return one bounded length-delimited marker payload and its end."""
    length = read_u16(data, offset)
    if length < 2:
        raise ContractError("JPEG marker length is invalid")
    end = offset + length
    if end > len(data):
        raise ContractError("JPEG marker is truncated")
    return data[offset + 2 : end], end


def _entropy_span(data: bytes, offset: int) -> tuple[int, int]:
    """Find the next marker and count entropy bytes safely."""
    count = 0
    while offset < len(data):
        if data[offset] != 0xFF:
            offset += 1
            count += 1
            continue
        if offset + 1 >= len(data):
            return len(data), count
        code = data[offset + 1]
        if code == 0x00:
            offset += 2
            count += 1
            continue
        if 0xD0 <= code <= 0xD7:
            offset += 2
            continue
        return offset, count
    return offset, count


def parse_jfif(payload: bytes) -> None:
    """Accept only a complete JFIF header without an embedded thumbnail."""
    if len(payload) != 14 or payload[:5] != b"JFIF\x00":
        raise ContractError("JPEG APP0 must be a zero-thumbnail JFIF record")
    if payload[5:7] not in {b"\x01\x00", b"\x01\x01", b"\x01\x02"}:
        raise ContractError("JPEG JFIF version is unsupported")
    if payload[7] > 2:
        raise ContractError("JPEG JFIF density unit is invalid")
    if read_u16(payload, 8) == 0 or read_u16(payload, 10) == 0:
        raise ContractError("JPEG JFIF densities must be positive")
    if payload[-2:] != b"\x00\x00":
        raise ContractError("JPEG JFIF thumbnails are forbidden")


def _parse_frame(payload: bytes) -> tuple[int, int]:
    """Return positive dimensions from one complete JPEG frame header."""
    if len(payload) < 6:
        raise ContractError("JPEG frame header is truncated")
    if payload[0] != 8:
        raise ContractError("JPEG frame precision must be 8-bit")
    component_count = payload[5]
    if component_count == 0 or len(payload) != 6 + 3 * component_count:
        raise ContractError("JPEG frame header length is invalid")
    component_ids: set[int] = set()
    sample_blocks = 0
    for offset in range(6, len(payload), 3):
        component_id = payload[offset]
        if component_id == 0 or component_id in component_ids:
            raise ContractError("JPEG frame component IDs must be unique and nonzero")
        component_ids.add(component_id)
        sampling = payload[offset + 1]
        horizontal = sampling >> 4
        vertical = sampling & 0x0F
        if not 1 <= horizontal <= 4 or not 1 <= vertical <= 4:
            raise ContractError("JPEG frame sampling factors must be between 1 and 4")
        sample_blocks += horizontal * vertical
        if payload[offset + 2] > 3:
            raise ContractError("JPEG frame quantization selector is unsupported")
    if sample_blocks > 10:
        raise ContractError("JPEG frame MCU has too many sample blocks")
    height = read_u16(payload, 1)
    width = read_u16(payload, 3)
    if width == 0 or height == 0:
        raise ContractError("JPEG frame dimensions must be positive")
    return width, height


def _validate_scan_header(payload: bytes, frame_marker: int, frame_components: frozenset[int]) -> None:
    """Require a complete scan header with at least one component."""
    if len(payload) < 4:
        raise ContractError("JPEG scan header is truncated")
    component_count = payload[0]
    if component_count == 0 or len(payload) != 4 + 2 * component_count:
        raise ContractError("JPEG scan header length is invalid")
    selectors = payload[1 : 1 + 2 * component_count : 2]
    if any(selector not in frame_components for selector in selectors):
        raise ContractError("JPEG scan references an unknown frame component")
    if len(selectors) != len(set(selectors)):
        raise ContractError("JPEG scan component selectors are duplicated")
    for table_selector in payload[2 : 1 + 2 * component_count : 2]:
        if table_selector >> 4 > 3 or table_selector & 0x0F > 3:
            raise ContractError("JPEG scan Huffman table selector is unsupported")
    if frame_marker == 0xC0 and payload[-3:] != b"\x00\x3f\x00":
        raise ContractError("JPEG baseline scan fields are invalid")
    if frame_marker == 0xC2:
        _validate_progressive_scan(component_count, payload[-3:])


def _validate_progressive_scan(component_count: int, fields: bytes) -> None:
    """Require legal progressive spectral and approximation fields."""
    spectral_start, spectral_end, approximation = fields
    high = approximation >> 4
    low = approximation & 0x0F
    if spectral_start > spectral_end or spectral_end > 63:
        raise ContractError("JPEG progressive spectral range is invalid")
    if spectral_start == 0 and spectral_end != 0:
        raise ContractError("JPEG progressive DC scan range is invalid")
    if spectral_start > 0 and component_count != 1:
        raise ContractError("JPEG progressive AC scan must have one component")
    if high > 13 or low > 13 or high not in {0, low + 1}:
        raise ContractError("JPEG progressive approximation is invalid")


def _update_progressive_state(payload: bytes, state: dict[tuple[int, int], int]) -> None:
    """Track coefficient initialization and successive approximation."""
    component_count = payload[0]
    components = payload[1 : 1 + 2 * component_count : 2]
    spectral_start, spectral_end, approximation = payload[-3:]
    high = approximation >> 4
    low = approximation & 0x0F
    keys = tuple(
        (component, coefficient)
        for component in components
        for coefficient in range(spectral_start, spectral_end + 1)
    )
    if high == 0 and any(key in state for key in keys):
        raise ContractError("JPEG progressive coefficient is initialized twice")
    if high > 0:
        if any(key not in state for key in keys):
            raise ContractError("JPEG progressive refinement precedes initialization")
        if any(state[key] != high for key in keys):
            raise ContractError("JPEG progressive refinement transition is skipped")
    for key in keys:
        state[key] = low


def _validate_quantization_tables(payload: bytes) -> None:
    """Require complete 8-bit or 16-bit JPEG quantization tables."""
    if not payload:
        raise ContractError("JPEG DQT marker is empty")
    offset = 0
    while offset < len(payload):
        table_info = payload[offset]
        precision = table_info >> 4
        if precision not in {0, 1} or table_info & 0x0F > 3:
            raise ContractError("JPEG DQT table selector is invalid")
        offset += 1 + 64 * (precision + 1)
        if offset > len(payload):
            raise ContractError("JPEG DQT table is truncated")


def _validate_huffman_tables(payload: bytes) -> None:
    """Require complete DC or AC JPEG Huffman tables."""
    if not payload:
        raise ContractError("JPEG DHT marker is empty")
    offset = 0
    while offset < len(payload):
        if offset + 17 > len(payload):
            raise ContractError("JPEG DHT table is truncated")
        table_info = payload[offset]
        table_class = table_info >> 4
        if table_class > 1 or table_info & 0x0F > 3:
            raise ContractError("JPEG DHT table selector is invalid")
        code_counts = payload[offset + 1 : offset + 17]
        available_codes = 1
        for count in code_counts:
            available_codes = 2 * available_codes - count
            if available_codes < 0:
                raise ContractError("JPEG DHT tree is oversubscribed")
        symbol_count = sum(code_counts)
        if symbol_count == 0:
            raise ContractError("JPEG DHT table is empty")
        maximum_symbols = 12 if table_class == 0 else 162
        if symbol_count > maximum_symbols:
            raise ContractError("JPEG DHT has too many symbols")
        offset += 17 + symbol_count
        if offset > len(payload):
            raise ContractError("JPEG DHT symbols are truncated")


def _walk_jpeg(data: bytes) -> tuple[int, int]:
    """Walk bounded JPEG marker segments and return frame dimensions."""
    if not data.startswith(b"\xff\xd8"):
        raise ContractError("JPEG SOI marker is missing")
    offset = 2
    dimensions: tuple[int, int] | None = None
    frame_components: frozenset[int] = frozenset()
    frame_marker: int | None = None
    progressive_state: dict[tuple[int, int], int] = {}
    saw_eoi = False
    saw_jfif = False
    saw_sos = False
    while offset < len(data):
        if data[offset] != 0xFF:
            raise ContractError("JPEG marker prefix is missing")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            raise ContractError("JPEG marker is truncated")
        marker = data[offset]
        offset += 1
        if marker == 0xD9:
            saw_eoi = True
            if data[offset:] == b"\xff\xd9":
                raise ContractError("JPEG EOI marker is duplicated")
            if offset != len(data):
                raise ContractError("JPEG data follows the EOI marker")
            break
        if marker == 0xD8:
            raise ContractError("JPEG SOI marker is duplicated")
        if 0xD0 <= marker <= 0xD7:
            raise ContractError("JPEG restart marker is outside entropy data")
        if 0xE1 <= marker <= 0xEF or marker == 0xFE:
            raise ContractError("JPEG metadata marker is forbidden")
        if marker not in {0xC0, 0xC2, 0xC4, 0xDA, 0xDB, 0xDD, 0xE0}:
            raise ContractError("JPEG marker is not allowed")
        payload, offset = _segment(data, offset)
        if marker in {0xC0, 0xC2}:
            if dimensions is not None:
                raise ContractError("JPEG frame marker is duplicated")
            dimensions = _parse_frame(payload)
            frame_components = frozenset(payload[6::3])
            frame_marker = marker
        elif marker == 0xE0:
            if saw_jfif:
                raise ContractError("JPEG JFIF marker is duplicated")
            parse_jfif(payload)
            saw_jfif = True
        elif marker == 0xDD and len(payload) != 2:
            raise ContractError("JPEG DRI marker length is invalid")
        elif marker == 0xC4:
            _validate_huffman_tables(payload)
        elif marker == 0xDB:
            _validate_quantization_tables(payload)
        elif marker == 0xDA:
            if dimensions is None:
                raise ContractError("JPEG scan precedes the frame header")
            if frame_marker is None:
                raise ContractError("JPEG frame type is missing")
            _validate_scan_header(payload, frame_marker, frame_components)
            if frame_marker == 0xC2:
                _update_progressive_state(payload, progressive_state)
            saw_sos = True
            offset, entropy_count = _entropy_span(data, offset)
            if entropy_count == 0:
                raise ContractError("JPEG entropy data is empty")
    if dimensions is None:
        raise ContractError("JPEG frame is missing")
    if not saw_eoi:
        raise ContractError("JPEG EOI marker is missing")
    if not saw_sos:
        raise ContractError("JPEG SOS marker is missing")
    return dimensions


def minimal_jpeg() -> bytes:
    """Return a minimal structural JPEG fixture with one entropy byte."""
    dqt = b"\xff\xdb\x00\x43\x00" + b"\x01" * 64
    dc_table = b"\x00\x01" + b"\x00" * 15 + b"\x00"
    ac_table = b"\x10\x01" + b"\x00" * 15 + b"\x00"
    dht_payload = dc_table + ac_table
    dht = b"\xff\xc4" + (len(dht_payload) + 2).to_bytes(2, "big") + dht_payload
    return (
        b"\xff\xd8"
        + dqt
        + b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        + dht
        + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        + b"\x01"
        + b"\xff\xd9"
    )


def progressive_jpeg(*scan_fields: bytes) -> bytes:
    """Return a progressive fixture with the requested scan field triples."""
    if not scan_fields:
        raise ValueError("at least one scan is required")
    jpeg = minimal_jpeg().replace(b"\xff\xc0", b"\xff\xc2", 1)
    first_scan = scan_fields[0] + b"\x01\xff\xd9"
    jpeg = jpeg.replace(b"\x00\x3f\x00\x01\xff\xd9", first_scan, 1)
    additional = b"".join(
        b"\xff\xda\x00\x08\x01\x01\x00" + fields + bytes([index + 2])
        for index, fields in enumerate(scan_fields[1:])
    )
    return jpeg[:-2] + additional + b"\xff\xd9"


def jfif_payload(
    version: tuple[int, int] = (1, 1),
    units: int = 0,
    x_density: int = 1,
    y_density: int = 1,
) -> bytes:
    """Return a complete zero-thumbnail JFIF payload."""
    return (
        b"JFIF\x00"
        + bytes((*version, units))
        + x_density.to_bytes(2, "big")
        + y_density.to_bytes(2, "big")
        + b"\x00\x00"
    )


def with_segment(jpeg: bytes, marker: int, payload: bytes) -> bytes:
    """Insert one length-delimited marker immediately after SOI."""
    segment = b"\xff" + bytes([marker]) + (len(payload) + 2).to_bytes(2, "big") + payload
    return jpeg[:2] + segment + jpeg[2:]


class StyleContractTests(unittest.TestCase):
    def setUp(self) -> None:
        """Load the reviewed stylesheet for each source-contract test."""
        self.styles = (ROOT / "site" / "styles.css").read_text(encoding="utf-8")

    def assert_style_rejected(
        self,
        mutated: str,
        validator: Callable[[str], None],
        message: str,
    ) -> None:
        """Require one mutated stylesheet copy to fail its focused validator."""
        self.assertNotEqual(self.styles, mutated)
        with self.assertRaisesRegex(ContractError, message):
            validator(mutated)

    def test_reviewed_tokens_are_used_with_required_contrast(self) -> None:
        _validate_color_contract(self.styles)

    def test_typography_media_and_overflow_foundations(self) -> None:
        _validate_foundation_contract(self.styles)

    def test_figures_fill_their_grid_tracks(self) -> None:
        _validate_figure_margin_contract(self.styles)

    def test_requirements_keep_native_list_markers(self) -> None:
        _validate_requirements_list_contract(self.styles)

    def test_requirements_marker_regressions_are_rejected(self) -> None:
        mutations = {
            "removed-marker": "#requirements ul { list-style: none; }",
            "illegible-marker": "#requirements li::marker { color: #FFF7E8; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "requirements"):
                _validate_requirements_list_contract(f"{self.styles}\n{override}\n")

    def test_keyboard_and_pointer_interactions_are_accessible(self) -> None:
        _validate_interaction_contract(self.styles)

    def test_all_effective_interaction_targets_are_at_least_44px(self) -> None:
        _validate_effective_interaction_targets(self.styles)

    def test_secondary_release_link_has_accessible_target(self) -> None:
        _validate_effective_action_target(self.styles, "secondary-link")

    def test_download_fallback_link_has_accessible_target(self) -> None:
        _validate_effective_action_target(self.styles, "download-fallback")

    def test_editorial_structure_and_responsive_breakpoints(self) -> None:
        _validate_layout_contract(self.styles)
        _validate_effective_responsive_contract(self.styles)

    def test_desktop_hero_heading_keeps_editorial_two_line_measure(self) -> None:
        _validate_effective_heading_contract(self.styles)

    def test_effective_layout_safety_at_reviewed_widths(self) -> None:
        _validate_effective_layout_safety_contract(self.styles)

    def test_motion_and_forbidden_style_contract(self) -> None:
        _validate_forbidden_style_contract(self.styles)

    def test_wrong_color_token_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace("--paper: #F5F0E8;", "--paper: #FFFFFF;", 1)
        self.assert_style_rejected(mutated, _validate_color_contract, "reviewed palette")

    def test_contrast_regression_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace("--button: #B83D31;", "--button: #D9513B;", 1)
        self.assertNotEqual(self.styles, mutated)
        with self.assertRaisesRegex(ContractError, "Windows button contrast"):
            _validate_contrast_contract(parse_style_tokens(mutated))

    def test_effective_download_color_override_mutations_are_rejected(self) -> None:
        mutations = {
            "windows-default": ".download-windows { background: #FFFFFF; }",
            "windows-hover": ".download-windows:hover { background: #FFFFFF; }",
            "macos-default": ".download-macos { color: #FFFFFF; background: #FFFFFF; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "effective .* contrast"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_effective_color_cascade_bypass_mutations_are_rejected(self) -> None:
        mutations = {
            "background-color": ".download-windows { background-color: #FFFFFF; }",
            "scoped-token": ".download-windows { --button: var(--paper); }",
            "body-color": "body { color: #FFFFFF; }",
            "body-background": "body { background: #FFFFFF; }",
            "main-background": "main { background-color: #FFFFFF; }",
            "text-link": "a { color: #FFFFFF; }",
            "macos-hover": ".download-macos:hover { background: #FFFFFF; }",
            "focus-color": ":focus-visible { outline-color: #FFFFFF; }",
            "download-windows-context": (
                ".download-option .download-windows { background-color: #FFFFFF; }"
            ),
            "download-macos-context-hover": (
                ".download-option .download-macos:hover { background: #FFFFFF; }"
            ),
            "text-link-context": ".download-option .download-fallback { color: #FFFFFF; }",
            "focus-context": ".download-option a:focus-visible { outline-color: #FFFFFF; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(
                ContractError,
                "effective color contract|custom properties",
            ):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_missing_focus_visible_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace(":focus-visible {", ":focus {", 1)
        self.assert_style_rejected(mutated, _validate_interaction_contract, "focus-visible")

    def test_small_action_target_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace(
            ".download-primary {\n  min-height: 44px;",
            ".download-primary {\n  min-height: 40px;",
            1,
        )
        self.assert_style_rejected(mutated, _validate_interaction_contract, "at least 44px")

    def test_missing_reduced_motion_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace(
            "@media (prefers-reduced-motion: reduce)",
            "@media (prefers-reduced-motion: no-preference)",
            1,
        )
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "required media query")

    def test_removed_mobile_breakpoint_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace("@media (max-width: 700px)", "@media (max-width: 699px)", 1)
        self.assert_style_rejected(mutated, _validate_layout_contract, "required media query")

    def test_effective_responsive_override_mutations_are_rejected(self) -> None:
        mutations = {
            "display-block": ".hero, #results { display: block; }",
            "narrow-container": ".site-header, main > *, .site-footer { max-width: 640px; }",
            "hero-columns": (
                "@media (min-width: 900px) { "
                ".hero { grid-template-columns: minmax(0, 1fr); } }"
            ),
            "results-columns": (
                "@media (min-width: 900px) { "
                "#results { grid-template-columns: minmax(0, 1fr); } }"
            ),
            "download-columns": (
                "@media (min-width: 701px) { "
                ".download-pair { grid-template-columns: minmax(0, 1fr); } }"
            ),
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "effective responsive"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_unsupported_cascade_mutations_are_rejected(self) -> None:
        mutations = {
            "important": ".hero-copy { display: block !important; }",
            "all": ".hero { all: initial; }",
            "media-union": (
                "@media (min-width: 900px), (max-width: 700px) { "
                ".hero { display: block; } }"
            ),
            "at-property": (
                '@property --button { syntax: "<color>"; inherits: false; '
                "initial-value: #FFFFFF; }"
            ),
            "unmodeled-selector": (
                ".download-option + .download-option .download-macos { background: #FFFFFF; }"
            ),
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "unsupported cascade"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_final_declaration_without_semicolon_is_parsed(self) -> None:
        rules = parse_css_rules("h1 { font-size: 100px }")
        self.assertEqual("100px", rules[0].declarations["font-size"])

    def test_nested_media_context_is_rejected_by_fixed_parser(self) -> None:
        nested = (
            "@media (min-width: 701px) { @media (min-width: 900px) { "
            ".hero { display: grid; } } }"
        )
        with self.assertRaisesRegex(ContractError, "media context"):
            parse_css_rules(nested)

    def test_malformed_and_duplicate_declarations_are_rejected(self) -> None:
        mutations = {
            "unparsed-residue": "h1 { font-size: 74px; malformed }",
            "duplicate-property": "h1 { font-size: 74px; font-size: 74px; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "CSS declaration"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_unmodeled_property_mutations_are_rejected(self) -> None:
        mutations = {
            "font-shorthand": "h1 { font: inherit; }",
            "background-image": "body { background-image: none; }",
            "logical-width": ".hero { inline-size: 2000px; }",
            "transition-longhand": ".hero { transition-duration: 10s; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "unsupported CSS property"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_hidden_overflow_and_color_invariant_mutations_are_rejected(self) -> None:
        mutations = {
            "final-heading-size": "h1 { font-size: 100px }",
            "final-visibility": "h1 { visibility: hidden }",
            "display-none": "h1 { display:none; }",
            "positive-minimum": ".hero { min-width: 2000px; }",
            "heading-color": "h1 { color: #FFF7E8; }",
            "ancestor-background": ".hero { background: #27212B; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_unreviewed_transition_mutations_are_rejected(self) -> None:
        mutations = {
            "long-duration": ".hero { transition: color 10s; }",
            "other-selector": ".secondary-link { transition: color 160ms ease; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "transition"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_reviewed_properties_cannot_be_replayed_in_duplicate_blocks(self) -> None:
        mutations = {
            "figure-margin": ".hero-figure { margin: 40px; }",
            "footer-background": ".site-footer { background: var(--ink); }",
            "hidden-heading": "h1 { height: 0; overflow: clip; }",
            "wide-copy": ".hero-copy { width: 2000px; }",
            "results-gap": "#results { gap: 2000px; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_in_place_selector_vocabulary_regressions_are_rejected(self) -> None:
        mutations = {
            "figure-margin": self.styles.replace(
                ".hero-figure {\n  margin-bottom: 0;",
                ".hero-figure {\n  margin: 40px;",
                1,
            ),
            "footer-background": self.styles.replace(
                ".site-footer {\n  display: flex;",
                ".site-footer {\n  background: var(--ink);\n  display: flex;",
                1,
            ),
            "hidden-heading": self.styles.replace(
                "h1 {\n  max-width: 16ch;",
                "h1 {\n  height: 0;\n  overflow: clip;\n  max-width: 16ch;",
                1,
            ),
            "wide-copy": self.styles.replace(
                ".hero-copy {\n  display: flex;",
                ".hero-copy {\n  width: 2000px;\n  display: flex;",
                1,
            ),
            "results-gap": self.styles.replace(
                "#results {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr);\n  gap: 36px;",
                "#results {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr);\n  gap: 2000px;",
                1,
            ),
        }
        for name, mutated in mutations.items():
            with self.subTest(name=name):
                self.assertNotEqual(self.styles, mutated)
                with self.assertRaises(ContractError):
                    validate_stylesheet(mutated)

    def test_cross_cutting_value_invariant_mutations_are_rejected(self) -> None:
        mutations = {
            "hero-copy-row": self.styles.replace(
                "  flex-direction: column;",
                "  flex-direction: row;",
                1,
            ),
            "how-step-gap": self.styles.replace(
                "  gap: 2px 18px;",
                "  gap: 2000px;",
                1,
            ),
            "explanation-contrast": self.styles.replace(
                ".hero-explanation {\n  max-width: 48ch;\n  margin-bottom: 30px;\n  color: var(--muted);",
                ".hero-explanation {\n  max-width: 48ch;\n  margin-bottom: 30px;\n  color: var(--surface);",
                1,
            ),
            "skip-contrast": self.styles.replace(
                "  background: var(--ink);\n  transform: translateY(-150%);",
                "  background: var(--surface);\n  transform: translateY(-150%);",
                1,
            ),
            "faq-target": self.styles.replace(
                "#faq summary {\n  min-height: 56px;\n  padding-block: 14px;",
                "#faq summary {\n  min-height: 1px;\n  padding-block: 0;",
                1,
            ),
            "caption-size": self.styles.replace(
                "figcaption {\n  margin-top: 12px;\n  color: var(--muted);\n  font-size: 14px;",
                "figcaption {\n  margin-top: 12px;\n  color: var(--muted);\n  font-size: 0;",
                1,
            ),
        }
        for name, mutated in mutations.items():
            with self.subTest(name=name):
                self.assertNotEqual(self.styles, mutated)
                with self.assertRaises(ContractError):
                    validate_stylesheet(mutated)

    def test_css_value_parser_accepts_reviewed_boundaries(self) -> None:
        self.assertEqual((0.0, 24.0), _css_gap_pixels("0 24px", 375))
        self.assertEqual((100.0, 100.0), _css_gap_pixels("100px 100px", 1440))
        self.assertEqual(14.0, _css_font_size_minimum("14px"))
        self.assertEqual(14.0, _css_font_size_minimum("clamp(14px, 2vw, 20px)"))

    def test_unreadable_copy_line_height_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace(
            "  line-height: 1.55;",
            "  line-height: 0;",
            1,
        )
        self.assert_style_rejected(mutated, validate_stylesheet, "line heights")

    def test_gap_clamp_with_oversized_maximum_is_rejected(self) -> None:
        mutated = self.styles.replace(
            "  gap: 12px 28px;",
            "  gap: clamp(0px, 1vw, 2000px);",
            1,
        )
        self.assert_style_rejected(mutated, validate_stylesheet, "gaps")

    def test_heading_line_height_floor_mutations_are_rejected(self) -> None:
        mutations = {
            "h1": self.styles.replace("  line-height: 1.02;", "  line-height: 0.12;", 1),
            "h2": self.styles.replace("  line-height: 1.12;", "  line-height: 0.13;", 1),
            "h3": self.styles.replace(
                "h3 {\n  margin-bottom: 8px;\n  font-size: clamp(20px, 2vw, 24px);\n  line-height: 1.3;",
                "h3 {\n  margin-bottom: 8px;\n  font-size: clamp(20px, 2vw, 24px);\n  line-height: 0.13;",
                1,
            ),
        }
        for name, mutated in mutations.items():
            with self.subTest(name=name):
                self.assertNotEqual(self.styles, mutated)
                with self.assertRaisesRegex(ContractError, "heading line heights"):
                    validate_stylesheet(mutated)

    def test_skip_link_position_and_focus_mutations_are_rejected(self) -> None:
        mutations = {
            "offscreen-left": self.styles.replace("  left: 12px;", "  left: -9999px;", 1),
            "offscreen-top": self.styles.replace("  top: 12px;", "  top: -1px;", 1),
            "low-layer": self.styles.replace("  z-index: 10;", "  z-index: 0;", 1),
            "horizontal-hide": self.styles.replace(
                "  transform: translateY(-150%);",
                "  transform: translateX(-150%);",
                1,
            ),
            "focused-hidden": self.styles.replace(
                ".skip-link:focus {\n  transform: translateY(0);",
                ".skip-link:focus {\n  transform: translateY(-150%);",
                1,
            ),
        }
        for name, mutated in mutations.items():
            with self.subTest(name=name):
                self.assertNotEqual(self.styles, mutated)
                with self.assertRaisesRegex(ContractError, "skip link"):
                    validate_stylesheet(mutated)

    def test_skip_link_zero_position_boundary_stays_on_screen(self) -> None:
        mutated = self.styles.replace("  left: 12px;", "  left: 0;", 1)
        self.assertNotEqual(self.styles, mutated)
        validate_stylesheet(mutated)

    def test_effective_target_override_mutations_are_rejected(self) -> None:
        mutations = {
            "secondary-height": ".secondary-link { min-height: 1px; }",
            "secondary-context-height": ".hero-copy .secondary-link { min-height: 1px; }",
            "fallback-height": ".download-fallback { min-height: 1px; }",
            "fallback-context-height": ".download-option .download-fallback { min-height: 1px; }",
            "heading-size": "h1 { font-size: 100px; }",
            "heading-measure": "h1 { max-width: 8ch; }",
        }
        for name, override in mutations.items():
            with self.subTest(name=name), self.assertRaisesRegex(ContractError, "effective target contract"):
                validate_stylesheet(f"{self.styles}\n{override}\n")

    def test_css_import_mutation_is_rejected(self) -> None:
        mutated = '@import url("https://example.invalid/template.css");\n' + self.styles
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "imports are forbidden")

    def test_backdrop_blur_mutation_is_rejected(self) -> None:
        mutated = ".hero { backdrop-filter: blur(12px); }\n" + self.styles
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "backdrop blur")

    def test_keyframes_mutation_is_rejected(self) -> None:
        mutated = "@keyframes enter { from { opacity: 0; } to { opacity: 1; } }\n" + self.styles
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "keyframe animation")

    def test_page_gradient_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace(
            "background: var(--paper);",
            "background: linear-gradient(#F5F0E8, #FCFAF6);",
            1,
        )
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "background gradients")

    def test_giant_pill_radius_mutation_is_rejected(self) -> None:
        mutated = self.styles.replace("border-radius: 8px;", "border-radius: 999px;", 1)
        self.assert_style_rejected(mutated, _validate_forbidden_style_contract, "pill radii")


class ReadmeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        """Load the README source for each contract test."""
        self.source = README.read_text(encoding="utf-8")

    def test_public_site_link_is_exact_and_unique(self) -> None:
        """Require one exact Pages target with a descriptive link label."""
        _validate_readme_links(self.source)

    def test_root_file_tree_includes_the_site(self) -> None:
        """Require one concise root entry for the dependency-free site."""
        _validate_readme_file_tree(self.source)

    def test_collaborating_includes_the_exact_site_validation_command(self) -> None:
        """Require the reproducible site-suite command in validation context."""
        _validate_readme_collaboration(self.source)

    def test_releases_and_native_installation_content_remains(self) -> None:
        """Protect existing Releases and native installation documentation."""
        _validate_readme_native_content(self.source)

    def test_readme_does_not_copy_landing_page_sections(self) -> None:
        """Keep the README concise instead of duplicating page content."""
        _validate_readme_scope(self.source)
        page = parse_landing_page()
        privacy_paragraphs = [
            child.text()
            for child in page.by_id("privacy")[0].children
            if child.tag == "p" and len(child.text()) >= README_COPY_BLOCK_MIN_LENGTH
        ]
        download_paragraphs = [
            child.text()
            for article in page.nodes("article")
            if "download-option" in (article.attrs.get("class") or "").split()
            for child in article.children
            if child.tag == "p" and len(child.text()) >= README_COPY_BLOCK_MIN_LENGTH
        ]
        _, faq_summaries = _landing_page_readme_copy()
        self.assertTrue(privacy_paragraphs)
        self.assertTrue(download_paragraphs)
        self.assertGreaterEqual(len(faq_summaries), 2)
        mutations = {
            "FAQ heading": f"{self.source}\n## FAQ\n",
            "privacy heading": f"{self.source}\n## Privacy\n",
            "marketing heading": f"{self.source}\n## Give the damage its own space.\n",
            "privacy paragraph": f"{self.source}\n{privacy_paragraphs[0]}\n",
            "download paragraph": f"{self.source}\n{download_paragraphs[0]}\n",
            "FAQ block": f"{self.source}\n{faq_summaries[0]}\n\n{faq_summaries[1]}\n",
        }
        for name, mutated in mutations.items():
            with self.subTest(name=name), self.assertRaises(ReadmeContractError):
                _validate_readme_scope(mutated)

    def test_duplicate_url_and_command_mutations_are_rejected(self) -> None:
        """Reject repeated public URLs and validation commands."""
        mutations = {
            "duplicate URL": (
                _validate_readme_links,
                f"{self.source}\n[ScreenFix website]({README_SITE_URL})\n",
            ),
            "raw duplicate URL": (
                _validate_readme_links,
                f"{self.source}\n{README_SITE_URL}\n",
            ),
            "duplicate command": (
                _validate_readme_collaboration,
                f"{self.source}\n{README_VALIDATION_COMMAND}\n",
            ),
        }
        for name, (validator, mutated) in mutations.items():
            with self.subTest(name=name), self.assertRaises(ReadmeContractError):
                validator(mutated)

    def test_required_source_omissions_are_rejected(self) -> None:
        """Reject omission of the site tree, Releases URL, and native headings."""
        without_site, site_count = README_ROOT_SITE_PATTERN.subn("", self.source, count=1)
        nested_site, nested_count = README_ROOT_SITE_PATTERN.subn(
            "│   ├── site/  Nested unrelated files.",
            self.source,
            count=1,
        )
        self.assertEqual((1, 1), (site_count, nested_count))
        mutations = {
            "missing site URL": (
                _validate_readme_links,
                self.source.replace(f"]({README_SITE_URL})", "](https://example.invalid/)", 1),
            ),
            "missing root site": (_validate_readme_file_tree, without_site),
            "nested site only": (_validate_readme_file_tree, nested_site),
            "missing Releases URL": (
                _validate_readme_native_content,
                self.source.replace(README_RELEASES_URL, "https://example.invalid/releases", 1),
            ),
            "missing Windows heading": (
                _validate_readme_native_content,
                self.source.replace("## Install the native Windows app", "", 1),
            ),
            "missing macOS heading": (
                _validate_readme_native_content,
                self.source.replace("## Install the native macOS app", "", 1),
            ),
        }
        for name, (validator, mutated) in mutations.items():
            self.assertNotEqual(self.source, mutated)
            with self.subTest(name=name), self.assertRaises(ReadmeContractError):
                validator(mutated)

    def test_harmless_documentation_edits_are_accepted(self) -> None:
        """Allow copy, alignment, and collaborator-note changes outside the contract."""
        realigned_tree, replacement_count = README_ROOT_SITE_PATTERN.subn(
            "├── site/  Holds the static landing page.",
            self.source,
            count=1,
        )
        self.assertEqual(1, replacement_count)
        mutations = {
            "website sentence rewording": (
                _validate_readme_links,
                self.source.replace(
                    "The product overview and direct native downloads are also available on the "
                    "[ScreenFix website]",
                    "Explore ScreenFix and get native downloads from the [project website]",
                    1,
                ),
            ),
            "site tree description and alignment": (
                _validate_readme_file_tree,
                realigned_tree,
            ),
            "collaborator GoatCounter mention": (
                _validate_readme_scope,
                f"{self.source}\nCollaborators may discuss GoatCounter changes in review.\n",
            ),
        }
        for name, (validator, mutated) in mutations.items():
            self.assertNotEqual(self.source, mutated)
            with self.subTest(name=name):
                validator(mutated)


class LandingPageContractTests(unittest.TestCase):
    def assert_mutation_rejected(self, old: str, new: str, message: str) -> None:
        """Mutate a temporary page copy and require a specific rejection."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            with self.assertRaisesRegex(ContractError, message):
                validate_landing_page(path)

    def test_exact_site_tree(self) -> None:
        site = ROOT / "site"
        actual = {
            path.relative_to(site).as_posix()
            for path in site.rglob("*")
            if path.is_symlink() or not path.is_dir()
        }
        self.assertEqual(EXPECTED_SITE_FILES, actual)
        for relative_path in EXPECTED_SITE_FILES:
            path = site / relative_path
            status = path.lstat()
            self.assertTrue(stat.S_ISREG(status.st_mode), relative_path)
            if relative_path == ".nojekyll":
                self.assertEqual(0, status.st_size)
            else:
                self.assertGreater(status.st_size, 0, relative_path)
        styles = (site / "styles.css").read_text(encoding="utf-8")
        self.assertIsNone(re.fullmatch(r"\s*/\*.*\*/\s*", styles, re.DOTALL))
        validate_stylesheet(styles)

    def test_document_metadata_landmarks_and_hero(self) -> None:
        page = parse_landing_page()
        self.assertEqual("doctype html", page.doctype)
        html = page.nodes("html")
        self.assertEqual(1, len(html))
        self.assertEqual("en", html[0].attrs.get("lang"))

        metas = page.nodes("meta")
        self.assertTrue(any(meta.attrs.get("charset", "").lower() == "utf-8" for meta in metas))
        self.assertTrue(
            any(
                meta.attrs.get("name") == "viewport"
                and meta.attrs.get("content") == "width=device-width, initial-scale=1"
                for meta in metas
            )
        )
        self.assertTrue(
            any(
                meta.attrs.get("name") == "description"
                and meta.attrs.get("content")
                == "ScreenFix masks a damaged vertical display strip and keeps ordinary windows in the usable space on either side."
                for meta in metas
            )
        )
        self.assertEqual(["ScreenFix — Work around a damaged screen"], [node.text() for node in page.nodes("title")])
        links = page.nodes("link")
        self.assertTrue(any(node.attrs.get("rel") == "canonical" and node.attrs.get("href") == "https://far1h.github.io/ScreenFix/" for node in links))
        self.assertTrue(any(node.attrs.get("rel") == "icon" and node.attrs.get("href") == "assets/screenfix-icon.svg" for node in links))
        self.assertTrue(any(node.attrs.get("rel") == "stylesheet" and node.attrs.get("href") == "styles.css" for node in links))

        for landmark, nodes in page.landmarks.items():
            self.assertEqual(1, len(nodes), landmark)
        main = page.nodes("main")[0]
        self.assertEqual("content", main.attrs.get("id"))
        skip_links = [node for node in page.nodes("a") if "skip-link" in (node.attrs.get("class") or "").split()]
        self.assertEqual([("#content", "Skip to content")], [(node.attrs.get("href"), node.text()) for node in skip_links])

        nav_links = [(node.text(), node.attrs.get("href")) for node in page.nodes("nav")[0].children if node.tag == "a"]
        self.assertEqual(
            [
                ("How it works", "#how"),
                ("Results", "#results"),
                ("Downloads", "#downloads"),
                ("Help", "#faq"),
                ("GitHub", "https://github.com/far1h/ScreenFix"),
            ],
            nav_links,
        )
        brand_images = [node for node in page.nodes("header")[0].children if node.tag == "a" for node in node.children if node.tag == "img"]
        self.assertEqual(1, len(brand_images))
        self.assertEqual("assets/screenfix-icon.svg", brand_images[0].attrs.get("src"))
        self.assertEqual("", brand_images[0].attrs.get("alt"))

        headings = page.nodes("h1")
        self.assertEqual(["Work around a damaged screen."], [heading.text() for heading in headings])
        hero_copy = [node for node in page.elements if "hero-copy" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(hero_copy))
        substantive_children = [child for child in hero_copy[0].children if child.text()]
        self.assertTrue(substantive_children)
        self.assertIs(headings[0], substantive_children[0])
        explanations = [node for node in hero_copy[0].children if "hero-explanation" in (node.attrs.get("class") or "").split()]
        self.assertEqual(
            ["ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works."],
            [node.text() for node in explanations],
        )

    def test_sections_steps_and_project_images(self) -> None:
        page = parse_landing_page()
        section_ids = ("how", "results", "downloads", "privacy", "requirements", "faq")
        self.assertEqual(6, len(page.nodes("section")))
        self.assertEqual(
            list(section_ids),
            [node.attrs["id"] for node in page.nodes("section") if node.attrs.get("id") in section_ids],
        )
        for identifier in section_ids:
            sections = page.by_id(identifier)
            self.assertEqual(1, len(sections), identifier)
            self.assertTrue(any(child.tag == "h2" and child.text() for child in sections[0].children), identifier)

        section_headings = [page.by_id(identifier)[0].children[0].text() for identifier in section_ids]
        self.assertEqual(
            [
                "Give the damage its own space.",
                "What it looks like in use.",
                "Download ScreenFix.",
                "ScreenFix stays on your computer.",
                "Requirements and limits.",
                "Questions before you download.",
            ],
            section_headings,
        )

        how = page.by_id("how")[0]
        steps = [node for node in how.children if node.tag == "article"]
        self.assertEqual(3, len(steps))
        expected_steps = [
            ("1", "Mark the damaged strip.", "Open calibration and drag the guides to mark the damaged strip on the selected display."),
            ("2", "Keep it dark.", "Save the calibration to place an opaque black mask over the damaged strip."),
            ("3", "Use the remaining space.", "ScreenFix keeps ordinary movable windows inside the usable space on either side."),
        ]
        actual_steps = []
        for step in steps:
            number = [node.text() for node in step.children if "step-number" in (node.attrs.get("class") or "").split()]
            heading = [node.text() for node in step.children if node.tag == "h3"]
            copy = [node.text() for node in step.children if node.tag == "p"]
            self.assertEqual((1, 1, 1), (len(number), len(heading), len(copy)))
            actual_steps.append((number[0], heading[0], copy[0]))
        self.assertEqual(expected_steps, actual_steps)

        hero_images = [node for node in page.nodes("img") if node.attrs.get("src") == "assets/damaged-display.jpg"]
        self.assertEqual(1, len(hero_images))
        self.assertEqual(
            {
                "alt": "Damaged display with a dark vertical strip through the screen",
                "width": "1200",
                "height": "900",
                "loading": "eager",
                "fetchpriority": "high",
            },
            {key: hero_images[0].attrs.get(key) for key in ("alt", "width", "height", "loading", "fetchpriority")},
        )

        figures = [node for node in page.by_id("results")[0].children if node.tag == "figure"]
        self.assertEqual(2, len(figures))
        expected_figures = [
            (
                "assets/result-calibration.jpg",
                "Three color bands marking the damaged display strip during calibration",
                "Calibration uses three bands to define the stepped damaged area.",
            ),
            (
                "assets/result-mask.jpg",
                "Black mask covering the saved damaged strip on the display",
                "After saving, an opaque mask keeps the damaged strip dark.",
            ),
        ]
        actual_figures = []
        for figure in figures:
            images = [child for child in figure.children if child.tag == "img"]
            captions = [child for child in figure.children if child.tag == "figcaption"]
            self.assertEqual((1, 1), (len(images), len(captions)))
            image = images[0]
            self.assertEqual(
                ("1200", "675", "lazy", "async"),
                tuple(image.attrs.get(key) for key in ("width", "height", "loading", "decoding")),
            )
            self.assertTrue(image.attrs.get("alt"))
            self.assertTrue(captions[0].text())
            actual_figures.append((image.attrs.get("src"), image.attrs.get("alt"), captions[0].text()))
        self.assertEqual(expected_figures, actual_figures)

    def test_hero_photo_uses_contextual_figure_and_caption(self) -> None:
        page = parse_landing_page()
        hero_figures = [
            node
            for node in page.nodes("figure")
            if "hero-figure" in (node.attrs.get("class") or "").split()
        ]
        self.assertEqual(1, len(hero_figures))
        images = [child for child in hero_figures[0].children if child.tag == "img"]
        captions = [child for child in hero_figures[0].children if child.tag == "figcaption"]
        self.assertEqual(1, len(images))
        self.assertEqual("assets/damaged-display.jpg", images[0].attrs.get("src"))
        self.assertEqual(
            ["The damaged display has a wide broken vertical strip through its center."],
            [caption.text() for caption in captions],
        )
        self.assertEqual(3, len(page.nodes("figure")))

    def test_generic_hero_has_no_aria_name_or_role(self) -> None:
        page = parse_landing_page()
        heroes = [node for node in page.elements if "hero" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(heroes))
        self.assertEqual("div", heroes[0].tag)
        self.assertTrue(
            {"aria-label", "aria-labelledby", "role"}.isdisjoint(heroes[0].attrs)
        )

    def test_native_downloads_are_primary_and_release_links_are_exact(self) -> None:
        page = parse_landing_page()
        windows_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64.exe"
        macos_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-macos-arm64.zip"
        fallback_url = "https://github.com/far1h/ScreenFix/releases/latest/download/ScreenFix-Windows-x64-uncompressed.exe"
        releases_url = "https://github.com/far1h/ScreenFix/releases/latest"

        primary = [node for node in page.nodes("a") if "download-primary" in (node.attrs.get("class") or "").split()]
        self.assertEqual(
            [windows_url, macos_url, windows_url, macos_url],
            [node.attrs.get("href") for node in primary],
        )
        for link in primary:
            self.assertRegex(link.text(), r"Windows x64|macOS Apple Silicon")

        fallback = [node for node in page.nodes("a") if "download-fallback" in (node.attrs.get("class") or "").split()]
        self.assertEqual([(fallback_url, "Windows x64 uncompressed fallback")], [(node.attrs.get("href"), node.text()) for node in fallback])
        release_links = [node for node in page.nodes("a") if node.attrs.get("href") == releases_url]
        self.assertTrue(release_links)
        self.assertIn("Releases and versioned checksums", [node.text() for node in release_links])
        self.assertTrue(all("download-primary" not in (node.attrs.get("class") or "").split() for node in fallback + release_links))

        heroes = [node for node in page.elements if "hero" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(heroes))
        self.assertEqual("div", heroes[0].tag)
        hero = heroes[0]
        hero_links = [node for node in hero.children[0].children if node.tag == "a"]
        self.assertEqual([windows_url, macos_url, releases_url], [node.attrs.get("href") for node in hero_links])

        downloads = page.by_id("downloads")[0]
        pairs = [node for node in downloads.children if "download-pair" in (node.attrs.get("class") or "").split()]
        self.assertEqual(1, len(pairs))
        options = [node for node in pairs[0].children if node.tag == "article"]
        self.assertEqual(["Windows x64", "macOS Apple Silicon"], [node.children[0].text() for node in options])
        windows_copy = options[0].text()
        for phrase in ("Intel or AMD x64 Windows", "self-contained", "no separate .NET runtime", "no ZIP extraction", "SmartScreen", "unsigned", "behavior-identical"):
            self.assertIn(phrase, windows_copy)
        macos_copy = options[1].text()
        for phrase in ("macOS 13 or later", "Apple Silicon", "not Intel", "Control-click", "ad hoc signed", "Accessibility", "automatic window placement", "Masks and calibration continue to work"):
            self.assertIn(phrase, macos_copy)

    def test_privacy_requirements_faq_and_footer_copy(self) -> None:
        page = parse_landing_page()
        privacy = page.by_id("privacy")[0].text()
        for phrase in (
            "does not capture the screen",
            "read window contents",
            "use the network",
            "send telemetry",
            "landing page uses GoatCounter",
            "privacy-friendly aggregate visit measurement",
            "count visits",
            "broad country-level traffic",
            "does not set tracking cookies",
            "briefly process an IP address and user agent in memory",
            "site owner does not receive or retain visitors’ IP addresses",
        ):
            self.assertIn(phrase, privacy)
        self.assertIn("only third-party analytics service used by this website", privacy)
        self.assertIn("does not display a public visit counter", privacy)
        self.assertNotIn("only third-party request", privacy)

        requirements = page.by_id("requirements")[0].text()
        for phrase in (
            "Intel or AMD x64 Windows",
            "macOS 13 or later on Apple Silicon",
            "not Intel Macs",
            "unsigned",
            "SmartScreen",
            "ad hoc signed",
            "not notarized",
            "Gatekeeper",
            "Accessibility permission",
            "physical display damage",
            "ordinary movable windows",
            "ordinary maximized Windows windows",
            "full-screen",
            "administrator",
        ):
            self.assertIn(phrase, requirements)

        questions = [
            "Does ScreenFix repair the damaged panel?",
            "Which windows may remain unchanged?",
            "Why does my operating system warn about ScreenFix?",
            "When does ScreenFix need macOS Accessibility permission?",
        ]
        faq = page.by_id("faq")[0]
        details = [node for node in faq.children if node.tag == "details"]
        self.assertEqual(4, len(details))
        actual_questions = []
        for detail in details:
            summaries = [node for node in detail.children if node.tag == "summary"]
            self.assertEqual(1, len(summaries))
            self.assertIs(detail.children[0], summaries[0])
            self.assertTrue(summaries[0].text())
            answers = [node for node in detail.children[1:] if node.text()]
            self.assertTrue(answers)
            actual_questions.append(summaries[0].text())
        self.assertEqual(questions, actual_questions)

        footer = page.nodes("footer")[0]
        self.assertIn("ScreenFix is an open-source utility for working around a damaged display strip.", footer.text())
        footer_links = [(node.text(), node.attrs.get("href")) for node in footer.children if node.tag == "a"]
        self.assertEqual(
            [
                ("Source", "https://github.com/far1h/ScreenFix"),
                ("Releases", "https://github.com/far1h/ScreenFix/releases/latest"),
                ("Advanced Hammerspoon setup", "https://github.com/far1h/ScreenFix#install-the-hammerspoon-version"),
                ("MIT license", "https://github.com/far1h/ScreenFix/blob/main/LICENSE"),
            ],
            footer_links,
        )
        self.assertEqual(1, sum("Hammerspoon" in text for text in page.visible_text_nodes))

    def test_references_analytics_accessibility_and_marketing_exclusions(self) -> None:
        page = parse_landing_page()
        validate_landing_page(ROOT / "site" / "index.html")
        site = ROOT / "site"
        identifiers = page.ids
        self.assertEqual(len(identifiers), len(set(identifiers)))

        for node in page.elements:
            for attribute in ("href", "src"):
                reference = node.attrs.get(attribute)
                if not reference:
                    continue
                self.assertFalse(reference.startswith("//"), reference)
                parsed = urlsplit(reference)
                if parsed.scheme:
                    self.assertEqual("https", parsed.scheme, reference)
                    continue
                self.assertFalse(parsed.netloc, reference)
                if parsed.path:
                    self.assertNotIn("..", Path(parsed.path).parts, reference)
                    resolved = (site / parsed.path).resolve()
                    self.assertTrue(resolved.is_relative_to(site.resolve()), reference)
                    self.assertTrue(resolved.is_file(), reference)
                if parsed.fragment:
                    self.assertIn(parsed.fragment, identifiers, reference)

        for link in page.links:
            self.assertTrue(link.attrs.get("href"))
            self.assertTrue(link.text() or link.attrs.get("aria-label"))
        for image in page.images:
            self.assertIn("alt", image.attrs)
            if image.attrs.get("src") != "assets/screenfix-icon.svg":
                self.assertTrue(image.attrs.get("alt"))

        scripts = page.scripts
        self.assertEqual(1, len(scripts))
        self.assertIsNotNone(scripts[0].parent)
        self.assertEqual("head", scripts[0].parent.tag)
        self.assertEqual(
            {
                "data-goatcounter": "https://farihmhmd.goatcounter.com/count",
                "async": None,
                "src": "https://gc.zgo.at/count.js",
            },
            scripts[0].attrs,
        )
        self.assertEqual("", scripts[0].text())

        banned_regions = (
            "eyebrow",
            "kicker",
            "trust-strip",
            "statistic-strip",
            "badge-cloud",
            "testimonial",
            "social-proof",
            "visible-counter",
            "glass",
            "glow",
        )
        names = page.class_tokens | {node.attrs.get("id", "") for node in page.elements}
        for name in names:
            self.assertFalse(any(term in name.lower() for term in banned_regions), name)
        standalone_claims = {"Free and MIT licensed", "Runs locally", "No app telemetry"}
        self.assertTrue(standalone_claims.isdisjoint(page.visible_text_nodes))
        visible_copy = " ".join(page.visible_text_nodes).lower()
        for forbidden in ("testimonial", "customer rating", "trusted by", "fake proof"):
            self.assertNotIn(forbidden, visible_copy)

        headings = page.headings
        levels = [int(node.tag[1]) for node in headings]
        self.assertEqual(1, levels[0])
        self.assertTrue(all(current <= previous + 1 for previous, current in zip(levels, levels[1:])))

    def test_eyebrow_before_h1_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<h1 id="hero-title">',
            '<p class="eyebrow">Desktop utility</p>\n          <h1 id="hero-title">',
            "hero heading must be first",
        )

    def test_standalone_trust_claim_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<p class="hero-explanation">ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works.</p>',
            '<p class="hero-explanation">ScreenFix blacks out the broken strip and keeps ordinary windows in the space that still works.</p>\n          <p>Free and MIT licensed</p>',
            "standalone trust claim",
        )

    def test_second_script_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'src="https://gc.zgo.at/count.js"></script>',
            'src="https://gc.zgo.at/count.js"></script>\n    <script src="https://example.com/second.js"></script>',
            "exactly one script",
        )

    def test_protocol_relative_goatcounter_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'src="https://gc.zgo.at/count.js"',
            'src="//gc.zgo.at/count.js"',
            "protocol-relative URL",
        )

    def test_missing_goatcounter_async_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "      async\n",
            "",
            "GoatCounter script attributes",
        )

    def test_wrong_native_filename_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "ScreenFix-Windows-x64.exe",
            "ScreenFix-Windows.exe",
            "native download filename",
        )

    def test_internal_parent_escape_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'href="assets/screenfix-icon.svg"',
            'href="../screenfix-icon.svg"',
            "internal reference escapes",
        )

    def test_duplicate_section_id_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            'id="results" aria-labelledby="results-title"',
            'id="how" aria-labelledby="results-title"',
            "duplicate section ID",
        )

    def test_reordered_faq_mutation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            first_start = source.index("        <details>\n          <summary>Does ScreenFix repair")
            second_start = source.index("        <details>\n          <summary>Which windows")
            third_start = source.index("        <details>\n          <summary>Why does")
            reordered = source[:first_start] + source[second_start:third_start] + source[first_start:second_start] + source[third_start:]
            path.write_text(reordered, encoding="utf-8")
            with self.assertRaisesRegex(ContractError, "FAQ order"):
                validate_landing_page(path)

    def test_empty_faq_summary_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            "<summary>Does ScreenFix repair the damaged panel?</summary>",
            "<summary></summary>",
            "FAQ summary must be non-empty",
        )

    def test_missing_image_alt_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '          alt="Damaged display with a dark vertical strip through the screen"\n',
            "",
            "image alt attribute",
        )

    def test_public_counter_id_mutations_are_rejected(self) -> None:
        mutations = {
            "gc-number": '<span id="gc-number">123 visits</span>',
            "public-counter": '<div id="public-counter">123 visits</div>',
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "public visit counter markup",
                )

    def test_public_counter_class_and_data_mutations_are_rejected(self) -> None:
        mutations = {
            "gc-number-class": '<span class="gc-number"></span>',
            "public-counter-class": '<div class="public-counter"></div>',
            "public-counter-data": '<span data-public-counter="visits"></span>',
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "public visit counter markup",
                )

    def test_rendered_visit_number_mutations_are_rejected(self) -> None:
        mutations = {
            "count-first": "<span>123 visits</span>",
            "label-first": "<strong>Visits: 1,234</strong>",
        }
        for name, markup in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    '    <footer class="site-footer">',
                    f"    {markup}\n    <footer class=\"site-footer\">",
                    "rendered visit number",
                )

    def test_duplicate_html_attribute_mutations_are_rejected(self) -> None:
        mutations = {
            "script-src": (
                'src="https://gc.zgo.at/count.js"',
                'src="http://unsafe.example/count.js" SRC="https://gc.zgo.at/count.js"',
                "src",
            ),
            "anchor-href": (
                'href="https://github.com/far1h/ScreenFix">GitHub',
                'href="../escape" HREF="https://github.com/far1h/ScreenFix">GitHub',
                "href",
            ),
            "image-src": (
                'src="assets/damaged-display.jpg"',
                'src="../escape.jpg" Src="assets/damaged-display.jpg"',
                "src",
            ),
        }
        for name, (old, new, attribute) in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    old,
                    new,
                    f"duplicate HTML attribute: {attribute}",
                )

    def test_required_content_visibility_mutations_are_rejected(self) -> None:
        mutations = {
            "hidden-main": (
                '<main id="content">',
                '<main id="content" hidden>',
            ),
            "aria-hidden-hero-copy": (
                '<div class="hero-copy">',
                '<div class="hero-copy" aria-hidden="true">',
            ),
            "inert-downloads": (
                '<section id="downloads" aria-labelledby="downloads-title">',
                '<section id="downloads" aria-labelledby="downloads-title" inert>',
            ),
        }
        for name, (old, new) in mutations.items():
            with self.subTest(name=name):
                self.assert_mutation_rejected(
                    old,
                    new,
                    "required content must remain visible",
                )

    def test_missing_aria_labelledby_target_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<section id="how" aria-labelledby="how-title">',
            '<section id="how" aria-labelledby="missing-title">',
            "aria-labelledby target must resolve",
        )

    def test_whitespace_aria_label_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '<nav aria-label="Primary navigation">',
            '<nav aria-label="   ">',
            "accessible name attribute must be non-empty",
        )

    def test_link_labelledby_visible_text_is_accepted(self) -> None:
        markup = (
            '<span id="external-link-label">Project mirror</span>\n'
            '    <a href="https://example.com/project" aria-labelledby="external-link-label"></a>'
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            path.write_text(
                source.replace('    <footer class="site-footer">', f"    {markup}\n    <footer class=\"site-footer\">", 1),
                encoding="utf-8",
            )
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"visible aria-labelledby link name was rejected: {error}")

    def test_link_labelledby_hidden_text_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            old = '<a href="https://github.com/far1h/ScreenFix">GitHub</a>'
            new = (
                '<span id="github-link-label" hidden>GitHub repository</span>\n'
                '        <a href="https://github.com/far1h/ScreenFix" '
                'aria-labelledby="github-link-label"></a>'
            )
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"hidden referenced link label was rejected: {error}")

    def test_image_alt_only_link_name_is_accepted(self) -> None:
        markup = (
            '<a href="https://example.com/project">'
            '<img src="assets/screenfix-icon.svg" alt="Project mirror">'
            "</a>"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            path.write_text(
                source.replace('    <footer class="site-footer">', f"    {markup}\n    <footer class=\"site-footer\">", 1),
                encoding="utf-8",
            )
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"image-alt-only link name was rejected: {error}")

    def test_blank_aria_label_with_visible_link_text_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            old = '<a href="https://github.com/far1h/ScreenFix">GitHub</a>'
            new = '<a href="https://github.com/far1h/ScreenFix" aria-label="   ">GitHub</a>'
            self.assertIn(old, source)
            path.write_text(source.replace(old, new, 1), encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"visible link fallback was rejected: {error}")

    def test_unnamed_external_link_mutation_is_rejected(self) -> None:
        self.assert_mutation_rejected(
            '    <footer class="site-footer">',
            '    <a href="https://example.com/project"></a>\n'
            '    <footer class="site-footer">',
            "link accessible names must be descriptive",
        )

    def test_empty_image_alt_is_limited_to_brand_icon(self) -> None:
        self.assert_mutation_rejected(
            '    <footer class="site-footer">',
            '    <img src="assets/screenfix-icon.svg" alt="">\n    <footer class="site-footer">',
            "empty image alt is reserved for the brand icon",
        )

    def test_non_void_self_closing_tag_mutations_are_rejected(self) -> None:
        mutations = {
            "script": (
                'src="https://gc.zgo.at/count.js"></script>',
                'src="https://gc.zgo.at/count.js" />',
            ),
            "div": (
                '    <footer class="site-footer">',
                '    <div class="empty" />\n    <footer class="site-footer">',
            ),
        }
        for tag, (old, new) in mutations.items():
            with self.subTest(tag=tag):
                self.assert_mutation_rejected(
                    old,
                    new,
                    f"self-closing HTML tag is not void: {tag}",
                )

    def test_self_closing_void_image_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "index.html"
            shutil.copyfile(ROOT / "site" / "index.html", path)
            source = path.read_text(encoding="utf-8")
            mutated = source.replace(
                '          >\n          <figcaption>The damaged display',
                '          />\n          <figcaption>The damaged display',
                1,
            )
            self.assertNotEqual(source, mutated)
            path.write_text(mutated, encoding="utf-8")
            try:
                validate_landing_page(path)
            except ContractError as error:
                self.fail(f"self-closing void image was rejected: {error}")


class ImageContractTests(unittest.TestCase):
    def test_oversized_jpeg_path_is_rejected_before_reading(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "oversized.jpg"
            with path.open("wb") as oversized:
                oversized.seek(MAX_IMAGE_BYTES)
                oversized.write(b"\x00")
            with self.assertRaisesRegex(ContractError, "JPEG file exceeds the size limit"):
                parse_jpeg(path)

    def test_directory_jpeg_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            directory = temporary / "directory.jpg"
            directory.mkdir()
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                parse_jpeg(directory)

    def test_symlink_jpeg_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            target = temporary / "target.jpg"
            target.write_bytes(minimal_jpeg())
            symlink = temporary / "symlink.jpg"
            try:
                symlink.symlink_to(target)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation is unavailable: {error}")
            with self.assertRaisesRegex(ContractError, "regular non-symlink"):
                parse_jpeg(symlink)

    def test_svg_animation_elements_are_rejected(self) -> None:
        mutations = {
            "set": (
                b'<svg xmlns="http://www.w3.org/2000/svg">'
                b'<set attributeName="href" to="https://example.invalid"/>'
                b"</svg>"
            ),
            "animate": (
                b'<svg xmlns="http://www.w3.org/2000/svg">'
                b'<animate attributeName="opacity" from="0" to="1"/>'
                b"</svg>"
            ),
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_svg(mutation)

    def test_svg_escaped_css_import_is_rejected(self) -> None:
        unsafe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<style>@\\69mport "https://example.com/site.css";</style>'
            b"</svg>"
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_escaped_css_url_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><rect fill="u\\72l(https://example.com/a)"/></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_style_attribute_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><rect style="fill:#fff"/></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_stylesheet_processing_instruction_is_rejected(self) -> None:
        unsafe = (
            b'<?xml-stylesheet href="https://example.com/site.css" type="text/css"?>'
            b'<svg xmlns="http://www.w3.org/2000/svg"/>'
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_external_css_import_is_rejected(self) -> None:
        unsafe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<style>@import "https://example.com/site.css";</style>'
            b"</svg>"
        )
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_local_fragment_url_is_accepted(self) -> None:
        safe = (
            b'<svg xmlns="http://www.w3.org/2000/svg">'
            b'<defs><linearGradient id="safe"/></defs>'
            b'<rect fill="url(#safe)"/>'
            b"</svg>"
        )
        validate_svg(safe)

    def test_svg_external_css_url_is_rejected(self) -> None:
        unsafe = b'<svg xmlns="http://www.w3.org/2000/svg"><style>.x{fill:url(https://example.com/a)}</style></svg>'
        with self.assertRaises(ContractError):
            validate_svg(unsafe)

    def test_svg_active_content_mutations_are_rejected(self) -> None:
        mutations = {
            "script": b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>',
            "foreignObject": b'<svg xmlns="http://www.w3.org/2000/svg"><foreignObject/></svg>',
            "event": b'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>',
            "href": b'<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/a"/></svg>',
            "src": b'<svg xmlns="http://www.w3.org/2000/svg"><image src="https://example.com/a"/></svg>',
            "namespace": b'<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="urn:example"><x:item/></svg>',
        }
        for name, mutation in mutations.items():
            with self.subTest(name=name), self.assertRaises(ContractError):
                validate_svg(mutation)

    def test_canonical_icon_copy_is_exact_and_script_free(self) -> None:
        site_icon = (ASSETS / "screenfix-icon.svg").read_bytes()
        canonical = (ROOT / "native/macos/Resources/ScreenFixAppIcon.svg").read_bytes()
        self.assertEqual(canonical, site_icon)
        validate_svg(site_icon)

    def test_minimal_jpeg_is_accepted(self) -> None:
        self.assertEqual((1, 1), parse_jpeg(minimal_jpeg()))

    def test_progressive_jpeg_is_accepted(self) -> None:
        self.assertEqual((1, 1), parse_jpeg(progressive_jpeg(b"\x00\x00\x00")))

    def test_progressive_initial_then_refinement_is_accepted(self) -> None:
        valid = progressive_jpeg(b"\x00\x00\x01", b"\x00\x00\x10")
        self.assertEqual((1, 1), parse_jpeg(valid))

    def test_progressive_refinement_before_initial_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x10"))

    def test_progressive_duplicate_initial_coverage_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x00", b"\x00\x00\x00"))

    def test_progressive_skipped_refinement_transition_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(progressive_jpeg(b"\x00\x00\x02", b"\x00\x00\x10"))

    def test_zero_thumbnail_jfif_is_accepted(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        self.assertEqual((1, 1), parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif)))

    def test_jfif_supported_boundary_fields_are_accepted(self) -> None:
        boundary = jfif_payload(version=(1, 2), units=2, x_density=1, y_density=65_535)
        self.assertEqual((1, 1), parse_jpeg(with_segment(minimal_jpeg(), 0xE0, boundary)))

    def test_jfif_version_100_is_accepted(self) -> None:
        try:
            dimensions = parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(version=(1, 0))))
        except ContractError as error:
            self.fail(f"valid JFIF 1.00 record was rejected: {error}")
        self.assertEqual((1, 1), dimensions)

    def test_jfif_version_is_validated(self) -> None:
        for version in ((0, 99), (1, 3), (2, 0)):
            with self.subTest(version=version), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(version=version)))

    def test_jfif_density_unit_is_validated(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif_payload(units=3)))

    def test_jfif_densities_must_be_positive(self) -> None:
        for densities in ((0, 1), (1, 0)):
            payload = jfif_payload(x_density=densities[0], y_density=densities[1])
            with self.subTest(densities=densities), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xE0, payload))

    def test_stuffed_entropy_and_restart_markers_are_accepted(self) -> None:
        entropy = b"\x01\xff\x00\xe1\xff\xd0\x02"
        mutated = minimal_jpeg().replace(b"\x01\xff\xd9", entropy + b"\xff\xd9", 1)
        self.assertEqual((1, 1), parse_jpeg(mutated))

    def test_restart_marker_outside_entropy_is_rejected(self) -> None:
        misplaced = minimal_jpeg()[:2] + b"\xff\xd0" + minimal_jpeg()[2:]
        with self.assertRaises(ContractError):
            parse_jpeg(misplaced)

    def test_malformed_marker_length_is_rejected(self) -> None:
        malformed = minimal_jpeg().replace(b"\xff\xdb\x00\x43", b"\xff\xdb\x00\x01", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(malformed)

    def test_app1_exif_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE1, b"Exif\x00\x00"))

    def test_app2_icc_profile_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE2, b"ICC_PROFILE\x00"))

    def test_app13_iptc_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xED, b"Photoshop 3.0\x00"))

    def test_app14_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xEE, b"Adobe"))

    def test_all_other_app_markers_are_rejected(self) -> None:
        for marker in (*range(0xE3, 0xED), 0xEF):
            with self.subTest(marker=marker), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), marker, b"metadata"))

    def test_comment_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xFE, b"comment"))

    def test_jfif_thumbnail_is_rejected(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x01\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xE0, jfif))

    def test_missing_eoi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:-2])

    def test_duplicate_eoi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg() + b"\xff\xd9")

    def test_bytes_after_eoi_are_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg() + b"trailing")

    def test_missing_soi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(b"\x00\x00" + minimal_jpeg()[2:])

    def test_duplicate_sof_is_rejected(self) -> None:
        frame = b"\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC0, frame))

    def test_zero_frame_dimension_is_rejected(self) -> None:
        zero_width = minimal_jpeg().replace(b"\x08\x00\x01\x00\x01", b"\x08\x00\x01\x00\x00", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(zero_width)

    def test_non_eight_bit_frame_precision_is_rejected(self) -> None:
        invalid = minimal_jpeg().replace(b"\xff\xc0\x00\x0b\x08", b"\xff\xc0\x00\x0b\x0c", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_zero_frame_sampling_factor_is_rejected(self) -> None:
        for sampling in (b"\x10", b"\x01"):
            invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_sampling_factor_four_is_accepted(self) -> None:
        for sampling in (b"\x41", b"\x14"):
            boundary = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling):
                self.assertEqual((1, 1), parse_jpeg(boundary))

    def test_frame_sampling_factor_five_is_rejected(self) -> None:
        for sampling in (b"\x51", b"\x15"):
            invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01" + sampling + b"\x00", 1)
            with self.subTest(sampling=sampling), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_mcu_sample_block_total_is_bounded(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        oversized = b"\xff\xc0\x00\x11\x08\x00\x01\x00\x01\x03\x01\x22\x00\x02\x22\x00\x03\x22\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(frame, oversized, 1))

    def test_frame_component_ids_must_be_unique_and_nonzero(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        zero_id = frame[:-3] + b"\x00\x11\x00"
        duplicate_id = b"\xff\xc0\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x01\x11\x00"
        for name, invalid_frame in {"zero": zero_id, "duplicate": duplicate_id}.items():
            invalid = minimal_jpeg().replace(frame, invalid_frame, 1)
            with self.subTest(name=name), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_frame_quantization_selector_must_be_supported(self) -> None:
        invalid = minimal_jpeg().replace(b"\x01\x11\x00", b"\x01\x11\x04", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_missing_sos_is_rejected(self) -> None:
        no_scan = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x01", b"", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(no_scan)

    def test_empty_entropy_data_is_rejected(self) -> None:
        empty_scan = minimal_jpeg().replace(b"\x3f\x00\x01\xff\xd9", b"\x3f\x00\xff\xd9", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(empty_scan)

    def test_unlisted_structural_marker_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDC, b"\x00\x01"))

    def test_duplicate_soi_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:2] + b"\xff\xd8" + minimal_jpeg()[2:])

    def test_duplicate_jfif_is_rejected(self) -> None:
        jfif = b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        duplicate = with_segment(with_segment(minimal_jpeg(), 0xE0, jfif), 0xE0, jfif)
        with self.assertRaises(ContractError):
            parse_jpeg(duplicate)

    def test_malformed_sof_length_is_rejected(self) -> None:
        valid_frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        short_frame = b"\xff\xc0\x00\x07\x08\x00\x01\x00\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(valid_frame, short_frame, 1))

    def test_malformed_sos_length_is_rejected(self) -> None:
        valid_scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        malformed_scan = b"\xff\xda\x00\x06\x00\x00\x3f\x00"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg().replace(valid_scan, malformed_scan, 1))

    def test_baseline_scan_spectral_selection_is_validated(self) -> None:
        invalid = minimal_jpeg().replace(b"\x00\x3f\x00\x01\xff\xd9", b"\x01\x3f\x00\x01\xff\xd9", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_selector_must_reference_frame_component(self) -> None:
        invalid = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00", b"\xff\xda\x00\x08\x01\x02\x00", 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_component_selectors_must_be_unique(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        two_component_frame = b"\xff\xc0\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x02\x11\x00"
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        duplicate_scan = b"\xff\xda\x00\x0a\x02\x01\x00\x01\x00\x00\x3f\x00"
        invalid = minimal_jpeg().replace(frame, two_component_frame, 1).replace(scan, duplicate_scan, 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_scan_huffman_table_selectors_must_be_supported(self) -> None:
        for tables in (b"\x40", b"\x04"):
            invalid = minimal_jpeg().replace(b"\xff\xda\x00\x08\x01\x01\x00", b"\xff\xda\x00\x08\x01\x01" + tables, 1)
            with self.subTest(tables=tables), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_progressive_scan_fields_are_validated(self) -> None:
        progressive = minimal_jpeg().replace(b"\xff\xc0", b"\xff\xc2", 1)
        invalid_fields = {
            "dc_end": b"\x00\x01\x00",
            "spectral_order": b"\x05\x04\x00",
            "approximation_low": b"\x01\x3f\x0e",
            "approximation_high": b"\x01\x3f\xe0",
            "approximation_step": b"\x01\x3f\x20",
        }
        for name, fields in invalid_fields.items():
            invalid = progressive.replace(b"\x00\x3f\x00\x01\xff\xd9", fields + b"\x01\xff\xd9", 1)
            with self.subTest(name=name), self.assertRaises(ContractError):
                parse_jpeg(invalid)

    def test_progressive_ac_scan_has_one_component(self) -> None:
        frame = b"\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
        progressive_frame = b"\xff\xc2\x00\x0e\x08\x00\x01\x00\x01\x02\x01\x11\x00\x02\x11\x00"
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00"
        ac_scan = b"\xff\xda\x00\x0a\x02\x01\x00\x02\x00\x01\x3f\x00"
        invalid = minimal_jpeg().replace(frame, progressive_frame, 1).replace(scan, ac_scan, 1)
        with self.assertRaises(ContractError):
            parse_jpeg(invalid)

    def test_malformed_dri_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDD, b""))

    def test_malformed_dqt_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xDB, b""))

    def test_malformed_dht_length_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, b""))

    def test_oversubscribed_huffman_tree_is_rejected(self) -> None:
        payload = b"\x00\x03" + b"\x00" * 15 + b"\x00\x01\x02"
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, payload))

    def test_excessive_huffman_symbol_count_is_rejected(self) -> None:
        dc_counts = b"\x00" * 3 + b"\x0d" + b"\x00" * 12
        ac_counts = b"\x00" * 7 + b"\xa3" + b"\x00" * 8
        payloads = {
            "dc": b"\x00" + dc_counts + bytes(range(13)),
            "ac": b"\x10" + ac_counts + bytes(range(163)),
        }
        for table_class, payload in payloads.items():
            with self.subTest(table_class=table_class), self.assertRaises(ContractError):
                parse_jpeg(with_segment(minimal_jpeg(), 0xC4, payload))

    def test_empty_huffman_table_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_jpeg(with_segment(minimal_jpeg(), 0xC4, b"\x00" * 17))

    def test_sos_before_sof_is_rejected(self) -> None:
        scan = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x01"
        with self.assertRaises(ContractError):
            parse_jpeg(minimal_jpeg()[:2] + scan + minimal_jpeg()[2:])

    def test_sanitized_jpegs_have_exact_dimensions_and_budgets(self) -> None:
        total = 0
        for name, dimensions in EXPECTED_IMAGES.items():
            path = ASSETS / name
            self.assertTrue(path.is_file() and not path.is_symlink())
            self.assertEqual(dimensions, parse_jpeg(path))
            size = path.stat().st_size
            total += size
        self.assertLessEqual(total, MAX_TOTAL_IMAGE_BYTES)

    def test_sanitized_illustrations_have_exact_dimensions_and_budgets(self) -> None:
        total = 0
        for name, dimensions in EXPECTED_ILLUSTRATIONS.items():
            path = ASSETS / name
            path_status = path.lstat()
            self.assertTrue(stat.S_ISREG(path_status.st_mode), name)
            self.assertEqual(dimensions, parse_jpeg(path))
            self.assertLessEqual(path_status.st_size, MAX_ILLUSTRATION_BYTES, name)
            total += path_status.st_size
        self.assertLessEqual(total, MAX_ILLUSTRATION_TOTAL_BYTES)

    def test_all_jpegs_stay_within_the_combined_budget(self) -> None:
        names = EXPECTED_IMAGES.keys() | EXPECTED_ILLUSTRATIONS.keys()
        total = sum((ASSETS / name).lstat().st_size for name in names)
        self.assertLessEqual(total, MAX_ALL_JPEG_BYTES)


class PagesWorkflowContractTests(unittest.TestCase):
    """Protect the least-privilege GitHub Pages delivery workflow."""

    def _source(self) -> str:
        """Return the checked-in Pages workflow source."""
        return PAGES_WORKFLOW.read_text(encoding="utf-8")

    def _mutation(self, old: str, new: str) -> str:
        """Apply one controlled source mutation to the valid workflow."""
        source = self._source()
        self.assertIn(old, source, f"mutation anchor must exist: {old!r}")
        return source.replace(old, new, 1)

    def _assert_mutations_rejected(self, mutations: dict[str, str]) -> None:
        """Require every named invalid workflow mutation to fail validation."""
        for name, source in mutations.items():
            with self.subTest(mutation=name), self.assertRaises(WorkflowContractError):
                validate_pages_workflow(source)

    def test_pages_workflow_exists(self) -> None:
        """Require the repository to define its Pages workflow."""
        self.assertTrue(PAGES_WORKFLOW.is_file(), f"missing {PAGES_WORKFLOW.relative_to(ROOT)}")

    def test_pages_workflow_satisfies_contract(self) -> None:
        """Require the checked-in workflow to satisfy the delivery contract."""
        validate_pages_workflow(self._source())

    def test_concurrency_groups_partition_prs_from_deployments(self) -> None:
        """Keep each PR queue isolated from the shared deployment queue."""
        approved = PAGES_CONCURRENCY_GROUP
        source = self._source()
        top = _workflow_mapping(_workflow_lines(source), "top-level")
        concurrency = _workflow_mapping(top["concurrency"].children, "concurrency")
        group = concurrency["group"].value

        def resolve(event_name: str, pull_request_number: int | None = None) -> str:
            """Evaluate only the approved concurrency partition expression."""
            if group != approved:
                return group
            if event_name == "pull_request":
                return f"screenfix-pages-pr-{pull_request_number}"
            return "screenfix-pages-deploy"

        pr_12 = resolve("pull_request", 12)
        pr_13 = resolve("pull_request", 13)
        push = resolve("push")
        manual = resolve("workflow_dispatch")
        self.assertEqual("screenfix-pages-pr-12", pr_12)
        self.assertEqual("screenfix-pages-pr-13", pr_13)
        self.assertNotEqual(pr_12, pr_13)
        self.assertEqual("screenfix-pages-deploy", push)
        self.assertEqual(push, manual)
        self.assertNotIn(push, {pr_12, pr_13})
        self.assertEqual("false", concurrency["cancel-in-progress"].value)

        approved_source = source.replace(f"  group: {group}", f"  group: {approved}", 1)
        validate_pages_workflow(approved_source)
        self._assert_mutations_rejected(
            {
                "constant group": approved_source.replace(
                    f"  group: {approved}",
                    "  group: screenfix-pages",
                    1,
                ),
                "broadened PR group": approved_source.replace(
                    f"  group: {approved}",
                    "  group: ${{ github.event_name == 'pull_request' && "
                    "'screenfix-pages-pr' || 'screenfix-pages-deploy' }}",
                    1,
                ),
                "ref-only group": approved_source.replace(
                    f"  group: {approved}",
                    "  group: ${{ format('screenfix-pages-{0}', github.ref) }}",
                    1,
                ),
            }
        )

    def test_trigger_mutations_are_rejected(self) -> None:
        """Reject filtered or broadened workflow triggers."""
        self._assert_mutations_rejected(
            {
                "pull request paths": self._mutation(
                    "  pull_request: {}",
                    "  pull_request:\n    paths:\n      - site/**",
                ),
                "pull request paths ignored": self._mutation(
                    "  pull_request: {}",
                    "  pull_request:\n    paths-ignore:\n      - docs/**",
                ),
                "non-main push": self._mutation("      - main", "      - develop"),
                "pull request target": self._mutation(
                    "  pull_request: {}",
                    "  pull_request_target: {}",
                ),
            }
        )

    def test_checkout_mutations_are_rejected(self) -> None:
        """Reject unsafe or incorrectly pinned checkout steps."""
        first_ref = "          ref: ${{ github.event.pull_request.head.sha || github.sha }}"
        first_credentials = "          persist-credentials: false"
        self._assert_mutations_rejected(
            {
                "missing ref": self._mutation(first_ref, "          ref: ${{ github.sha }}"),
                "missing credential protection": self._mutation(
                    first_credentials,
                    "          persist-credentials: true",
                ),
                "wrong checkout major": self._mutation(
                    "        uses: actions/checkout@v7\n        with:",
                    "        uses: actions/checkout@v6\n        with:",
                ),
            }
        )

    def test_dependency_and_permission_mutations_are_rejected(self) -> None:
        """Reject broadened privileges and broken job dependencies."""
        self._assert_mutations_rejected(
            {
                "publish missing validate dependency": self._mutation(
                    "  publish:\n    needs: validate\n",
                    "  publish:\n",
                ),
                "publish lacks pages read": self._mutation("      pages: read", "      pages: none"),
                "deploy missing publish dependency": self._mutation(
                    "  deploy:\n    needs: publish\n",
                    "  deploy:\n",
                ),
                "deploy gets contents": self._mutation(
                    "      id-token: write\n    environment:",
                    "      id-token: write\n      contents: read\n    environment:",
                ),
                "validate gets pages write": self._mutation(
                    "  validate:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read",
                    "  validate:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n      pages: write",
                ),
                "publish gets oidc write": self._mutation(
                    "      pages: read\n    steps:",
                    "      pages: read\n      id-token: write\n    steps:",
                ),
                "contents write": self._mutation(
                    "permissions:\n  contents: read",
                    "permissions:\n  contents: write",
                ),
            }
        )

    def test_action_and_archive_mutations_are_rejected(self) -> None:
        """Reject wrong actions, incomplete validation, and wrong upload inputs."""
        validate_test = "        run: python3 -m unittest discover -s tests/site -p 'test_*.py' -v"
        validate_tar = '          tar --dereference --hard-dereference --directory site -cf "$validation_archive" .'
        validate_inspection = '          tar -tf "$validation_archive" | sed'
        publish_inspection = '          tar -tf "$RUNNER_TEMP/artifact.tar" | sed'
        self._assert_mutations_rejected(
            {
                "validate missing tests": self._mutation(
                    validate_test,
                    "        run: python3 -m unittest -v",
                ),
                "validate missing equivalent tar": self._mutation(
                    validate_tar,
                    '          tar --directory site -cf "$validation_archive" .',
                ),
                "validate missing archive inspection": self._mutation(
                    validate_inspection,
                    '          printf \'not inspected\\n\' | sed',
                ),
                "publish missing actual artifact inspection": self._mutation(
                    publish_inspection,
                    '          printf \'not inspected\\n\' | sed',
                ),
                "wrong configure major": self._mutation(
                    "actions/configure-pages@v6",
                    "actions/configure-pages@v5",
                ),
                "wrong upload major": self._mutation(
                    "actions/upload-pages-artifact@v5",
                    "actions/upload-pages-artifact@v4",
                ),
                "hidden files omitted": self._mutation(
                    "          include-hidden-files: true\n",
                    "",
                ),
                "hidden files disabled": self._mutation(
                    "          include-hidden-files: true",
                    "          include-hidden-files: false",
                ),
                "wrong upload path": self._mutation("          path: site", "          path: dist"),
            }
        )

    def test_deploy_mutations_are_rejected(self) -> None:
        """Reject broadened deployment conditions and incomplete environment wiring."""
        exact_condition = (
            "    if: github.ref == 'refs/heads/main' && "
            "(github.event_name == 'push' || github.event_name == 'workflow_dispatch')"
        )
        self._assert_mutations_rejected(
            {
                "broadened publish condition": self._mutation(
                    exact_condition + "\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read",
                    "    if: github.ref == 'refs/heads/main'\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read",
                ),
                "missing github-pages environment": self._mutation("      name: github-pages\n", ""),
                "missing environment url": self._mutation(
                    "      url: ${{ steps.deployment.outputs.page_url }}\n",
                    "",
                ),
                "missing deployment id": self._mutation("        id: deployment\n", ""),
                "broadened deploy condition": self._mutation(
                    "  deploy:\n    needs: publish\n" + exact_condition,
                    "  deploy:\n    needs: publish\n    if: github.ref == 'refs/heads/main'",
                ),
                "wrong deploy major": self._mutation("actions/deploy-pages@v5", "actions/deploy-pages@v4"),
            }
        )

    def test_adversarial_duplicates_and_secrets_are_rejected(self) -> None:
        """Reject duplicates that could conceal an unsafe earlier definition."""
        self._assert_mutations_rejected(
            {
                "duplicate top key": self._mutation(
                    "name: ScreenFix Pages",
                    "name: Unsafe Pages\nname: ScreenFix Pages",
                ),
                "duplicate job": self._mutation(
                    "jobs:\n  validate:",
                    "jobs:\n  validate:\n    runs-on: ubuntu-latest\n  validate:",
                ),
                "duplicate action": self._mutation(
                    "        uses: actions/checkout@v7\n        with:",
                    "        uses: untrusted/checkout@v1\n        uses: actions/checkout@v7\n        with:",
                ),
                "secret reference": self._mutation(
                    "          persist-credentials: false",
                    "          persist-credentials: ${{ secrets.PAGES_TOKEN }}",
                ),
            }
        )
