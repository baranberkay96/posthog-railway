#!/bin/bash
# Runs personhog-replica and personhog-router in one Railway service (upstream: two
# containers). The replica serves persons/groups from Postgres on 127.0.0.1:50051
# (container-local); the router, which web, workers and ingestion call, listens on
# [::]:50052 and forwards to it.
set -euo pipefail

: "${PRIMARY_DATABASE_URL:?PRIMARY_DATABASE_URL must be set (persons database)}"

# shellcheck source=railway-supervise.sh
. /usr/local/bin/railway-supervise.sh

spawn "personhog-replica (grpc 127.0.0.1:50051)" env \
  GRPC_ADDRESS=127.0.0.1:50051 \
  METRICS_PORT="${REPLICA_METRICS_PORT:-9100}" \
  /usr/local/bin/personhog-replica

spawn "personhog-router (grpc [::]:50052)" env \
  GRPC_ADDRESS="[::]:50052" \
  METRICS_PORT="${ROUTER_METRICS_PORT:-9101}" \
  REPLICA_URL=http://127.0.0.1:50051 \
  /usr/local/bin/personhog-router

supervise
