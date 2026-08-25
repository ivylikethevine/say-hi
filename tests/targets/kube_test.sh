#!/bin/bash
# Boots a throwaway kind (Kubernetes-in-docker) cluster and drives hi.sh's
# real kube path (_say_hi_container) over actual `kubectl exec` against pods
# running on it. This proves the kube-specific command shapes added to
# _say_hi_container (`kubectl exec POD --` for the probe, `-i ... --` for
# copying, `-it ... --` for the interactive attach, the `--` separating
# kubectl's own flags from the remote command).
# Only two cases are covered, not the full zsh/fish fallback matrix
# docker_test.sh/podman_test.sh run: _say_hi_container's fallback logic past
# the initial `command -v bash` probe is identical code for every backend and
# is already proven there, so this only needs to prove kubectl exec's own
# argument shapes work - once with bash present, once without.
#
# GLOSSARY: HI.30 + HI.34
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_HI_CLUSTER="hi-kubetest-$$"
_HI_CLUSTER_UP=0

function _hi_kube_cleanup() {
  [ "$_HI_CLUSTER_UP" -eq 1 ] && kind delete cluster --name "$_HI_CLUSTER" >/dev/null 2>&1
  return 0
}

function _hi_pod_running() { [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }

# A kind node starts with an empty containerd, so --image-pull-policy=IfNotPresent
# still pulls from the registry the first time a pod wants an image - and
# debian:bookworm-slim did not finish inside the Running poll's budget on CI
# while the 3MB alpine shape did. Pulling both up front moves that wait out of
# the per-pod budget, which is the actual coupling: the poll below should be
# waiting on the scheduler, never on a download.
#
# `crictl pull` in the node rather than `kind load docker-image` from the host:
# kind's loader shells out to `ctr images import --all-platforms`, which fails
# ("content digest ...: not found") wherever docker's image store holds a
# multi-platform index without every platform's blobs - true of this dev box and
# not something a test should be fragile about. crictl talks to the node's own
# containerd and needs nothing from the host's docker at all.
#
# Best-effort throughout: a failure here is a slow pod, not a broken suite, and
# the widened poll covers it.
function _hi_kube_preload_images() {
  local node image
  local -a nodes=()
  _hi_read_lines nodes < <(kind get nodes --name "$_HI_CLUSTER" 2>/dev/null)
  [ "${#nodes[@]}" -gt 0 ] || {
    _hi_cecho " | No nodes to preload, leaving the images to the pods" "$YELLOW"
    return 0
  }
  for node in "${nodes[@]}"; do
    for image in "$_HI_PAIR_IMAGE_BASH" "$_HI_PAIR_IMAGE_SH"; do
      if docker exec "$node" crictl pull "$image" >>"$_HI_WORKDIR/preload.log" 2>&1; then
        _hi_cecho " | Preloaded $image" "$GREEN"
      else
        _hi_cecho " | Could not preload $image, leaving it to the pod" "$YELLOW"
      fi
    done
  done
  return 0
}

# 90s rather than the 30s docker and podman take, and the difference is the
# transport rather than slack: those two exec locally, while every step here is
# an API-server round trip. One session is eight of them - the bash probe, the
# shell ladder, three file streams, the attach and the cleanup - and the three
# cases run as a batch, so a single-node kind cluster serves all of it at once.
# On a laptop that is a second; on a shared CI runner 30s was the budget that
# broke first, and it was measuring the cluster, not hi.
function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-90}"
  local name ok=0

  name="hi-kubetest-$label"
  _hi_h3 "Testing shape: [$label]"

  if ! kubectl run "$name" --image="$image" --image-pull-policy=IfNotPresent \
    --restart=Never --command -- sleep infinity >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_dump_log "Failed to create pod:" "$_HI_WORKDIR/$label.run.log"
    return 1
  fi
  _hi_cecho " | Pod: $name (image: $image)"

  # 120s, generously: the preload makes Running arrive in a couple of seconds,
  # so this is the budget for the run where that didn't work rather than a
  # figure anything normally spends.
  if ! _hi_poll_bool 240 0.5 _hi_pod_running "$name"; then
    kubectl describe pod "$name" >"$_HI_WORKDIR/$label.describe.log" 2>&1 || true
    _hi_dump_log "Pod never reported Running:" "$_HI_WORKDIR/$label.describe.log"
    kubectl delete pod "$name" --now >/dev/null 2>&1
    return 1
  fi

  _hi_exec_case "$label" "kube path" "$_HI_TEST_MARKER" "$timeout_s" "$name" "$cmd" && ok=1
  kubectl delete pod "$name" --now >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

