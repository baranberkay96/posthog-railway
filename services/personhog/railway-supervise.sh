#!/bin/bash
# Minimal supervisor for running several PostHog processes in one Railway service.
#
# Railway deploys at most 25 services per template, so closely related PostHog
# processes that upstream runs as separate containers share one service here.
# Sourced by the service's start script, which calls `spawn` once per process and
# then `supervise`.
#
# Behaviour: every process gets SIGTERM when the service stops. If any process exits,
# the others are stopped and the script exits non-zero, so Railway's restart policy
# restarts the whole service (no half-running service).

RAILWAY_PIDS=()
RAILWAY_NAMES=()

# spawn NAME COMMAND [ARGS...]  (use `env VAR=value ...` to set per-process variables)
spawn() {
  local name="$1"
  shift
  "$@" &
  RAILWAY_PIDS+=("$!")
  RAILWAY_NAMES+=("$name")
  echo "railway: started ${name} (pid $!)"
}

railway_stop_all() {
  local pid
  for pid in "${RAILWAY_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait || true
}

supervise() {
  trap 'echo "railway: stop requested"; railway_stop_all; exit 0' TERM INT
  local code=0 i
  wait -n || code=$?
  for i in "${!RAILWAY_PIDS[@]}"; do
    if ! kill -0 "${RAILWAY_PIDS[$i]}" 2>/dev/null; then
      echo "railway: ${RAILWAY_NAMES[$i]} exited (code ${code}); stopping the other processes so the service restarts" >&2
    fi
  done
  railway_stop_all
  if [ "$code" -eq 0 ]; then
    code=1
  fi
  exit "$code"
}
