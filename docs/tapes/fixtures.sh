#!/usr/bin/env bash
# Demo-tape fixtures: the targets docs/tapes/*.tape connect to, shaped like
# the e2e fixtures (tests/test_lib.sh) but standalone - a tape render happens
# outside the test harness, on a machine that just has the backends installed.
# Everything lands under /tmp/hi-demo so `down` can remove it wholesale, and
# every container carries `--label hi.demo=1` so a crashed render can't leak
# one: `down` sweeps the label rather than a list of names it has to be kept in
# step with. The label and not a `hi-demo-*` name prefix, because **a target is
# named for its own hostname** - the tape types `hi db-prod` and the prompt that
# comes back says `db-prod`, which a prefix would break. Nomad is the exception
# and cannot help it: an alloc is addressed by ID, so `hi <alloc-id>` lands on
# `batch-7` and no naming can make those match.
#
# Not sourced by anything; invoked from the tapes' Hide blocks:
#
#   docs/tapes/fixtures.sh up demo|packages|editors|pick|overlay|colors|complete|run
#   docs/tapes/fixtures.sh down
set -euo pipefail

_HI_DEMO_DIR=/tmp/hi-demo
_HI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# demo_wait_for <what> <cmd...> - poll <cmd> once a second for 30s. Returns 0
# the first time it succeeds; otherwise names <what> on stderr and returns 1,
# so a fixture that never came up says which one rather than failing the tape
# further down with something unrelated.
function demo_wait_for() {
  local what="$1" i=0
  shift
  while ((i < 30)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
    i=$((i + 1))
  done
  echo "$what never answered" >&2
  return 1
}

# a throwaway keypair and an ssh config the ssh tape's `hi -F` points at, so
# the demo never touches the renderer's ~/.ssh
function demo_keypair() {
  [ -f "$_HI_DEMO_DIR/key" ] || ssh-keygen -q -t ed25519 -N "" -f "$_HI_DEMO_DIR/key"
}

function demo_sshd_image() {
  # Two images: the e2e sshd base from tests/dockerfiles/sshd-debian.Dockerfile
  # (its context is the entrypoint below, alone in its own directory so the
  # checkout is not sent to the daemon twice), and the demo target from
  # tests/dockerfiles/demo-sshd.Dockerfile on top of it - the box's own hi
  # settings and the clean checkout further down are that one's context.

  # The ssh demo's configuration, and the only one that lives on the target.
  # hi.sh's permanent-install branch (_say_hi, the $remote_root arm) sets
  # $_HI_HOME and $_HI_ROOT and stops, leaving core.sh to default
  # $_HI_CONFIG_DIR to the box's own ~/.config/say-hi - no overlay ships, which
  # is the point of a permanent install. So this rides in the image, where the
  # rest of the box's identity already is, and `docker run hi-demo-sshd` alone
  # is the demo's box rather than one that still needs configuring.
  demo_settings "$_HI_DEMO_DIR/ssh-target-settings.sh" <<'EOF'
export _HI_HEADER_TIMESTAMP='0'
export _HI_HEADER_SYSINFO='0'
export _HI_HEADER_CHECK='0'
EOF

  mkdir -p "$_HI_DEMO_DIR/base"
  cat >"$_HI_DEMO_DIR/base/entrypoint.sh" <<'EOF'
#!/bin/bash
set -eu
mkdir -p /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown -R hitest:hitest /home/hitest/.ssh
chmod 700 /home/hitest/.ssh
ssh-keygen -A
exec /usr/sbin/sshd -D -e
EOF
  docker build -q -t hi-demo-sshd-base \
    -f "$_HI_ROOT/tests/dockerfiles/sshd-debian.Dockerfile" "$_HI_DEMO_DIR/base" >/dev/null
  # A clean copy rather than the live checkout as context: .git and dist/ would
  # bloat the build context and the image alike.
  #
  # From HEAD by default, because a demo should show a state that exists in the
  # history. $HI_DEMO_SOURCE=worktree renders what is in front of you instead -
  # which matters more than it sounds: the *client* side of every tape is the
  # working tree either way, so rendering a dirty tree without this gives you a
  # new client talking to an old target, and the GIF quietly lies.
  rm -rf "$_HI_DEMO_DIR/checkout"
  mkdir -p "$_HI_DEMO_DIR/checkout"
  if [ "${HI_DEMO_SOURCE:-head}" = worktree ]; then
    # tracked files only, uncommitted contents included - the same set
    # `git archive` would take, read from the working tree
    (cd "$_HI_ROOT" && git ls-files -z | tar --null -T - -cf -) |
      tar -x -C "$_HI_DEMO_DIR/checkout"
  else
    (cd "$_HI_ROOT" && git archive HEAD | tar -x -C "$_HI_DEMO_DIR/checkout")
  fi
  docker build -q -t hi-demo-sshd --build-arg BASE=hi-demo-sshd-base \
    -f "$_HI_ROOT/tests/dockerfiles/demo-sshd.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
}

# demo_ssh_block <name> - the Host block that reaches the running sshd
# container <name>: its published port, the demo key, and no known_hosts. The
# one place the shape is spelled, for both files it lands in (the -F config
# below, and the throwaway ~/.ssh/config the colors and run demos read).
function demo_ssh_block() {
  local port
  port="$(docker port "$1" 22/tcp | head -1)"
  port="${port##*:}"
  cat <<EOF
Host $1
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $_HI_DEMO_DIR/key
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
}

function up_ssh() { # <name...> - one sshd box per name, off the one image
  local name
  demo_keypair
  demo_sshd_image
  : >"$_HI_DEMO_DIR/ssh_config"
  for name in "$@"; do
    docker rm -f "$name" >/dev/null 2>&1 || true
    # --hostname as well as --name: docker's own default hostname is a random
    # 12-char hex ID, which makes for an ugly, meaningless color in the
    # header's user@host line. The two match so the ssh_config Host, the name
    # the tape types, and the prompt that answers are all one word.
    docker run -d --rm --name "$name" --hostname "$name" --label hi.demo=1 \
      -p 127.0.0.1::22 \
      -e PUBKEY="$(cat "$_HI_DEMO_DIR/key.pub")" hi-demo-sshd >/dev/null
    demo_ssh_block "$name" >>"$_HI_DEMO_DIR/ssh_config"
  done
  # wait for every sshd to answer before the tape types anything
  for name in "$@"; do
    demo_wait_for "sshd for $name" \
      ssh -F "$_HI_DEMO_DIR/ssh_config" "$name" true
  done
}

# a bare shell-only image per flavor, the docker/podman e2e shape. <name> is
# both the container's name and its hostname: the tape types the first and the
# prompt shows the second, and a demo where those differ reads as a bug in hi.
# It also gives the header's color-hash line something meaningful to hash
# instead of the backend's random container ID.
function up_container() { # <backend> <name> <flavor: debian|zsh|fish|ash>
  local backend="$1" name="$2" flavor="$3" image
  case "$flavor" in
  debian) image=debian:bookworm-slim ;;
  ash) image=alpine:3.24 ;;
  # the debian with your tools on it - git, nano, vim, bat and a checkout under
  # /root/app - which is what the feature tapes have to show; the Dockerfile
  # says what each is for
  tools)
    "$backend" build -q -t hi-demo-tools-img \
      -f "$_HI_ROOT/tests/dockerfiles/demo-debian.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
    image=hi-demo-tools-img
    ;;
  # fish with bash beside it: a box hi can give a *full* session on, in fish,
  # when _HI_SHELL_PREFERENCE says so - the overlay demo's second target, since
  # the bash-less aliases-only tier ships hi's own aliases and not the overlay
  fish-bash)
    "$backend" build -q -t hi-demo-fish-bash-img --build-arg "PKGS=fish bash git" \
      -f "$_HI_ROOT/tests/dockerfiles/alpine-shell.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
    image=hi-demo-fish-bash-img
    ;;
  zsh | fish)
    "$backend" build -q -t "hi-demo-$flavor-img" --build-arg "PKGS=$flavor git" \
      -f "$_HI_ROOT/tests/dockerfiles/alpine-shell.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
    image="hi-demo-$flavor-img"
    ;;
  *)
    echo "unknown flavor: $flavor" >&2
    return 1
    ;;
  esac
  "$backend" rm -f "$name" >/dev/null 2>&1 || true
  "$backend" run -d --rm --name "$name" --hostname "$name" --label hi.demo=1 \
    "$image" tail -f /dev/null >/dev/null
}

