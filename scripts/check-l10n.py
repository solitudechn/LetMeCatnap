#!/usr/bin/env python3
"""Localization guard for src/L10n.swift.

Fails when:
  1. a bilingual pair has an empty side, or the Chinese side has no CJK text
     (i.e. someone added a key and forgot to translate it);
  2. the English side contains CJK characters (copy/paste slip);
  3. a UI file builds a visible string without going through L10n;
  4. code references an `L10n.foo` that does not exist.

Run from the repository root: `python3 scripts/check-l10n.py`
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
L10N = SRC / "L10n.swift"

CJK = re.compile(r"[\u4e00-\u9fff]")

# Files that render text on screen.
UI_FILES = [
    "BreakOverlayView.swift",
    "CompactBreakOverlayView.swift",
    "AppDelegate.swift",
    "AboutViewController.swift",
    "UpdateDialogViewController.swift",
    "TimerManager.swift",
]

# Visible-string constructors that must never take a bare literal.
UI_PATTERNS = [
    r'Text\(\s*"((?:[^"\\]|\\.)*)"',
    r"labelWithString:\s*\"((?:[^\"\\]|\\.)*)\"",
    r"wrappingLabelWithString:\s*\"((?:[^\"\\]|\\.)*)\"",
    r'NSMenuItem\(title:\s*"((?:[^"\\]|\\.)*)"',
    r'messageText\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'informativeText\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'\.title\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'Button\(\s*"((?:[^"\\]|\\.)*)"',
]

# Literals that are intentionally not localized: empty placeholders, and
# strings that are only whitespace plus interpolation (the menu bar countdown
# prefix, whose text comes from L10n).
def allowed_literal(literal: str) -> bool:
    if literal.strip() == "":
        return True
    return re.fullmatch(r"\s*\\\(.*\)", literal) is not None


def main() -> int:
    source = L10N.read_text()
    failures: list[str] = []

    pairs = re.findall(
        r't\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)', source
    )
    for en, zh in pairs:
        if not en.strip() or not zh.strip():
            failures.append(f"empty translation pair: {en!r} / {zh!r}")
        elif not CJK.search(zh):
            failures.append(f"Chinese side has no CJK text: {en!r} / {zh!r}")
        if CJK.search(en):
            failures.append(f"English side contains Chinese: {en!r}")

    for name in UI_FILES:
        path = SRC / name
        if not path.exists():
            continue
        text = path.read_text()
        for pattern in UI_PATTERNS:
            for match in re.finditer(pattern, text):
                literal = match.group(1)
                if allowed_literal(literal):
                    continue
                failures.append(f"{name}: hardcoded UI string {literal!r}")

    defined = set(
        re.findall(r"static\s+(?:var|func|let)\s+([A-Za-z_][A-Za-z0-9_]*)", source)
    ) | {"Language"}
    used: set[str] = set()
    for path in SRC.glob("*.swift"):
        if path.name == "L10n.swift":
            continue
        used.update(re.findall(r"\bL10n\.([A-Za-z_][A-Za-z0-9_]*)", path.read_text()))
    for key in sorted(used - defined):
        failures.append(f"L10n.{key} is referenced but not defined")

    if failures:
        print(f"check-l10n: {len(failures)} problem(s)")
        for failure in failures:
            print("  -", failure)
        return 1

    print(f"check-l10n: OK ({len(pairs)} bilingual pairs, {len(used)} references)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