# The pod/container syntax, against a pod that actually has two. The assertion
# is not "it connected" but "it connected to the one named": each container
# writes its own name to /tmp/who, and a session that ignored the suffix would
# read the other's file - which is exactly what kubectl's silent first-container
# default does, and what this syntax exists to stop.
function _hi_kube_multi_container_case() {
  local name=hi-kubetest-multi got ok=0
  _hi_h3 "Testing shape: [multi-container]"
  if ! kubectl apply -f - >"$_HI_WORKDIR/multi.run.log" 2>&1 <<EOF; then
apiVersion: v1
kind: Pod
metadata:
  name: $name
spec:
  containers:
    - name: app
      image: $_HI_PAIR_IMAGE_SH
      command: ["sleep", "infinity"]
    - name: sidecar
      image: $_HI_PAIR_IMAGE_SH
      command: ["sleep", "infinity"]
EOF
    _hi_dump_log "Failed to create the multi-container pod:" "$_HI_WORKDIR/multi.run.log"
    return 1
  fi
  if ! _hi_poll_bool 240 0.5 _hi_pod_running "$name"; then
    kubectl describe pod "$name" >"$_HI_WORKDIR/multi.describe.log" 2>&1 || true
    _hi_dump_log "Multi-container pod never reported Running:" "$_HI_WORKDIR/multi.describe.log"
    kubectl delete pod "$name" --now >/dev/null 2>&1
    return 1
  fi
  kubectl exec "$name" -c app -- sh -c 'echo app >/tmp/who' >/dev/null 2>&1
  kubectl exec "$name" -c sidecar -- sh -c 'echo sidecar >/tmp/who' >/dev/null 2>&1

  got="$("$_HI_ROOT/hi.sh" "$name/sidecar" 'cat /tmp/who' 2>/dev/null | tr -d '\r' | tail -1)"
  if [ "$got" = sidecar ]; then
    _hi_align " | pod/container reached the named container" "OK" "$GREEN"
    ok=1
  else
    _hi_cecho " | hi $name/sidecar read '$got', expected 'sidecar'" "$RED"
  fi
  kubectl delete pod "$name" --now >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

# The namespace prefix: a pod in a namespace kubectl does *not* point at,
# reached as `namespace:pod`. A bare `hi <pod>` would not find it at all, so
# a session landing is the proof that the prefix became --namespace.
function _hi_kube_namespace_case() {
  local ns=hi-kubetest-ns name=hi-kubetest-nspod ok=0
  _hi_h3 "Testing shape: [namespace:pod]"
  if ! kubectl create namespace "$ns" >"$_HI_WORKDIR/ns.run.log" 2>&1; then
    _hi_dump_log "Failed to create the namespace:" "$_HI_WORKDIR/ns.run.log"
    return 1
  fi
  if ! kubectl -n "$ns" run "$name" --image="$_HI_PAIR_IMAGE_SH" --image-pull-policy=IfNotPresent \
    --restart=Never --command -- sleep infinity >>"$_HI_WORKDIR/ns.run.log" 2>&1; then
    _hi_dump_log "Failed to create the namespaced pod:" "$_HI_WORKDIR/ns.run.log"
    kubectl delete namespace "$ns" --now >/dev/null 2>&1
    return 1
  fi
  if ! _hi_poll_bool 240 0.5 _hi_pod_running_in "$ns" "$name"; then
    kubectl -n "$ns" describe pod "$name" >"$_HI_WORKDIR/ns.describe.log" 2>&1 || true
    _hi_dump_log "Namespaced pod never reported Running:" "$_HI_WORKDIR/ns.describe.log"
    kubectl delete namespace "$ns" --now >/dev/null 2>&1
    return 1
  fi
  _hi_exec_case ns "kube path (namespace:pod)" "$_HI_TEST_MARKER" 90 \
    "$ns:$name" "$(_hi_probe_cmd "$_HI_TEST_MARKER" sh)" && ok=1
  kubectl delete namespace "$ns" --now >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}
function _hi_pod_running_in() { [ "$(kubectl -n "$1" get pod "$2" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }

function run_kube_test() {
  _hi_require kind
  _hi_require kubectl
  _hi_require_backend docker "not installed (kind needs it to run cluster nodes)"

  _hi_workdir kubetest _hi_kube_cleanup
  export KUBECONFIG="$_HI_WORKDIR/kubeconfig"
  _hi_h1 "Testing hi's kube path against a throwaway kind cluster"

  _hi_h2 "Creating kind cluster $_HI_CLUSTER"
  if ! kind create cluster --name "$_HI_CLUSTER" --kubeconfig "$KUBECONFIG" \
    >"$_HI_WORKDIR/kind.log" 2>&1; then
    _hi_dump_log "Kind cluster never came up:" "$_HI_WORKDIR/kind.log" "$YELLOW"
    _hi_stand_down "kind cluster never came up"
  fi
  _HI_CLUSTER_UP=1
  _hi_cecho " | Cluster up" "$GREEN"

  # Two gates, not one, and the preload runs across both.
  #
  # The default ServiceAccount is what lets a pod be admitted, so it has to
  # exist before `kubectl run` - but it shows up while the node is still
  # NotReady, and that is the trap: the cases used to start there, ~10s before
  # kindnet and CoreDNS had settled, so every `kubectl exec` in them was racing
  # the cluster's own startup. A session is eight API round trips (probe, shell
  # ladder, three file streams, the attach, the cleanup), and eight round trips
  # against a still-booting API server is exactly how a 30s case budget goes on
  # a runner slower than a laptop. Waiting for Ready costs wall clock the pod
  # poll was going to spend anyway, and buys a settled cluster to measure on.
  #
  # The preload is started first and collected after, because `crictl` talks to
  # the node's containerd directly - which is up long before the node is Ready -
  # so the pulls and the wait overlap instead of running in turn.
  if ! _hi_poll_bool 40 0.5 kubectl get serviceaccount default; then
    _hi_stand_down "no default ServiceAccount" \
      "default ServiceAccount never showed up, skipping"
  fi

  # buffered, not streamed: a background job writing straight to the terminal
  # would interleave with the wait below and break the ordered transcript the
  # rest of the suite keeps.
  _hi_kube_preload_images >"$_HI_WORKDIR/preload.out" 2>&1 &
  _HI_PRELOAD_PID=$!

  if ! kubectl wait --for=condition=Ready node --all --timeout=180s \
    >"$_HI_WORKDIR/ready.log" 2>&1; then
    _hi_dump_log "Nodes never reported Ready:" "$_HI_WORKDIR/ready.log" "$YELLOW"
    _hi_cecho " | Carrying on anyway - the pod poll below has its own budget" "$YELLOW"
  else
    _hi_cecho " | Node ready" "$GREEN"
  fi

  wait "$_HI_PRELOAD_PID" 2>/dev/null || true
  cat "$_HI_WORKDIR/preload.out" 2>/dev/null || true

  _HI_TEST_MARKER="HI_KUBE_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - kubectl exec -it will fail outright, results may be unreliable"

  _hi_backend_pair_cases kube "shape" _hi_kube_multi_container_case _hi_kube_namespace_case
}

run_kube_test