# one poll of the hi-demo allocation: stash the running alloc's short ID and
# say whether there was one.
function demo_alloc_running() {
  nomad job allocs -t '{{ range . }}{{ if eq .ClientStatus "running" }}{{ .ID }}{{ end }}{{ end }}' hi-demo \
    2>/dev/null | cut -c1-8 >"$_HI_DEMO_DIR/alloc"
  [ -s "$_HI_DEMO_DIR/alloc" ]
}

function up_nomad() {
  command -v nomad >/dev/null || {
    echo "nomad is not installed" >&2
    return 1
  }
  pkill -f 'nomad agent -dev' 2>/dev/null || true
  nomad agent -dev >"$_HI_DEMO_DIR/nomad.log" 2>&1 &
  echo $! >"$_HI_DEMO_DIR/nomad.pid"
  # not fatal: the job run below is the real gate, and it reports its own
  # failure. A timeout here just says so rather than passing silently.
  demo_wait_for 'the nomad agent' nomad status || true
  cat >"$_HI_DEMO_DIR/demo.nomad.hcl" <<'EOF'
job "hi-demo" {
  type = "service"
  group "g" {
    task "box" {
      driver = "docker"
      config {
        image    = "debian:bookworm-slim"
        hostname = "batch-7"
        command  = "tail"
        args     = ["-f", "/dev/null"]
      }
    }
  }
}
EOF
  nomad job run "$_HI_DEMO_DIR/demo.nomad.hcl" >/dev/null
  demo_wait_for 'the hi-demo allocation' demo_alloc_running
}

