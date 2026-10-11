# PostHog property-defs-rs: maintains event and property definitions from the events
# stream and from the LLM analytics stream, one process each (see
# railway-property-defs.sh). Upstream runs the image twice (property-defs-rs and
# property-defs-ai); combined here to stay under Railway's 25-service limit.
FROM ghcr.io/posthog/posthog/property-defs-rs:sha-000ac49

COPY --chmod=0755 railway-property-defs.sh railway-supervise.sh /usr/local/bin/

# Health/readiness: GET /_readiness on 3301 (events, Railway check) and 3303 (ai).
EXPOSE 3301 3303

ENTRYPOINT ["/usr/local/bin/railway-property-defs.sh"]
