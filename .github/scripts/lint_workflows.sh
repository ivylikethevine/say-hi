#!/usr/bin/env bash
# Structural invariants over GitHub Actions YAML that neither zizmor nor
# actionlint enforces as a rule. Each one is a convention a reviewer would
# otherwise have to remember on every new job:
#
#   1. every job sets timeout-minutes (a call to a reusable workflow cannot,
#      so those are exempt; the called workflow's own jobs are checked)
#   2. every actions/checkout step sets persist-credentials: false
#   3. every workflow declares top-level permissions (jobs widen it, never
#      inherit the default token)
#   4. a workflow triggered by workflow_run gates each job that can start on
#      its own - no `needs:`, or always()/cancelled()/failure() in its `if:` -
#      on github.event.workflow_run.conclusion == 'success', unless its `if:`
#      narrows it to another event (`github.event_name == '<event>'`, no `||`,
#      and no comparison of event_name against workflow_run)
#   5. every third-party `uses:` is pinned to a 40-hex commit SHA followed by
#      a `# vX.Y.Z` comment, or `# X.Y.Z` where upstream's tags carry no v
#      (local `./`, `$/` and `docker://` refs are exempt)
#   6. every job's first step is step-security/harden-runner with an explicit
#      egress-policy, audit or block, or an expression choosing one of them by
#      `runner.os` (one step: the action's `pre` ignores its step's `if:`, so a
#      second step's agent would start too); reusable-workflow calls have no
#      steps and are exempt; the action's own default is `block`, which with no
#      allowlist would cut a job off, so the policy is never left to it
#   7. in a job whose actions/checkout sets sparse-checkout, every local
#      `uses: ./<path>` step has <path> (or a parent directory of it) in that
#      list - otherwise the runner fails with "Can't find 'action.yml'"
#   8. no `# zizmor: ignore[...]` sits on the `on:` line: zizmor flags the
#      trigger's own key, and 1.31.0 ignores a comment on `on:` that 1.30.1
#      and 1.31.1 honour, so it goes on the trigger's line instead
#
# Workflows get all eight; composite actions (action.yml) get 2 and 5.
#
#   .github/scripts/lint_workflows.sh [file...]
#
# With no arguments it reads .github/workflows/*.y*ml and every
# .github/actions/**/action.y*ml. Needs jq and a yq - either mikefarah's Go
# yq or the Python jq wrapper; both only convert YAML to JSON here, and jq
# does the rest. Prints one line per violation and exits 1 if there were
# any, 127 when yq or jq is missing. Runs under bash 3.2.
set -euo pipefail

cd "$(dirname "$0")/../.."

# shellcheck source=./lib.sh
source .github/scripts/lib.sh
_ci_need lint_workflows yq jq

# YAML to JSON with whichever yq is installed: the Go one needs -o=json, the
# Python one prints JSON already. The Python one reads `on:` as YAML 1.1's
# boolean true, hence `.on // .["true"]` in the filter.
if yq --version 2>&1 | grep -qi mikefarah; then
  to_json() { yq -o=json '.' "$1"; }
else
  to_json() { yq '.' "$1"; }
fi

if [ $# -eq 0 ]; then
  while IFS= read -r f; do
    set -- "$@" "$f"
  done < <(
    {
      find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \)
      find .github/actions -type f \( -name action.yml -o -name action.yaml \)
    } 2>/dev/null | sort
  )
fi

