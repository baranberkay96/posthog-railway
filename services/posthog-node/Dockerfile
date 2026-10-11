# PostHog Node.js services (plugins/CDP, ingestion, session replay, recording API,
# error tracking, logs and traces ingestion) with the GeoLite2 database baked in.
#
# The hobby compose mounts a host ./share directory with GeoLite2-City.mmdb; Railway
# has no shared host files, so the database is copied from PostHog's own livestream
# image (which ships it at /GeoLite2-City.mmdb). Without it GeoIP enrichment of
# events ($geoip_* properties) is disabled.
#
# The Node services' Kafka clients default to the compose hostname "kafka:9092"; the
# entrypoint points all of them at KAFKA_HOSTS.
#
# Node image: the one the hobby installer deploys (`posthog/posthog-node:latest` on Docker
# Hub, build 82ea668 of 2026-03-31), pinned by commit. Newer ghcr.io master builds write
# persons with ON CONFLICT (team_id, uuid), which needs the partitioned persons table that
# the hobby migrations skip, so person creation fails with them on a hobby schema.
FROM ghcr.io/posthog/posthog/livestream:397fc8862e1ca5121a8679f0f686afde88d70b14 AS geoip
RUN mkdir -p /share && cp /GeoLite2-City.mmdb /share/ \
 && printf '{"date": "%s"}\n' "$(date +%Y-%m-%d)" > /share/GeoLite2-City.json \
 && chmod 0755 /share && chmod 0644 /share/GeoLite2-City.mmdb /share/GeoLite2-City.json

FROM posthog/posthog-node:82ea6681305bb00ad4ca920e3ba6e8fb39157424

COPY --from=geoip /share /share

COPY --chmod=0755 railway-node-env.sh /usr/local/bin/railway-node-env.sh

ENV MMDB_FILE_LOCATION=/share/GeoLite2-City.mmdb

# Points every Kafka client at KAFKA_HOSTS, then runs the image command.
ENTRYPOINT ["/usr/local/bin/railway-node-env.sh"]
CMD ["node", "nodejs/dist/index.js"]

# Health/readiness: GET /_health on HTTP_SERVER_PORT (default 6738).
EXPOSE 6738
