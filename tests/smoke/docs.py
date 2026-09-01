#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
DOCS = [ROOT / "README.md", ROOT / "CONTRIBUTING.md"]
DOCS.extend(sorted((ROOT / "docs").rglob("*.md")))
LINK_PATTERN = re.compile(r"(?<!!)\[[^]]*]\(([^)]+)\)")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
LIST_PATTERN = re.compile(r"^\s*(?:[-+*]|\d+\.)\s+")


def github_anchor(heading: str) -> str:
    heading = re.sub(r"<[^>]+>", "", heading)
    heading = heading.replace("`", "").strip().lower()
    heading = re.sub(r"[^\w\- ]", "", heading)
    return re.sub(r"\s+", "-", heading)


def headings(path: Path) -> set[str]:
    result: set[str] = set()
    in_fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING_PATTERN.match(line)
        if match:
            result.add(github_anchor(match.group(2)))
    return result


def link_target(raw: str) -> tuple[str, str]:
    value = raw.strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1]
    path, separator, fragment = value.partition("#")
    return unquote(path), unquote(fragment) if separator else ""


def check_document(path: Path) -> list[str]:
    errors: list[str] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    in_fence = False
    previous_heading = 0
    h1_count = 0
    paragraph_start = 0
    paragraph_lines = 0

    def finish_paragraph() -> None:
        nonlocal paragraph_start, paragraph_lines
        if paragraph_lines > 4:
            errors.append(
                f"{path.relative_to(ROOT)}:{paragraph_start}: "
                f"paragraph spans {paragraph_lines} lines"
            )
        paragraph_start = 0
        paragraph_lines = 0

    for number, line in enumerate(lines, start=1):
        if line.startswith("```"):
            finish_paragraph()
            if not in_fence and line == "```":
                errors.append(
                    f"{path.relative_to(ROOT)}:{number}: code fence needs a language"
                )
            in_fence = not in_fence
            continue

        if in_fence:
            continue

        if len(line) > 100:
            errors.append(
                f"{path.relative_to(ROOT)}:{number}: line exceeds 100 characters"
            )

        heading = HEADING_PATTERN.match(line)
        if heading:
            finish_paragraph()
            level = len(heading.group(1))
            if level == 1:
                h1_count += 1
            if previous_heading and level > previous_heading + 1:
                errors.append(
                    f"{path.relative_to(ROOT)}:{number}: heading level jumps "
                    f"from {previous_heading} to {level}"
                )
            previous_heading = level
            continue

        structural = (
            not line.strip()
            or LIST_PATTERN.match(line)
            or line.startswith((">", "|", "    ", "\t"))
        )
        if structural:
            finish_paragraph()
        else:
            if paragraph_lines == 0:
                paragraph_start = number
            paragraph_lines += 1

    finish_paragraph()

    if in_fence:
        errors.append(f"{path.relative_to(ROOT)}: unclosed code fence")
    if h1_count != 1:
        errors.append(
            f"{path.relative_to(ROOT)}: expected one level-one heading, got {h1_count}"
        )

    for number, line in enumerate(lines, start=1):
        for match in LINK_PATTERN.finditer(line):
            target_path, fragment = link_target(match.group(1))
            if not target_path or "://" in target_path or target_path.startswith("mailto:"):
                continue

            target = (path.parent / target_path).resolve()
            try:
                target.relative_to(ROOT)
            except ValueError:
                errors.append(
                    f"{path.relative_to(ROOT)}:{number}: link escapes repository"
                )
                continue

            if not target.exists():
                errors.append(
                    f"{path.relative_to(ROOT)}:{number}: missing link target "
                    f"{target_path}"
                )
                continue

            if fragment and target.suffix == ".md":
                if github_anchor(fragment) not in headings(target):
                    errors.append(
                        f"{path.relative_to(ROOT)}:{number}: missing fragment "
                        f"#{fragment} in {target.relative_to(ROOT)}"
                    )

    return errors


def main() -> int:
    errors: list[str] = []
    for document in DOCS:
        errors.extend(check_document(document))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
