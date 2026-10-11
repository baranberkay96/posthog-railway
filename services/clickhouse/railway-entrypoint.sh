#!/bin/bash
# Thin wrapper around the official ClickHouse entrypoint for PostHog on Railway.
set -euo pipefail

fail() { echo "FATAL: $*" >&2; exit 1; }

for v in CLICKHOUSE_PASSWORD CLICKHOUSE_API_PASSWORD CLICKHOUSE_APP_PASSWORD CLICKHOUSE_DICT_READER_PASSWORD KAFKA_HOSTS; do
  [ -n "${!v:-}" ] || fail "$v must be set (see the template variables)."
done

# Cluster replica host: this service's own private domain. PostHog's migration tooling
# connects to the hosts listed in system.clusters, so it must resolve from other services.
: "${CLICKHOUSE_CLUSTER_HOST:=${RAILWAY_PRIVATE_DOMAIN:-$(hostname)}}"
export CLICKHOUSE_CLUSTER_HOST

# Conventional private hostname of the ZooKeeper service if the reference is empty.
: "${ZOOKEEPER_HOST:=zookeeper.railway.internal}"
export ZOOKEEPER_HOST

# Fresh Railway volumes contain lost+found; ClickHouse does not need it.
rm -rf /var/lib/clickhouse/lost+found 2>/dev/null || true

# PostHog's ClickHouse migrations create views over system.crash_log, which ClickHouse
# only creates on the first log flush. Upstream's init-db.sh runs SYSTEM FLUSH LOGS for
# the same reason; do it once the server answers (in the background, on every start).
(
  for _ in $(seq 1 150); do
    if clickhouse client --host 127.0.0.1 --password "$CLICKHOUSE_PASSWORD" -q "SYSTEM FLUSH LOGS" >/dev/null 2>&1; then
      echo "railway: system log tables flushed"
      exit 0
    fi
    sleep 2
  done
  echo "railway: WARNING could not run SYSTEM FLUSH LOGS" >&2
) &

echo "railway: starting ClickHouse (cluster host=${CLICKHOUSE_CLUSTER_HOST}, zookeeper=${ZOOKEEPER_HOST}, kafka=${KAFKA_HOSTS})"
exec /entrypoint.sh "$@"
