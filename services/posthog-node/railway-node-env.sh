#!/bin/sh
# PostHog's Node services create several Kafka clients (consumer, main producer,
# ingestion upstream/downstream, session replay, CDP, logs/metrics, warehouse, ...),
# each with its own KAFKA_<TARGET>_METADATA_BROKER_LIST setting that defaults to
# "kafka:9092" - the compose hostname. On Railway the broker is reached by its private
# domain, so every unset broker list is pointed at KAFKA_HOSTS, as in the hobby stack
# where all of them resolve to the same broker.
set -eu

: "${KAFKA_HOSTS:?KAFKA_HOSTS must be set (Kafka bootstrap server, e.g. kafka.railway.internal:9092)}"

for target in \
  KAFKA_CONSUMER KAFKA_PRODUCER KAFKA_CDP_PRODUCER KAFKA_MONITORING_PRODUCER \
  KAFKA_METRICS_PRODUCER KAFKA_WAREHOUSE_PRODUCER KAFKA_WARPSTREAM_PRODUCER \
  KAFKA_INGESTION_PRODUCER KAFKA_INGESTION_UPSTREAM_PRODUCER KAFKA_INGESTION_DOWNSTREAM_PRODUCER \
  KAFKA_INGESTION_SESSIONREPLAY_PRODUCER KAFKA_WARPSTREAM_INGESTION_PRODUCER \
  KAFKA_WARPSTREAM_CYCLOTRON_PRODUCER KAFKA_WARPSTREAM_LOGS_PRODUCER \
  KAFKA_WARPSTREAM_METRICS_PRODUCER CDP_INTERNAL_EVENTS_CONSUMER
do
  var="${target}_METADATA_BROKER_LIST"
  eval "current=\${${var}:-}"
  if [ -z "$current" ]; then
    export "${var}=${KAFKA_HOSTS}"
  fi
done

exec "$@"