function up_kube() {
  command -v kind >/dev/null || {
    echo "kind is not installed" >&2
    return 1
  }
  kind get clusters 2>/dev/null | grep -qx hi-demo ||
    kind create cluster --name hi-demo --wait 120s >/dev/null 2>&1
  # a pod's hostname *is* its name, so naming it for the host is all it takes
  # for `hi api-7` to answer as api-7. The cluster keeps the hi-demo name: it
  # is never on screen, and `kind delete cluster` is what tears it down.
  kubectl --context kind-hi-demo delete pod api-7 --ignore-not-found >/dev/null 2>&1
  kubectl --context kind-hi-demo run api-7 --image=alpine:3.24 \
    --restart=Never --command -- sleep infinity >/dev/null
  kubectl --context kind-hi-demo wait --for=condition=Ready pod/api-7 --timeout=120s >/dev/null
}

# The *client* side of every tape: an rc the tape sources so the outside shell
# has hi's own prompt (vhs starts a bare shell, which otherwise renders the
# blank default) under a chosen identity rather than the renderer's.
#
# The identity needs both halves. $_HI_WHOAMI_CACHE/$_HI_HOSTNAME_CACHE are what
# hi resolves *colors* from, so priming them makes the prompt's colors the ones
# that user@host really would get. The rendered text needs a different lever per
# shell: bash expands \u and \h itself, zsh's %n reads $USERNAME (which zsh will
# not let a script reassign), and fish reads $USER and prompt_hostname. So bash
# and zsh get the two escapes substituted back out of the finished prompt, and
# fish gets the variable and the function. Everything else on the line stays
# hi's real prompt - its colors, its separator, its git segment.
#
# Written through sed rather than an unquoted heredoc so the rc's own ${...}
# survives being generated.
# The per-demo configuration, written as the overlay's settings.sh rather than
# exported into the client shell. That is not a style choice - it is the only
# lever that reaches both ends: _hi_session_env (hi.sh) forwards the target
# color and the tags and nothing else, so a _HI_DISABLE_* or
# _HI_HEADER_* exported here would style the client and leave the session it
# opens on stock defaults. settings.sh is _HI_OVERLAY_FILES[0], so hi ships it
# to the target and both sides read the same file.
#
# Written to $_HI_SETTINGS's own contract (scripts/install.sh): a `#!/bin/sh`
# line and `export NAME='value'` lines, nothing else - fish sources this file
# too, and doctor.sh fails a settings.sh that only parses as sh.
#
# Body on stdin, destination optional - the ssh demo's copy is baked into its
# image instead of the client's overlay dir, and this is the only writer of the
# format either way. No call at all is itself a configuration: demo.tape ships
# the stock defaults on purpose, as the one shot that shows everything on.
function demo_settings() { # [outfile] - body on stdin
  local out="${1:-$_HI_DEMO_DIR/config/settings.sh}"
  mkdir -p "$(dirname "$out")"
  {
    printf '#!/bin/sh\n'
    printf '# written by docs/tapes/fixtures.sh for this demo only\n'
    cat
  } >"$out"
}

