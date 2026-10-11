#!/bin/bash
# Runs cymbal's processing and resolution modes in one Railway service (upstream:
# `cymbal` and `cymbal-resolution`, same image).
#   resolution  gRPC 127.0.0.1:50061 (container-local), metrics/health 9101
#   processing  HTTP [::]:3302 (Node error-tracking ingestion calls it), uses the local resolver
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must be set}"

# shellcheck source=railway-supervise.sh
. /usr/local/bin/railway-supervise.sh

spawn "cymbal-resolution (grpc 127.0.0.1:50061)" env \
  CYMBAL_MODE=resolution \
  GRPC_ADDRESS=127.0.0.1:50061 \
  METRICS_PORT="${RESOLUTION_METRICS_PORT:-9101}" \
  /usr/local/bin/cymbal

spawn "cymbal processing (port ${BIND_PORT:-3302})" env \
  -u CYMBAL_MODE \
  BIND_HOST="${BIND_HOST:-::}" \
  BIND_PORT="${BIND_PORT:-3302}" \
  CYMBAL_REMOTE_RESOLUTION_HOST=127.0.0.1 \
  CYMBAL_REMOTE_RESOLUTION_PORT=50061 \
  /usr/local/bin/cymbal

supervise
