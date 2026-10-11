# PostHog feature-flags service (Rust) with the GeoLite2 database baked in, so flag
# conditions on GeoIP properties evaluate as in the hobby compose (which mounts a host
# ./share directory). The database is copied from PostHog's livestream image.
FROM ghcr.io/posthog/posthog/livestream:397fc8862e1ca5121a8679f0f686afde88d70b14 AS geoip
RUN mkdir -p /share && cp /GeoLite2-City.mmdb /share/ \
 && printf '{"date": "%s"}\n' "$(date +%Y-%m-%d)" > /share/GeoLite2-City.json \
 && chmod 0755 /share && chmod 0644 /share/GeoLite2-City.mmdb /share/GeoLite2-City.json

FROM ghcr.io/posthog/posthog/feature-flags:sha-3dc6352

COPY --from=geoip /share /share

ENV MAXMIND_DB_PATH=/share/GeoLite2-City.mmdb

EXPOSE 3001