# The other overlay files a demo can ship, into the same $_HI_DEMO_DIR/config
# that settings.sh lands in - hi.sh's _HI_OVERLAY_FILES carries both to the
# target, which is the point of showing either. Body on stdin.
function demo_overlay() { # <basename> - body on stdin
  mkdir -p "$_HI_DEMO_DIR/config"
  cat >"$_HI_DEMO_DIR/config/$1"
}

# The rc template's substitutions, in one place rather than once per shell: the
# three rc *bodies* below differ for real, the sed line never did. Reads
# client_rc's locals, so it lives with it and nowhere else.
function rc_sed() { # <outfile> - body on stdin
  sed -e "s/@USER@/$user/g" -e "s/@HOST@/$host/g" \
    -e "s#@HOME@#$home#g" -e "s#@ROOT@#$_HI_ROOT#g" \
    -e "s#@CONFIG@#$_HI_DEMO_DIR/config#g" >"$1"
}

function client_rc() { # <shell> <user> <hostname>
  local shell="$1" user="$2" host="$3" home
  home="$(dirname "$_HI_ROOT")"
  # Every up:* calls this before writing its overlay, so this is the one place
  # that can guarantee a demo gets its own configuration and no one else's.
  # Without it a render of demo.tape straight after packages.tape would inherit
  # docker's overlay from /tmp and quietly stop being the defaults shot. The
  # whole directory, not just settings.sh: `colors` is an overlay file too and
  # would leak the same way.
  rm -rf "$_HI_DEMO_DIR/config"
  mkdir -p "$_HI_DEMO_DIR/config"
  # the throwaway $HOME every tape stands in (pick.tape says why), whether or
  # not its fixture puts anything there
  mkdir -p "$_HI_DEMO_DIR/home"
  # $_HI_HOME/$_HI_ROOT are baked in rather than inherited: vhs starts a bare
  # shell, and on a machine where /usr/bin/hi points at some other install (or
  # a login profile exports its own $_HI_HOME) an inherited one renders the
  # wrong tree - silently, and the GIF is the only place it would show.
  case "$shell" in
  bash)
    rc_sed "$_HI_DEMO_DIR/clientrc.bash" <<'EOF'
