"""coverage_gaps.py <kcov cobertura.xml> <bashcov .resultset.json> <checkout> <rev> [out]

The lines of a coverage sweep neither tool recorded, read against the source
at <rev> (git show, so the line numbers are the sweep's), each sorted into
the artifact it is - a shape xtrace never prints, a zsh-only or another OS's
arm, code a target runs from a generated script - or a real gap. Then the
files the two tools disagree on most. Written to [out] (default stdout).

  scratch/coverage_gaps.sh <coverage run id>   fetches the two reports and
                                               runs this over them

Product files only: tests/, docs/, scratch/, .github/ are not the subject.
"""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

kcov_xml, resultset, checkout, rev = sys.argv[1:5]
out = open(sys.argv[5], "w") if len(sys.argv) > 5 else sys.stdout
SKIP = re.compile(r"^(tests|docs|scratch|\.github)/")
ROOT = re.compile(r"^.*?/say-hi/say-hi/|^.*?/say-hi/(?=(common|scripts|config|packaging|load\.sh|hi\.sh))")


def rel(path):
    m = ROOT.search(path)
    return path[m.end():] if m else path


# kcov: cobertura's per-line hits, a file's lines keyed by number
kcov = {}
tree = ET.parse(kcov_xml)
for cls in tree.iter("class"):
    f = rel(cls.get("filename") or "")
    if SKIP.match(f):
        continue
    lines = kcov.setdefault(f, {})
    for ln in cls.iter("line"):
        n, h = int(ln.get("number") or 0), int(ln.get("hits") or 0)
        lines[n] = max(lines.get(n, 0), h)

# bashcov: the resultset's per-line arrays, summed over every command name
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

src_cache = {}


