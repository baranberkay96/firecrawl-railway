#!/usr/bin/env bash
# Starts a group of Firecrawl worker processes in one container.
#
#   FIRECRAWL_WORKER_ROLE=worker      queue-worker, extract-worker, NuQ prefetch + reconciler
#   FIRECRAWL_WORKER_ROLE=nuq-worker  NUQ_WORKER_COUNT scrape executors (one job each)
#
# Mirrors the process list of apps/api/src/harness.ts (`--start-docker`). If any
# process exits, the others are stopped and the container exits non-zero so
# Railway's restart policy brings the whole group back.
set -uo pipefail
cd /app

export NUQ_REDUCE_NOISE=true
ROLE="${FIRECRAWL_WORKER_ROLE:-worker}"
pids=()

start() {
  local name="$1"
  shift
  echo "[railway-workers] starting ${name}"
  env "$@" &
  pids+=("$!")
}

stop_all() {
  if [ "${#pids[@]}" -gt 0 ]; then
    kill -TERM "${pids[@]}" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null
  fi
}

on_signal() {
  echo "[railway-workers] shutdown requested, stopping workers"
  stop_all
  exit 0
}
trap on_signal TERM INT

case "$ROLE" in
  worker)
    start queue-worker NUQ_POD_NAME=worker WORKER_PORT="${WORKER_PORT:-3005}" \
      node dist/src/services/queue-worker.js
    start extract-worker NUQ_POD_NAME=extract-worker EXTRACT_WORKER_PORT="${EXTRACT_WORKER_PORT:-3004}" \
      node dist/src/services/extract-worker.js
    start nuq-prefetch-worker NUQ_POD_NAME=nuq-prefetch-worker-0 NUQ_PREFETCH_REPLICAS=1 \
      NUQ_PREFETCH_WORKER_PORT="${NUQ_PREFETCH_WORKER_PORT:-3011}" \
      node dist/src/services/worker/nuq-prefetch-worker.js
    start nuq-reconciler NUQ_POD_NAME=nuq-reconciler-worker-0 \
      NUQ_RECONCILER_WORKER_PORT="${NUQ_RECONCILER_WORKER_PORT:-3012}" \
      node dist/src/services/worker/nuq-reconciler-worker.js
    ;;
  nuq-worker)
    count="${NUQ_WORKER_COUNT:-5}"
    base="${NUQ_WORKER_START_PORT:-3006}"
    for ((i = 0; i < count; i++)); do
      start "nuq-worker-${i}" NUQ_POD_NAME="nuq-worker-${i}" NUQ_WORKER_PORT="$((base + i))" \
        node dist/src/services/worker/nuq-worker.js
    done
    ;;
  *)
    echo "[railway-workers] unknown FIRECRAWL_WORKER_ROLE '${ROLE}' (expected worker or nuq-worker)" >&2
    exit 64
    ;;
esac

# Wait until any process exits, then take the group down so Railway restarts it.
wait -n
status=$?
echo "[railway-workers] a worker process exited with status ${status}; restarting the group" >&2
stop_all
exit 1
