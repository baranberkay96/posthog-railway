#!/bin/bash
# Starts PostHog's Node server.
#
# NODE_PROCESSES unset: one process, mode taken from PLUGIN_SERVER_MODE (or the default
# plugin-server capabilities when that is unset too).
#
# NODE_PROCESSES="mode:port mode:port ...": one process per entry in this service, each
# with its own PLUGIN_SERVER_MODE and HTTP_SERVER_PORT (health and API port). Used to
# keep the template under Railway's 25-service limit, e.g.
#   "ingestion-v2-combined:6738 ingestion-errortracking:6739"
#   "recordings-blob-ingestion-v2:6738 recording-api:6739"
set -euo pipefail

if [ -z "${NODE_PROCESSES:-}" ]; then
  exec node nodejs/dist/index.js
fi

# shellcheck source=railway-supervise.sh
. /usr/local/bin/railway-supervise.sh

for spec in $NODE_PROCESSES; do
  mode="${spec%%:*}"
  port="${spec##*:}"
  case "$port" in
    ''|*[!0-9]*) echo "FATAL: NODE_PROCESSES entry '${spec}' must be mode:port" >&2; exit 1 ;;
  esac
  if [ -z "$mode" ] || [ "$mode" = "$spec" ]; then
    echo "FATAL: NODE_PROCESSES entry '${spec}' must be mode:port" >&2
    exit 1
  fi
  spawn "${mode} (port ${port})" env PLUGIN_SERVER_MODE="$mode" HTTP_SERVER_PORT="$port" node nodejs/dist/index.js
done

supervise
