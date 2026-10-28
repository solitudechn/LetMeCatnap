#!/usr/bin/env python3
"""Localization guard for the bilingual string table.

The table itself is type-checked by the compiler and unit-tested by
`Tests/ICHRCoreTests/StringTableTests.swift`. This script covers what neither
can see — source text that never goes through `L10n` at all — plus a couple of
cheap structural checks so the failure is reported in CI even if XCTest is
unavailable.

Fails when:
  1. a `LocKey` case has no entry in `StringTable.table`;
  2. `L10n.t(.foo)` references a case that does not exist;
  3. a UI file builds a visible string from a bare literal;
  4. the two break-tip arrays drifted apart in length.

Run from the repository root: `python3 scripts/check-l10n.py`
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
CORE = ROOT / "core"
KEYS = CORE / "L10n.swift"
TABLE = CORE / "StringTable.swift"

CJK = re.compile(r"[\u4e00-\u9fff]")

# Visible-string constructors that must never take a bare literal.
UI_PATTERNS = [
    r'Text\(\s*"((?:[^"\\]|\\.)*)"',
    r'labelWithString:\s*"((?:[^"\\]|\\.)*)"',
    r'wrappingLabelWithString:\s*"((?:[^"\\]|\\.)*)"',
    r'NSMenuItem\(title:\s*"((?:[^"\\]|\\.)*)"',
    r'messageText\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'informativeText\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'\.title\s*=\s*"((?:[^"\\]|\\.)*)"',
    r'Button\(\s*"((?:[^"\\]|\\.)*)"',
]


def allowed_literal(literal: str) -> bool:
    """Literals that are intentionally not localized.

    Empty placeholders, strings that are only whitespace plus interpolation (the
    menu bar countdown prefix, whose text comes from `L10n`), and key names like
    `"SUFeedURL"` that are configuration rather than copy.
    """
    if literal.strip() == "":
        return True
    if re.fullmatch(r"\s*\\\(.*\)", literal) is not None:
        return True
    return literal.startswith(("SU", "NS", "CF"))


def main() -> int:
    failures: list[str] = []

    keys_source = KEYS.read_text()
    table_source = TABLE.read_text()

    cases = set(re.findall(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", keys_source, re.MULTILINE))
    entries = set(re.findall(r"^\s*\.([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Translation\(", table_source, re.MULTILINE))

    for missing in sorted(cases - entries):
        failures.append(f"LocKey.{missing} has no entry in StringTable")
    for orphan in sorted(entries - cases):
        failures.append(f"StringTable has an entry for unknown key .{orphan}")

    for path in sorted(SRC.glob("*.swift")):
        text = path.read_text()
        for pattern in UI_PATTERNS:
            for match in re.finditer(pattern, text):
                literal = match.group(1)
                if allowed_literal(literal):
                    continue
                failures.append(f"{path.name}: hardcoded UI string {literal!r}")
        for key in re.findall(r"L10n\.t\(\.([A-Za-z_][A-Za-z0-9_]*)", text):
            if key not in cases:
                failures.append(f"{path.name}: L10n.t(.{key}) has no LocKey case")

    # Every tip must exist in both languages. Only the `breakTips` block is
    # looked at — `Translation("en", "zh")` pairs above it are already covered by
    # the key/entry check and by the unit tests.
    marker = "static let breakTips"
    tips_block = table_source.split(marker, 1)[1] if marker in table_source else ""
    tips = re.findall(r'\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)', tips_block)
    if not tips:
        failures.append("no break tips found in StringTable")
    for en, zh in tips:
        if not en.strip() or not zh.strip():
            failures.append(f"empty break tip: {en!r} / {zh!r}")
        elif not CJK.search(zh):
            failures.append(f"break tip is not translated: {en!r}")

    if failures:
        print(f"check-l10n: {len(failures)} problem(s)")
        for failure in failures:
            print("  -", failure)
        return 1

    print(
        f"check-l10n: OK ({len(cases)} keys, {len(tips)} break tips, "
        f"{len(list(SRC.glob('*.swift')))} UI files scanned)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