export _HI_HOME='@HOME@' _HI_ROOT='@ROOT@'
export _HI_WHOAMI_CACHE='@USER@' _HI_HOSTNAME_CACHE='@HOST@'
# Unconditional, and it has to be: generate.sh sources common/core.sh, which
# exports $_HI_CONFIG_DIR, and vhs hands that environment straight to this
# shell - so anything conditional here would read the renderer's own overlay
# and silently drop this demo's. Ahead of the rc, which is what sources it.
export _HI_CONFIG_DIR='@CONFIG@'
source "$_HI_ROOT/common/bash.sh"
_hi_demo_ps1() {
  ps1
  PS1="${PS1//\\u/@USER@}"
  PS1="${PS1//\\h/@HOST@}"
}
PROMPT_COMMAND=_hi_demo_ps1
EOF
    ;;
  zsh)
    rc_sed "$_HI_DEMO_DIR/clientrc.zsh" <<'EOF'
export _HI_HOME='@HOME@' _HI_ROOT='@ROOT@'
export _HI_WHOAMI_CACHE='@USER@' _HI_HOSTNAME_CACHE='@HOST@'
# unconditional, for the reason the bash rc spells out
export _HI_CONFIG_DIR='@CONFIG@'
source "$_HI_ROOT/common/zsh.zsh"
# %n reads $USERNAME, which zsh will not let a script reassign, so both escapes
# are substituted out of the finished prompt instead. zsh builds PS1 once and
# updates the git segment through a variable, so once is enough.
PS1="${PS1//\%n/@USER@}"
PS1="${PS1//\%m/@HOST@}"
EOF
    ;;
  fish)
    rc_sed "$_HI_DEMO_DIR/clientrc.fish" <<'EOF'
set -gx _HI_HOME '@HOME@'
set -gx _HI_ROOT '@ROOT@'
set -gx _HI_WHOAMI_CACHE '@USER@'
set -gx _HI_HOSTNAME_CACHE '@HOST@'
set -gx USER '@USER@'
# unconditional, for the reason the bash rc spells out
set -gx _HI_CONFIG_DIR '@CONFIG@'
function prompt_hostname
  echo '@HOST@'
end
source "$_HI_ROOT/common/config.fish"
EOF
    ;;
  esac
}

# The demo ssh roster, written outside the overlay because neither thing that
# reads it looks there: it is the file $_HI_SSH_CONFIG has to end up pointing
# at. Getting this in front of the two demos that show ssh hosts is not
# neatness - reading the renderer's real ~/.ssh/config would put their hostnames
# into a committed GIF.
#
# Shared by colors and complete, so the two GIFs name the same boxes - the color
# demo resolves them, the completion demo lists what carries them - but they
# reach the file by different routes, and the difference is forced:
#
#   colors    exports a throwaway $HOME, which paths.sh:52 derives
#             $_HI_SSH_CONFIG from. It reads files and starts nothing, so a
#             fake $HOME costs it nothing.
#   complete  sets $_HI_SSH_CONFIG directly, *after* the rc. It cannot fake
#             $HOME: podman keeps its storage there and kubectl its
#             ~/.kube/config, so a throwaway one empties two of the four
#             backends the demo exists to show.
function demo_ssh_config() {
  mkdir -p "$_HI_DEMO_DIR/home/.ssh"
  cat >"$_HI_DEMO_DIR/home/.ssh/config" <<'EOF'
# Tags: prod
Host db-prod web-prod
  User deploy

# Tags: staging
Host db-staging
  User deploy

# Tags: desktop
Host workshop
  User hitest

Host build-box
  User ci

Host bastion
  User root
EOF
}

# The same roster with real connection details for the sshd boxes named, for
# the demos that both *list* hosts and *connect* to one from a throwaway $HOME:
# the tape types `hi db-prod` bare, so its port and key have to be in the file
# ssh reads. `# Tags:` stays above each live block - it is what the hosttag
# pins resolve from, and a live host without one would color by its name hash
# and quietly stop being the demo.
function demo_ssh_config_live() { # <name:tag...>
  local spec name tag
  mkdir -p "$_HI_DEMO_DIR/home/.ssh"
  {
    for spec in "$@"; do
      name="${spec%%:*}"
      tag="${spec#*:}"
      [ -n "$tag" ] && printf '# Tags: %s\n' "$tag"
      demo_ssh_block "$name"
      echo
    done
    cat <<'EOF'
# Tags: prod
Host web-prod
  User deploy

# Tags: staging
Host db-staging
  User deploy

# Tags: desktop
Host workshop
  User hitest

Host build-box
  User ci

Host bastion
  User root
EOF
  } >"$_HI_DEMO_DIR/home/.ssh/config"
}