def source(f):
    if f not in src_cache:
        try:
            txt = subprocess.run(["git", "-C", checkout, "show", f"{rev}:{f}"],
                                 capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError:
            txt = ""
        src_cache[f] = txt.split("\n")
    return src_cache[f]


def context(f):
    """per line: in a heredoc body, in a multi-line single-quoted string, in
    a hi-nocov region, under a zsh test, inside a generated remote script"""
    lines = source(f)
    info = [set() for _ in range(len(lines) + 2)]
    heredoc = None
    remote = False
    quote = False
    nocov = False
    array = False
    zsh_depth = None
    for i, t in enumerate(lines, 1):
        s = t.strip()
        if heredoc:
            info[i].add("heredoc")
            if remote:
                info[i].add("remote")
            if s == heredoc:
                heredoc, remote = None, False
            continue
        if quote:
            info[i].add("quoted")
        # a multi-line array literal: xtrace credits it to one line
        if array:
            info[i].add("array")
            if re.search(r"\)\s*$", t.split(" #")[0]):
                array = False
        elif re.search(r"=\([^)]*$", t.split(" #")[0]):
            array = True
        if "hi-nocov-begin" in t:
            nocov = True
        if nocov:
            info[i].add("nocov")
        if "hi-nocov-end" in t:
            nocov = False
        if re.search(r'ZSH_VERSION', t) and re.search(r'\[ -n "\$\{?ZSH_VERSION', t):
            zsh_depth = len(t) - len(t.lstrip())
        elif zsh_depth is not None:
            ind = len(t) - len(t.lstrip())
            if s.startswith(("else", "elif", "fi")) and ind <= zsh_depth:
                zsh_depth = None
            elif s:
                info[i].add("zsh")
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_]+)['\"]?", t)
        if m and not quote:
            heredoc = m.group(1)
            remote = heredoc in ("REMOTE", "SH", "SCRIPT")
        # single quotes outside double quotes and comments toggle the state
        code = re.sub(r'"(\\.|[^"\\])*"', '""', t.split(" #")[0] if not quote else t)
        if code.count("'") % 2 == 1:
            quote = not quote
    return info


SHAPES = [
    ("closes a block with a redirect", re.compile(r"^\s*(done|[})]|fi|esac)\s*[0-9]*[<>]")),
    ("a bare keyword or case label", re.compile(r"^\s*(do|then|else|fi|done|esac|esac\s*;;|;;|\{|\}|\)|[^ ()]+\)\s*;;?|[^ ()]*\))\s*$")),
    ("an empty case arm", re.compile(r"^\s*[^()]*\)\s*;;\s*$")),
    ("another OS's arm", re.compile(r"Darwin|darwin|MINGW|MSYS|CYGWIN|wmic|sysctl|vm_stat|sw_vers|OpenBSD|FreeBSD|/proc/")),
]


CONT = re.compile(r"(\\|\||&&|\|\|)\s*$|=\([^)]*$|\$\([^)]*$")


def classify(f, n, info, hit):
    lines = source(f)
    t = lines[n - 1] if n - 1 < len(lines) else ""
    prev = lines[n - 2].split(" #")[0].rstrip() if n >= 2 else ""
    code = t.split(" #")[0].rstrip()
    tags = info[n]
    if "nocov" in tags:
        return "excluded"
    if "remote" in tags:
        return "artifact: a target runs it, from a generated script"
    if "heredoc" in tags:
        return "artifact: a heredoc body"
    if "quoted" in tags:
        return "artifact: inside a multi-line quoted string (awk, sed, a script)"
    if "array" in tags:
        return "artifact: a line of a multi-line array"
    if "zsh" in tags:
        return "platform: a zsh-only arm"
    if CONT.search(prev):
        return "artifact: the rest of a command the line above continues"
    # xtrace credits a command that spans lines to its last line
    if CONT.search(code) and hit(n + 1):
        return "artifact: the first line of a command split across lines"
    if re.match(r"^\s*for \(\(", t) and hit(n + 1):
        return "artifact: an arithmetic for header whose body ran"
    for name, rx in SHAPES[:3]:
        if rx.search(t):
            return "artifact: " + name
    if SHAPES[3][1].search(t):
        return "platform: another OS's arm"
    return "gap"


report = []
both_missed = {}
files = sorted(set(kcov) | set(bash))
for f in files:
    k, b = kcov.get(f, {}), bash.get(f, {})
    info = context(f)

    def hit(m, k=k, b=b):
        return k.get(m, 0) > 0 or b.get(m, 0) > 0

    for n in sorted(set(k) | set(b)):
        if k.get(n, 1) == 0 and b.get(n, 1) == 0 and n in k and n in b:
            c = classify(f, n, info, hit)
            if c != "excluded":
                both_missed.setdefault(f, []).append((n, c))

w = out.write
w(f"# coverage gaps at {rev}\n\n")
tot = {}
for f, rows in both_missed.items():
    for _, c in rows:
        key = c.split(":")[0]
        tot[key] = tot.get(key, 0) + 1
w("lines both tools missed: " + ", ".join(f"{v} {k}" for k, v in sorted(tot.items())) + "\n\n")
w("## real gaps, by file\n\n")
for f, rows in sorted(both_missed.items(), key=lambda kv: -sum(c == "gap" for _, c in kv[1])):
    gaps = [n for n, c in rows if c == "gap"]
    if not gaps:
        continue
    w(f"### {f} ({len(gaps)})\n")
    src = source(f)
    for n in gaps:
        w(f"{n:5d}  {src[n - 1].strip()[:110]}\n")
    w("\n")
w("## artifacts and platform arms, by kind\n\n")
kinds = {}
for f, rows in both_missed.items():
    for n, c in rows:
        if c != "gap":
            kinds.setdefault(c, []).append(f"{f}:{n}")
for c, locs in sorted(kinds.items(), key=lambda kv: -len(kv[1])):
    w(f"- {c}: {len(locs)} ({', '.join(locs[:6])}{', ...' if len(locs) > 6 else ''})\n")
w("\n## where the tools disagree (missed by one, run by the other)\n\n")
w(f"{'file':34} {'kcov only':>9} {'bashcov only':>12}\n")
div = []
for f in files:
    k, b = kcov.get(f, {}), bash.get(f, {})
    ko = sum(1 for n in k if k[n] == 0 and b.get(n, 0) > 0)
    bo = sum(1 for n in b if b[n] == 0 and k.get(n, 0) > 0)
    div.append((ko + bo, f, ko, bo))
for _, f, ko, bo in sorted(div, reverse=True)[:20]:
    w(f"{f:34} {ko:9d} {bo:12d}\n")
for name, d in (("kcov", kcov), ("bashcov", bash)):
    h = sum(1 for f in d for n in d[f] if d[f][n] > 0)
    t = sum(len(d[f]) for f in d)
    w(f"\n{name}: {h}/{t} lines, {100 * h / max(t, 1):.2f}%")
w("\n")
