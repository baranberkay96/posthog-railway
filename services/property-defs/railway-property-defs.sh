#!/bin/bash
# Runs PostHog's two property-defs-rs consumers in one Railway service (upstream:
# `property-defs-rs` and `property-defs-ai`, same image):
#   events  BIND_PORT 3301  default topic and consumer group (event and property definitions)
#   ai      BIND_PORT 3303  clickhouse_ai_events_json / property-defs-ai (LLM analytics events)
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must be set}"
: "${KAFKA_HOSTS:?KAFKA_HOSTS must be set}"

# shellcheck source=railway-supervise.sh
. /usr/local/bin/railway-supervise.sh

spawn "events (port ${PROPERTY_DEFS_EVENTS_PORT:-3301})" env \
  -u KAFKA_CONSUMER_TOPIC -u KAFKA_CONSUMER_GROUP \
  BIND_PORT="${PROPERTY_DEFS_EVENTS_PORT:-3301}" \
  /usr/local/bin/property-defs-rs

spawn "ai (port ${PROPERTY_DEFS_AI_PORT:-3303})" env \
  KAFKA_CONSUMER_TOPIC=clickhouse_ai_events_json \
  KAFKA_CONSUMER_GROUP=property-defs-ai \
  BIND_PORT="${PROPERTY_DEFS_AI_PORT:-3303}" \
  /usr/local/bin/property-defs-rs

supervise
