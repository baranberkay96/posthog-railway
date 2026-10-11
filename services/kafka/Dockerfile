# Kafka-compatible broker for PostHog on Railway: Redpanda, as in PostHog's
# docker-compose.base.yml, plus the topic pre-creation that the hobby stack runs
# in its one-shot `kafka-init` container. Here it runs inside the broker container
# after every start (idempotent), so no separate init service has to finish first.
FROM redpandadata/redpanda:v26.2.4

# PostHog commit the topic list is taken from. Keep it equal to the web image tag.
ARG POSTHOG_COMMIT=716405ddea318758493221f26e844512757c7927

USER root
ADD https://raw.githubusercontent.com/PostHog/posthog/${POSTHOG_COMMIT}/docker/kafka/topics.txt /etc/redpanda/posthog-topics.txt
COPY railway-redpanda.sh /usr/local/bin/railway-redpanda.sh
RUN chmod 0644 /etc/redpanda/posthog-topics.txt \
 && chmod 0755 /usr/local/bin/railway-redpanda.sh \
 && grep -q '^events_plugin_ingestion_overflow$' /etc/redpanda/posthog-topics.txt

EXPOSE 9092 9644

# Starts as root only to fix ownership of the Railway volume, then drops to `redpanda`.
ENTRYPOINT ["/usr/local/bin/railway-redpanda.sh"]
