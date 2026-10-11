# PostHog personhog: gRPC person/group service (router + replica) in one Railway service.
# Both binaries come from PostHog's images of the same commit and Debian base; they run
# as two processes (see railway-personhog.sh). Combined to stay under Railway's
# 25-service limit.
FROM ghcr.io/posthog/posthog/personhog-replica:sha-4fb044d AS replica

FROM ghcr.io/posthog/posthog/personhog-router:sha-4fb044d

COPY --from=replica /usr/local/bin/personhog-replica /usr/local/bin/personhog-replica
COPY --chmod=0755 railway-personhog.sh railway-supervise.sh /usr/local/bin/

# gRPC 50052 (router); health/readiness on 9101 (router, Railway check) and 9100 (replica).
EXPOSE 50052 9100 9101

ENTRYPOINT ["/usr/local/bin/railway-personhog.sh"]
