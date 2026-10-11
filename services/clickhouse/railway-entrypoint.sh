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

# Railway registers this service's private DNS name only after the deployment is up
# (after the /ping healthcheck), so at boot ClickHouse cannot resolve its own cluster
# host and builds the posthog clusters with no replicas (PostHog then migrates nothing).
# Once the name resolves, drop the DNS cache and reload the config to rebuild them.
(
  until getent hosts "$CLICKHOUSE_CLUSTER_HOST" >/dev/null 2>&1; do sleep 5; done
  for _ in $(seq 1 120); do
    clickhouse client --host 127.0.0.1 --password "$CLICKHOUSE_PASSWORD" -q "SYSTEM DROP DNS CACHE" >/dev/null 2>&1 || true
    clickhouse client --host 127.0.0.1 --password "$CLICKHOUSE_PASSWORD" -q "SYSTEM RELOAD CONFIG" >/dev/null 2>&1 || true
    n="$(clickhouse client --host 127.0.0.1 --password "$CLICKHOUSE_PASSWORD" -q "SELECT count() FROM system.clusters WHERE cluster = 'posthog'" 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
      echo "railway: cluster host ${CLICKHOUSE_CLUSTER_HOST} resolves; posthog cluster ready"
      exit 0
    fi
    sleep 5
  done
  echo "railway: WARNING posthog cluster still empty after config reloads" >&2
) &

echo "railway: starting ClickHouse (cluster host=${CLICKHOUSE_CLUSTER_HOST}, zookeeper=${ZOOKEEPER_HOST}, kafka=${KAFKA_HOSTS})"
exec /entrypoint.sh "$@"
