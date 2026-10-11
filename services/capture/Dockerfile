# PostHog Rust capture: events, LLM analytics (ai) and session replay (recordings) capture
# in one Railway service, one process per mode (see railway-capture.sh). Upstream runs
# the same image three times; the template does this to stay under Railway's
# 25-service limit.
FROM ghcr.io/posthog/posthog/capture:sha-14a43b7

COPY --chmod=0755 railway-capture.sh railway-supervise.sh /usr/local/bin/

# Health/readiness: GET /_readiness on each mode's port (3000 events is the Railway check).
EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/local/bin/railway-capture.sh"]
