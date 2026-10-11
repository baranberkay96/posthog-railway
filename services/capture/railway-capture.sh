#!/bin/bash
# Runs PostHog's three Rust capture processes in one Railway service (upstream runs them
# as the `capture`, `capture-ai` and `replay-capture` containers of the same image):
#   events      CAPTURE_EVENTS_PORT (3000)  /e, /i/v0, /batch, /capture, /i/v1/analytics/events
#   ai          CAPTURE_AI_PORT     (3001)  /i/v0/ai, /i/v1/ai/events
#   recordings  CAPTURE_REPLAY_PORT (3002)  /s (session replay snapshots)
# Shared settings (KAFKA_HOSTS, REDIS_URL, RUST_LOG, ...) come from the service variables;
# the mode-specific Kafka topics below are PostHog's fixed topic names, as in the
# hobby compose.
#
# LLM analytics events: this capture build sends them to a separate "AI lane" topic
# (events_plugin_ingestion_ai) that only newer Node ingestion builds consume. The
# pinned Node build (the one the hobby installer deploys) reads AI events from the main
# lane and splits large AI payloads into the ai_events table itself
# (INGESTION_AI_EVENT_SPLITTING_ENABLED on `ingestion`), so CAPTURE_AI_LANE_TOPIC
# defaults to the main topic. Set it to events_plugin_ingestion_ai only together with
# a Node image that consumes that topic.
set -euo pipefail

: "${KAFKA_HOSTS:?KAFKA_HOSTS must be set}"
EVENTS_PORT="${CAPTURE_EVENTS_PORT:-3000}"
AI_PORT="${CAPTURE_AI_PORT:-3001}"
REPLAY_PORT="${CAPTURE_REPLAY_PORT:-3002}"
AI_TOPIC="${CAPTURE_AI_LANE_TOPIC:-events_plugin_ingestion}"
if [ "$AI_TOPIC" = "events_plugin_ingestion" ]; then
  AI_HISTORICAL=events_plugin_ingestion_historical
  AI_OVERFLOW=events_plugin_ingestion_overflow
else
  AI_HISTORICAL="$AI_TOPIC"
  AI_OVERFLOW="$AI_TOPIC"
fi

# shellcheck source=railway-supervise.sh
. /usr/local/bin/railway-supervise.sh

v1_sink() {
  # main historical overflow
  echo "CAPTURE_V1_SINKS=msk" \
    "CAPTURE_V1_SINK_MSK_KAFKA_HOSTS=${KAFKA_HOSTS}" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_MAIN=$1" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_HISTORICAL=$2" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_OVERFLOW=$3" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_DLQ=events_plugin_ingestion_dlq" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_EXCEPTION=ingestion-errortracking-main" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_HEATMAP=heatmaps_ingestion" \
    "CAPTURE_V1_SINK_MSK_KAFKA_TOPIC_CLIENT_INGESTION_WARNING=ingestion-clientwarnings-main-1"
}

# shellcheck disable=SC2046  # v1_sink output is a list of VAR=value words without spaces
spawn "events (port ${EVENTS_PORT})" env \
  CAPTURE_MODE=events \
  ADDRESS="[::]:${EVENTS_PORT}" \
  KAFKA_TOPIC=events_plugin_ingestion \
  CAPTURE_OUTPUT_ANALYTICS_MAIN_TOPIC=events_plugin_ingestion \
  KAFKA_ERROR_TRACKING_TOPIC=ingestion-errortracking-main \
  CAPTURE_OUTPUT_ERROR_TRACKING_TOPIC=ingestion-errortracking-main \
  CAPTURE_OUTPUT_AI_MAIN_TOPIC="$AI_TOPIC" \
  $(v1_sink events_plugin_ingestion events_plugin_ingestion_historical events_plugin_ingestion_overflow) \
  /usr/local/bin/capture

# shellcheck disable=SC2046
spawn "ai (port ${AI_PORT})" env \
  CAPTURE_MODE=ai \
  ADDRESS="[::]:${AI_PORT}" \
  KAFKA_TOPIC="$AI_TOPIC" \
  CAPTURE_OUTPUT_ANALYTICS_MAIN_TOPIC="$AI_TOPIC" \
  CAPTURE_OUTPUT_AI_MAIN_TOPIC="$AI_TOPIC" \
  $(v1_sink "$AI_TOPIC" "$AI_HISTORICAL" "$AI_OVERFLOW") \
  /usr/local/bin/capture

spawn "recordings (port ${REPLAY_PORT})" env \
  CAPTURE_MODE=recordings \
  ADDRESS="[::]:${REPLAY_PORT}" \
  KAFKA_TOPIC=session_recording_snapshot_item_events \
  CAPTURE_OUTPUT_SESSION_REPLAY_MAIN_TOPIC=session_recording_snapshot_item_events \
  /usr/local/bin/capture

supervise
