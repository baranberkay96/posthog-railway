# ClickHouse for PostHog on Railway.
#
# Same server line as PostHog's docker-compose.base.yml (26.9), plus the files the
# hobby compose bind-mounts from the PostHog repository. Railway cannot bind-mount
# host files and the data volume hides anything baked under /var/lib/clickhouse,
# so the files are fetched at build time from the pinned PostHog commit and placed
# under /etc/clickhouse-server:
#   docker/clickhouse/config.xml, users.xml, user_defined_function.xml
#   posthog/idl/*.json            -> format_schemas/ (was docker-entrypoint-initdb.d/init-db.sh)
#   posthog/user_scripts/*        -> user_scripts/   (UDF wrappers + x86_64/aarch64 binaries)
# Railway-specific overrides (cluster hosts, passwords, ZooKeeper host, smaller caches,
# console logging) live in config.d/ and users.d/.
FROM clickhouse/clickhouse-server:26.9.15.5

# PostHog commit the config files are taken from. Keep it equal to the web image tag.
ARG POSTHOG_COMMIT=716405ddea318758493221f26e844512757c7927

RUN set -eux; \
    base="https://raw.githubusercontent.com/PostHog/posthog/${POSTHOG_COMMIT}"; \
    arch="$(uname -m)"; [ "$arch" = "aarch64" ] || arch="x86_64"; \
    etc=/etc/clickhouse-server; \
    mkdir -p "$etc/user_scripts" "$etc/format_schemas"; \
    for f in config.xml users.xml user_defined_function.xml; do \
        wget -q -O "$etc/$f" "$base/docker/clickhouse/$f"; \
    done; \
    for f in events_dead_letter_queue events_json groups person person_distinct_id person_distinct_id2 plugin_log_entries; do \
        wget -q -O "$etc/format_schemas/$f.json" "$base/posthog/idl/$f.json"; \
    done; \
    for f in run_udf.sh aggregate_funnel decompress_udf json_clean_posthog_event_properties_udf json_drop_keys_udf \
             json_strip_empty_strings_and_nulls_udf aggregate_funnel_test.py aggregate_funnel_array_trends_test.py; do \
        wget -q -O "$etc/user_scripts/$f" "$base/posthog/user_scripts/$f"; \
    done; \
    for b in aggregate_funnel decompress_udf json_clean_posthog_event_properties_udf json_drop_keys_udf \
             json_strip_empty_strings_and_nulls_udf; do \
        wget -q -O "$etc/user_scripts/${b}_${arch}" "$base/posthog/user_scripts/${b}_${arch}"; \
    done; \
    chmod 0644 "$etc/config.xml" "$etc/users.xml" "$etc/user_defined_function.xml" "$etc"/format_schemas/*; \
    chmod 0755 "$etc"/user_scripts/*; \
    grep -q '<clickhouse>' "$etc/config.xml"; \
    grep -q 'aggregate_funnel' "$etc/user_defined_function.xml"

COPY config.d/ /etc/clickhouse-server/config.d/
COPY users.d/ /etc/clickhouse-server/users.d/
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0644 /etc/clickhouse-server/config.d/*.xml /etc/clickhouse-server/users.d/*.xml \
 && chmod 0755 /usr/local/bin/railway-entrypoint.sh

# Users come from users.xml + users.d (passwords from the environment), not from the
# image entrypoint's CLICKHOUSE_USER/CLICKHOUSE_PASSWORD handling.
ENV CLICKHOUSE_SKIP_USER_SETUP=1

EXPOSE 8123 9000

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