# ...and the colors overlay, which lands somewhere else again: paths.sh:30
# reads `colors` out of $_HI_CONFIG_DIR, the same overlay dir every other demo
# writes its settings.sh into. Two live sshd boxes, one per pinned tag, so the
# preview's table and the two sessions after it are the same names.
function up_colors() {
  up_ssh db-prod dev-1 || return 1
  demo_ssh_config_live db-prod:prod dev-1:dev
  demo_overlay colors <<'EOF'
# pins beat the name hash; everything unpinned still resolves on its own
username,root,red
hostname,bastion,yellow
hosttag,prod,red
hosttag,dev,green
hosttag,staging,yellow
hosttag,desktop,green
EOF
}

# The recents file (GLOSSARY: HI.42) under the throwaway $HOME, seeded so the
# picker's first row is settled in advance: <target> used most and last, with
# two older visits to a roster host behind it. Epochs relative to now, so the
# "recent" half of the order holds however long the fixture has been up.
function demo_recents() { # <target>
  local now
  now="$(date +%s)"
  mkdir -p "$_HI_DEMO_DIR/home/.local/state/say-hi"
  printf '%s\t%s\n' \
    "$((now - 90000))" bastion \
    "$((now - 7200))" "$1" \
    "$((now - 3600))" bastion \
    "$((now - 600))" "$1" \
    "$((now - 60))" "$1" \
    >"$_HI_DEMO_DIR/home/.local/state/say-hi/recent"
}

# One of everything, at once - the completion demo's whole subject is that
# `hi <TAB>` answers from every backend in one list, which is the one thing no
# other fixture sets up: they each bring up the single target their tape
# connects to.
#
# Composed from the existing up_* rather than written fresh, so the names in the
# completion pane are the ones the other GIFs already use and nothing here
# can drift from them. The two container names are picked to *not* collide with
# demo_ssh_config's hosts: `db-prod` is an ssh host in that roster, and a pane
# listing it twice - once ssh, once docker - reads as a bug rather than as the
# feature it actually is.
#
# No ssh backend. The ssh rows come from the config file demo_ssh_config writes,
# which is all targets.sh reads for them (its `emit_targets` awks the file), so
# a running sshd would cost four minutes of image build and change nothing on
# screen.
# The picker demo's stage: the ssh roster off a file, and one container to land
# in.
#
# `app-1`, and neither of the two container names the other GIFs already use,
# because both are wrong here for a different reason. `db-prod` is one of
# demo_ssh_config's hosts, and a list naming the same word twice - once ssh,
# once docker - reads as a bug rather than as two backends (up_complete makes
# the same choice, from the same file). `cache-1` is the zsh-only box, so a
# session landing in it prints the bash-less fallback notice instead of the
# ordinary greeting: true, but not this one's subject.
# Debian, therefore, under a name that is in no roster.
function up_pick() {
  demo_ssh_config
  demo_recents app-1
  up_container docker app-1 debian || return 1
}

# The run demo's stage: one target per backend, reached from a throwaway $HOME
# that carries the ssh host's port and key and the kind cluster's kubeconfig -
# the two things a bare `hi <name> <cmd>` reads out of $HOME. The tools debian
# rather than a bare one, so one of the four `cat`s renders through bat.
function up_run() {
  up_ssh web-1 || return 1
  demo_ssh_config_live web-1:
  up_container docker db-prod tools || return 1
  up_nomad || return 1
  up_kube || return 1
  mkdir -p "$_HI_DEMO_DIR/home/.kube"
  kind get kubeconfig --name hi-demo >"$_HI_DEMO_DIR/home/.kube/config"
}

