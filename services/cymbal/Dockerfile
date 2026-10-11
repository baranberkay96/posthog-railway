# PostHog cymbal (error tracking: processing + symbol resolution, Rust) with the GeoLite2
# database baked in, replacing the hobby compose's host ./share mount (copied from
# PostHog's livestream image). Processing and resolution run as two processes of the
# same image (see railway-cymbal.sh); upstream runs two containers, combined here to
# stay under Railway's 25-service limit.
FROM ghcr.io/posthog/posthog/livestream:397fc8862e1ca5121a8679f0f686afde88d70b14 AS geoip
RUN mkdir -p /share && cp /GeoLite2-City.mmdb /share/ \
 && printf '{"date": "%s"}\n' "$(date +%Y-%m-%d)" > /share/GeoLite2-City.json \
 && chmod 0755 /share && chmod 0644 /share/GeoLite2-City.mmdb /share/GeoLite2-City.json

FROM ghcr.io/posthog/posthog/cymbal:sha-ef168ea

COPY --from=geoip /share /share
COPY --chmod=0755 railway-cymbal.sh railway-supervise.sh /usr/local/bin/

ENV MAXMIND_DB_PATH=/share/GeoLite2-City.mmdb

# Health/readiness: GET /_readiness on 3302 (processing, Railway check).
EXPOSE 3302

ENTRYPOINT ["/usr/local/bin/railway-cymbal.sh"]
