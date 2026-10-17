#!/usr/bin/env python3
"""Every repo path a doc names in a code span that no longer exists.

Reads README.md, CLAUDE.md and docs/*.md, takes each `code span` that looks
like a path into this checkout (holds a / or ends in a known extension, no
spaces, no $ or <>), and prints the ones with no file or directory behind
them, grouped by doc. A path under local/, a glob, or a placeholder in
angle brackets is skipped. Review the list: a path a doc names as an example
of what a user might create is not a stale reference.

Usage: python3 -I scratch/doc_paths.py [checkout]   (default: the cwd)
"""

import glob
import os
import re
import subprocess
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
SPAN = re.compile(r"`([^`\n]+)`")
EXT = (".sh", ".md", ".yml", ".yaml", ".json", ".toml", ".txt", ".fish", ".zsh", ".1", ".py", ".nix", ".lock", ".tape")
SKIP = re.compile(r"[\s$<>*{}|=,;:()]|^local/|^~|^/|^https?:")


def looks_like_path(span):
    span = span.strip()
    if SKIP.search(span):
        return None
    span = span.rstrip("/")
    if "/" in span or span.endswith(EXT):
        return span
    return None


# a bare name (`ci.yml`, `install.sh`) counts when any tracked file has it
tracked = subprocess.run(
    ["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True
).stdout.split("\n")
suffixes = set()
for t in tracked:
    parts = t.split("/")
    for i in range(len(parts)):
        suffixes.add("/".join(parts[i:]))
    for i in range(1, len(parts)):
        suffixes.add("/".join(parts[:i]))


def known(cand):
    return cand in suffixes or os.path.exists(os.path.join(root, cand))


docs = ["README.md", "CLAUDE.md"] + sorted(glob.glob(os.path.join(root, "docs", "*.md")))
missing_total = 0
for doc in docs:
    path = doc if os.path.isabs(doc) else os.path.join(root, doc)
    if not os.path.exists(path):
        continue
    seen = set()
    missing = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for span in SPAN.findall(line):
                cand = looks_like_path(span)
                if not cand or cand in seen:
                    continue
                seen.add(cand)
                # a path given relative to the root, to docs/ (another doc),
                # or by a tail of a tracked path
                beside = os.path.join(os.path.dirname(path), cand)
                if not (known(cand) or os.path.exists(beside)):
                    missing.append((n, cand))
    if missing:
        print(f"{os.path.relpath(path, root)}:")
        for n, cand in missing:
            print(f"  {n}: {cand}")
        missing_total += len(missing)
print(f"{missing_total} path spans with nothing behind them")