function up_complete() {
  demo_ssh_config
  up_container docker cache-1 zsh || return 1
  up_container podman edge-1 fish || return 1
  up_nomad || return 1
  up_kube || return 1
}

# The label, not a list of names: a name list has to be edited in step with
# every fixture and silently leaks the one somebody forgot, where the label is
# on every container up_container and up_ssh start. Both backends, because a
# render can crash between docker's fixtures and podman's.
function demo_down() {
  local backend ids
  for backend in docker podman; do
    command -v "$backend" >/dev/null 2>&1 || continue
    ids="$("$backend" ps -aq --filter label=hi.demo=1 2>/dev/null || true)"
    # shellcheck disable=SC2086 # ids is a list of container IDs, split on purpose
    [ -n "$ids" ] && "$backend" rm -f $ids >/dev/null 2>&1
  done
  # The agent, by its pid file and then by the pattern that started it. The
  # second half is not belt and braces: demo_down deletes $_HI_DEMO_DIR itself
  # and generate.sh runs a teardown between every tape, so an agent started
  # after the first `down` of a run has no pid file left to reap it by, and
  # without the pattern fallback it would survive a whole render unreaped. The
  # job cannot stand in for the pid either - the first teardown purges it,
  # leaving an agent that is still running and no longer serving anything.
  #
  # So it is the same sweep up_nomad does on the way in, which is what makes it
  # fair: a dev agent is already something the fixtures claim rather than share,
  # and this takes nothing on the way out that they would not have taken on the
  # way in.
  #
  # One live edge, found the hard way: `pkill -f` matches a whole command line,
  # so a shell that merely *mentions* the pattern - a person pasting this line
  # into a terminal, a script quoting it - is killed by its own teardown. Real
  # enough to write down, and not worth a narrower pattern: `nomad agent -dev`
  # is already the most specific string there is for the thing being reaped.
  if [ -f "$_HI_DEMO_DIR/nomad.pid" ]; then
    nomad job stop -purge hi-demo >/dev/null 2>&1 || true
    kill "$(cat "$_HI_DEMO_DIR/nomad.pid")" 2>/dev/null || true
  fi
  pkill -f 'nomad agent -dev' 2>/dev/null || true
  if kind get clusters 2>/dev/null | grep -qx hi-demo; then
    kind delete cluster --name hi-demo >/dev/null 2>&1 || true
  fi
  rm -rf "$_HI_DEMO_DIR" /tmp/hi-demo.log
}

mkdir -p "$_HI_DEMO_DIR"
case "${1:-}:${2:-}" in
# Client identities, chosen per tape rather than taken from the renderer. The
# spread is the point: every tape but one says hi somewhere it is not. The
# exception is docker's second target, where client and target are both cache-1
# - the same box reached two ways, which is worth one frame of the set.
up:packages)
  client_rc bash ivy workshop
  # the check as a diagnosis: a floor of 3 keeps everything below the top tier
  # out of the frame, and the overlay below is the list being checked. Two
  # boxes: the tools debian answers the list quietly, the bare one does not.
  demo_settings <<'EOF'
export _HI_PACKAGES_MIN_PRIORITY='3'
EOF
  demo_overlay packages <<'EOF'
# the tools you care about, and how loudly to miss them
vim:3
nano:3
batcat:3
git:3
rg:3
htop:3
EOF
  up_container docker db-prod tools
  up_container docker builder debian
  ;;
up:editors)
  client_rc zsh dev cache-1
  # the header stays one line; the editors get the frame
  demo_settings <<'EOF'
export _HI_HEADER_CHECK='0'
EOF
  up_container docker db-prod tools
  ;;
