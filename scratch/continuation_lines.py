r"""continuation_lines.py <kcov cobertura.xml> <bashcov .resultset.json> <checkout> <rev> [out]

Every product line that follows a line ending in `&&`, `||`, `|` or `\`, read
against the source at <rev>, tallied by that operator and by what each tool
recorded on it and on the line above: whether the tracers print a continued
command's later lines, which is what tests/lib/coverage.sh's shadow() rule
for them assumes they never do. Then each line both tools missed while the
line above ran, for reading by hand. Written to [out] (default stdout).

  scratch/coverage_gaps.sh <coverage run id>   fetches the two reports into
                                               local/coverage-<run>/
  python3 -I scratch/continuation_lines.py local/coverage-<run>/cobertura.xml \
    local/coverage-<run>/resultset.json . <sha> local/coverage-<run>/cont.md

Product files only: tests/, docs/, scratch/, .github/ are not the subject.
Heredoc bodies and multi-line single-quoted strings (an awk program's `||`)
are left out.
"""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

kcov_xml, resultset, checkout, rev = sys.argv[1:5]
out = open(sys.argv[5], "w") if len(sys.argv) > 5 else sys.stdout
SKIP = re.compile(r"^(tests|docs|scratch|\.github)/|^\.")
ROOT = re.compile(r"^.*?/say-hi/say-hi/|^.*?/say-hi/(?=(common|scripts|config|packaging|load\.sh|hi\.sh))")
OP = re.compile(r"(\\|\|\||&&|\|)\s*$")


def rel(path):
    m = ROOT.search(path)
    return path[m.end():] if m else path


kcov = {}
for cls in ET.parse(kcov_xml).iter("class"):
    f = rel(cls.get("filename") or "")
    if SKIP.match(f):
        continue
    lines = kcov.setdefault(f, {})
    for ln in cls.iter("line"):
        n, h = int(ln.get("number") or 0), int(ln.get("hits") or 0)
        lines[n] = max(lines.get(n, 0), h)

bash = {}
for entry in json.load(open(resultset)).values():
    for path, data in (entry.get("coverage") or {}).items():
        f = rel(path)
        if SKIP.match(f) or "/say-hi/" in f or f.startswith("/"):
            continue
        arr = data["lines"] if isinstance(data, dict) else data
        lines = bash.setdefault(f, {})
        for i, v in enumerate(arr):
            if v is not None:
                lines[i + 1] = lines.get(i + 1, 0) + v


def source(f):
    try:
        return subprocess.run(["git", "-C", checkout, "show", f"{rev}:{f}"],
                              capture_output=True, text=True, check=True).stdout.split("\n")
    except subprocess.CalledProcessError:
        return []


def code_lines(lines):
    """per line: its code with the comment cut, or None in a heredoc body or
    a multi-line single-quoted string"""
    res: list[str | None] = [None]
    heredoc, quote = None, False
    for t in lines:
        if heredoc:
            res.append(None)
            if t.strip() == heredoc:
                heredoc = None
            continue
        res.append(None if quote else re.sub(r"(^|\s)#.*$", "", t).rstrip())
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_]+)['\"]?", t)
        if m and not quote:
            heredoc = m.group(1)
        code = re.sub(r'"(\\.|[^"\\])*"', '""', t if quote else re.sub(r"(^|\s)#.*$", "", t))
        if code.count("'") % 2 == 1:
            quote = not quote
    return res


def state(d, n):
    return "-" if n not in d else ("hit" if d[n] > 0 else "missed")


tally, inspect = {}, []
for f in sorted(set(kcov) | set(bash)):
    src = source(f)
    code = code_lines(src)
    k, b = kcov.get(f, {}), bash.get(f, {})
    for n in range(2, len(code)):
        p, t = code[n - 1], code[n]
        if p is None or t is None or not t.strip():
            continue
        m = OP.search(p)
        if not m:
            continue
        op = m.group(1)
        key = (op, state(k, n), state(b, n))
        tally[key] = tally.get(key, 0) + 1
        prev_ran = k.get(n - 1, 0) > 0 or b.get(n - 1, 0) > 0
        if state(k, n) == "missed" and state(b, n) == "missed" and prev_ran:
            inspect.append((op, f, n, src[n - 2].strip(), src[n - 1].strip()))

w = out.write
w(f"# continuation lines at {rev}\n\n")
w("`-` is a line the tool does not count as executable.\n\n")
w(f"| {'op':4} | {'kcov':6} | {'bashcov':7} | {'lines':>5} |\n| ---- | ------ | ------- | ----: |\n")
for (op, ks, bs), c in sorted(tally.items()):
    w(f"| {op.replace('|', chr(92) + '|'):4} | {ks:6} | {bs:7} | {c:5d} |\n")
w(f"\n## missed by both, the line above run ({len(inspect)})\n\n")
for op, f, n, a, t in inspect:
    w(f"- `{op}` {f}:{n}\n  - {a[:110]}\n  - {t[:110]}\n")