# Rules 1, 3, 4, 6 and 7: workflows only.
# shellcheck disable=SC2016 # jq's $vars, not the shell's
workflow_filter='
  def triggers: (.on // .["true"]) as $on
    | if ($on | type) == "string" then [$on]
      elif ($on | type) == "array" then $on
      elif ($on | type) == "object" then ($on | keys)
      else [] end;
  def cond: (.if // "") | tostring;
  def jobs: (.jobs // {}) | to_entries[];
  (if .permissions == null then "no top-level permissions: block" else empty end),
  (jobs | .key as $job | .value as $j
    | select($j.uses == null)
    | (if $j["timeout-minutes"] == null then "job \($job): no timeout-minutes" else empty end),
      (($j.steps // [])[0] // {}) as $first
      | (if (($first.uses // "") | startswith("step-security/harden-runner@") | not)
          then "job \($job): first step is not step-security/harden-runner"
        elif ((($first.with // {})["egress-policy"] // "") | tostring
            | test("^(audit|block)$|^\\$\\{\\{ *runner\\.os *[!=]= *\\x27[A-Za-z]+\\x27 *&& *\\x27(audit|block)\\x27 *\\|\\| *\\x27(audit|block)\\x27 *\\}\\}$")
            | not)
          then "job \($job): step-security/harden-runner has no explicit egress-policy (audit or block)"
        else empty end)),
  (if (triggers | index("workflow_run")) != null then
    jobs | .key as $job | .value as $j
    | ($j | cond) as $if
    | select($j.needs == null or ($if | test("always\\(\\)|cancelled\\(\\)|failure\\(\\)")))
    | select($if | test("github\\.event\\.workflow_run\\.conclusion\\s*==\\s*.success.") | not)
    | select((($if | test("github\\.event_name\\s*==\\s*.[a-z_]+."))
              and ($if | contains("||") | not)
              and ($if | test("github\\.event_name\\s*(==|!=)\\s*.workflow_run.") | not)) | not)
    | "job \($job): runs on workflow_run without requiring github.event.workflow_run.conclusion == '"'"'success'"'"'"
  else empty end),
  (jobs | .key as $job | (.value.steps // []) as $steps
    | [$steps[] | select((.uses // "") | startswith("actions/checkout@"))
        | (.with // {})["sparse-checkout"] | select(. != null)] as $lists
    | select($lists | length > 0)
    | [$lists[] | tostring | split("\n")[]
        | sub("^\\s+"; "") | sub("\\s+$"; "") | select(. != "")
        | sub("^/"; "") | sub("/+$"; "")] as $sparse
    | $steps[] | (.uses // "") | select(startswith("./"))
    | ltrimstr("./") | sub("/+$"; "") as $path
    | select([$sparse[] | . as $p | select($path == $p or ($path | startswith($p + "/")))] | length == 0)
    | "job \($job): uses: ./\($path) is not in its checkout'"'"'s sparse-checkout list")
'

# Rule 2: workflows and composite actions alike ("false" as a string is
# equally honoured by the action).
# shellcheck disable=SC2016 # jq's $vars, not the shell's
checkout_filter='
  ([(.jobs // {}) | to_entries[] | .key as $job
     | (.value.steps // []) | to_entries[] | {where: "job \($job) step \(.key + 1)", s: .value}]
   + [(.runs.steps // []) | to_entries[] | {where: "composite step \(.key + 1)", s: .value}])[]
  | select((.s.uses // "") | startswith("actions/checkout@"))
  | select(((.s.with // {})["persist-credentials"] | tostring) != "false")
  | "\(.where): actions/checkout without persist-credentials: false"
'

# Rules 5 and 8 are line-based: comments are not part of the parsed YAML.
# Held in variables so bash 3.2 and 4+ read the regexes the same way.
_lw_uses_re='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*["'"'"']?([^"'"'"'[:space:]]+)["'"'"']?(.*)$'
_lw_sha_re='^[^/@[:space:]]+/[^@[:space:]]+@[0-9a-f]{40}$'
_lw_comment_re='^[[:space:]]+#[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.-]+)?([[:space:]]|$)'
_lw_on_ignore_re='^["'"'"']?on["'"'"']?:.*#.*zizmor:[[:space:]]*ignore\['

bad=0
# report <where> <message>
report() {
  printf '%s: %s\n' "$1" "$2"
  bad=$((bad + 1))
}

for file in "$@"; do
  [ -f "$file" ] || {
    report "$file" "no such file"
    continue
  }
  json="$(to_json "$file")" || {
    report "$file" "not valid YAML"
    continue
  }

  case "$file" in
  action.y*ml | */action.y*ml) filter="$checkout_filter" workflow="" ;;
  *) filter="($workflow_filter), ($checkout_filter)" workflow=1 ;;
  esac
  msgs="$(printf '%s\n' "$json" | jq -r "$filter")" || {
    report "$file" "jq could not evaluate the rules"
    continue
  }
  while IFS= read -r msg; do
    if [ -n "$msg" ]; then report "$file" "$msg"; fi
  done <<EOF_MSGS
$msgs
EOF_MSGS

  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ -n "$workflow" ] && [[ "$line" =~ $_lw_on_ignore_re ]]; then
      report "$file:$n" "zizmor ignore on the on: line: put it on the line of the trigger it covers"
    fi
    [[ "$line" =~ $_lw_uses_re ]] || continue
    ref="${BASH_REMATCH[2]}"
    rest="${BASH_REMATCH[3]}"
    case "$ref" in
    ./* | '$/'* | docker://*) continue ;;
    esac
    if ! [[ "$ref" =~ $_lw_sha_re ]]; then
      report "$file:$n" "uses: $ref is not pinned to a 40-hex commit SHA"
    elif ! [[ "$rest" =~ $_lw_comment_re ]]; then
      report "$file:$n" "uses: $ref has no '# vX.Y.Z' version comment"
    fi
  done <"$file"
done

if [ "$bad" -gt 0 ]; then
  echo "lint_workflows: $bad violation(s) in $# file(s)" >&2
  exit 1
fi
echo "lint_workflows: $# file(s) clean"