up:overlay)
  client_rc fish ops bastion
  # no throwaway $HOME here (podman lives under the real one), so the recents
  # file is moved out of the renderer's state dir by hand
  demo_settings <<'EOF'
export _HI_HEADER_CHECK='0'
export _HI_RECENT_FILE='/tmp/hi-demo/home/recent'
export _HI_SHELL_PREFERENCE='fish'
EOF
  # The demo's subject: one alias, in the POSIX+fish subset settings/aliases.sh
  # says the file has to stay in, and one of the *_OPTS the shipped `cat` alias
  # reads. Both are in effect in a bash session and a fish one, which is what
  # the tape shows. (The fish-only abbr knob was tried here and taken back
  # out: hi is itself an alias, so the abbr expands the `hi edge-1` the tape
  # types into the shim's absolute path, rewriting the command the GIF exists
  # to show.)
  demo_overlay aliases.sh <<'EOF'
# ~/.config/say-hi/aliases.sh - sourced on every target, in every shell
alias dfh='df -h /'
export _HI_BAT_OPTS='-P --theme Nord --style grid'
EOF
  up_container docker db-prod tools
  up_container podman edge-1 fish-bash
  ;;
up:pick)
  # Bare `hi` - the picker. Cheap on purpose: this demo's subject is the
  # *choice*, not the roster, so it wants a list with more than one kind of row
  # in it and one row that can actually be connected to. demo_ssh_config's six
  # hosts supply the first (they are read out of a file, so no sshd is built for
  # them) and one docker container supplies the second; demo_recents puts that
  # container on top.
  #
  # _HI_TARGETS_TTL=0 for up:complete's reason: the sweep is cached for 5s in
  # $XDG_RUNTIME_DIR, which the renderer shares with every other shell on their
  # box, so a stale window would render *their* containers into a committed GIF.
  client_rc bash ivy workshop
  # ...and no package check, so the picker and the session it opens fit one
  # recording. The header is not this demo's subject; the choice above it is.
  demo_settings <<'EOF'
export _HI_TARGETS_TTL='0'
export _HI_HEADER_CHECK='0'
EOF
  up_pick
  ;;

up:complete)
  # The one demo whose subject is the *client* alone - nothing is connected to,
  # so the fixture exists only to be listed. fish for the client because its
  # pager is the one shell that renders targets.sh's second column, which is
  # what makes a still frame carry the idea.
  #
  # Its configuration: _HI_TARGETS_TTL=0. targets.sh caches its sweep for 5s in
  # $XDG_RUNTIME_DIR, which the renderer shares with every other shell on their
  # box - so a TAB landing inside a stale window would render *their* containers
  # into the GIF. 0 is the one value that cannot, and on a demo whose subject is
  # the sweep it is the honest setting anyway.
  client_rc fish ops bastion
  demo_settings <<'EOF'
export _HI_TARGETS_TTL='0'
EOF
  up_complete
  ;;
up:colors)
  # no settings.sh: this demo's configuration is the `colors` overlay up_colors
  # writes, into the same dir every other demo uses. The tape exports a
  # throwaway $HOME as well, for the ssh config the preview and the two
  # sessions read.
  client_rc bash ivy workshop
  up_colors
  ;;
up:run)
  client_rc zsh dev cache-1
  # a one-off command draws no header, so nothing a knob would show; the TTL
  # is up:complete's, for up:complete's reason
  demo_settings <<'EOF'
export _HI_TARGETS_TTL='0'
EOF
  up_run
  ;;
up:demo)
  client_rc bash ivy workshop
  # No demo_settings, deliberately. Every other demo turns something on or
  # ships something of its own; the README's top GIF is the one that shows
  # what you get having configured nothing, which is only legible if it stays
  # stock. The tools debian, so the defaults have something to work on.
  up_container docker db-prod tools
  ;;
down:) demo_down ;;
*)
  echo "usage: fixtures.sh up <demo|packages|editors|pick|overlay|colors|complete|run> | down" >&2
  exit 1
  ;;
esac
