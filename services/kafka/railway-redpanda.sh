#!/bin/bash
# Single-node Redpanda for PostHog on Railway.
# - Kafka API on :9092, advertised under the Railway private domain.
# - Admin API on :9644 (/v1/status/ready is the Railway healthcheck).
# - Creates PostHog's topics after start and applies the retention settings.
set -euo pipefail

DATA_DIR=/var/lib/redpanda/data
ADVERTISE_HOST="${KAFKA_ADVERTISE_HOST:-${RAILWAY_PRIVATE_DOMAIN:-$(hostname)}}"
SMP="${REDPANDA_SMP:-1}"
MEMORY="${REDPANDA_MEMORY:-1G}"
RETENTION_MS="${KAFKA_LOG_RETENTION_MS:-86400000}"
TOPICS_FILE=/etc/redpanda/posthog-topics.txt

mkdir -p "$DATA_DIR"
rm -rf "$DATA_DIR/lost+found" 2>/dev/null || true
if [ "$(stat -c %u "$DATA_DIR")" != "$(id -u redpanda)" ]; then
  chown -R redpanda:redpanda "$DATA_DIR"
fi

# rpk reads ~/.config/rpk; HOME must point somewhere the redpanda user can read.
export HOME=/var/lib/redpanda
as_redpanda() { setpriv --reuid=redpanda --regid=redpanda --init-groups "$@"; }

init_cluster() {
  until as_redpanda rpk cluster health --exit-when-healthy --watch >/dev/null 2>&1; do sleep 2; done
  as_redpanda rpk cluster config set log_retention_ms "$RETENTION_MS" >/dev/null || true
  local topic created=0
  while read -r topic; do
    case "$topic" in ''|'#'*) continue ;; esac
    if as_redpanda rpk topic create "$topic" -p 1 -r 1 >/dev/null 2>&1; then
      created=$((created + 1))
    elif ! as_redpanda rpk topic describe "$topic" >/dev/null 2>&1; then
      echo "railway: WARNING could not create topic $topic" >&2
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$TOPICS_FILE")
  echo "railway: PostHog topics ready ($created created, retention ${RETENTION_MS} ms)"
}

init_cluster &

echo "railway: starting Redpanda (advertise ${ADVERTISE_HOST}:9092, smp ${SMP}, memory ${MEMORY})"
exec setpriv --reuid=redpanda --regid=redpanda --init-groups \
  rpk redpanda start \
    --mode dev-container \
    --smp "$SMP" \
    --memory "$MEMORY" \
    --reserve-memory 0M \
    --overprovisioned \
    --kafka-addr "internal://[::]:9092" \
    --advertise-kafka-addr "internal://${ADVERTISE_HOST}:9092" \
    --rpc-addr "0.0.0.0:33145" \
    --advertise-rpc-addr "127.0.0.1:33145" \
    --default-log-level=warn
