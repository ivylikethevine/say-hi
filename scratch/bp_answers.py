#!/usr/bin/env python3
"""Turn docs/OPENSSF-IMPROVEMENTS.md's answer sheet into paste-ready entries.

One entry per criterion for the silver, gold and baseline level 3 sections: its edit link on
bestpractices.dev, the status to pick, and the justification with doc links
made absolute. A combined row (`a` / `b`) becomes one entry per criterion,
and a gold "Same as silver" row takes silver's evidence.

    python3 scratch/bp_answers.py            # writes local/bp-answers.md
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "docs" / "OPENSSF-IMPROVEMENTS.md"
OUT = ROOT / "local" / "bp-answers.md"
EDIT = "https://www.bestpractices.dev/en/projects/14397/{level}/edit#{name}"
BLOB = "https://github.com/ivylikethevine/say-hi/blob/main/"
STATUS = {"M": "Met", "U": "Unmet", "N/A": "N/A"}


def absolute(link: str) -> str:
    if link.startswith("http"):
        return link
    if link.startswith("../"):
        return BLOB + link[3:]
    return BLOB + "docs/" + link


def justification(text: str) -> str:
    # [label](target) -> target, the form the site's text field links
    return re.sub(r"\[[^\]]*\]\(([^)]+)\)", lambda m: absolute(m.group(1)), text).strip()


def rows(lines: list[str], heading: str) -> list[tuple[str, str, str]]:
    out, inside = [], False
    for line in lines:
        if line.startswith("### "):
            inside = line.strip() == f"### {heading}"
            continue
        if not inside or not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        names = re.findall(r"`([a-zA-Z0-9_]+)`", cells[0])
        status = STATUS.get(cells[1].split()[0], cells[1])
        for name in names:
            out.append((name, status, cells[2]))
    return out


def main() -> int:
    lines = SHEET.read_text().split("\n")
    silver = rows(lines, "Silver level")
    silver_evidence = {name: ev for name, _, ev in silver}
    parts = []
    counts = []
    for level, heading in (("silver", "Silver level"), ("gold", "Gold level"), ("baseline-3", "Baseline level 3")):
        entries = rows(lines, heading)
        counts.append(f"{len(entries)} {level}")
        parts.append(f"# {heading}\n")
        for name, status, evidence in entries:
            if level == "gold" and evidence.startswith("Same") and "silver" in evidence:
                extra = " [](SECURITY.md#assurance-case)" if "assurance-case URL" in evidence else ""
                evidence = silver_evidence.get(name, evidence) + extra
            parts.append(
                f"## {name} - {status}\n\n{EDIT.format(level=level, name=name)}\n\n"
                f"```text\n{justification(evidence)}\n```\n"
            )
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("\n".join(parts))
    print(f"{OUT}: " + ", ".join(counts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
