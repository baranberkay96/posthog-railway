# PostHog Product Analytics Suite — Railway template spec

## Listing

- **Name:** PostHog Product Analytics Suite
  - No version label: PostHog does not publish versioned releases of the self-hosted stack (the hobby installer deploys a commit of `master`; its own script says "PostHog don't create tagged releases anymore"). The template pins exact commit-SHA image tags instead (see below). Same rule as other stacks without one upstream version.
- **Description (75 chars):** Self-hosted product analytics, session replay, feature flags and A/B tests.
- **Category:** Analytics
- **Tags:** posthog, analytics, product-analytics, session-replay, feature-flags, ab-testing, clickhouse, kafka
- **Template repo:** `baranberkay96/posthog-railway` (this folder)

## Base market template

- **No usable market base.** The only self-hosted entry, `posthog-1` "PostHog" (12 active / 185 total projects), runs 20 services from third-party images `ghcr.io/hexatare/posthog-railway-template/*:latest` (unpinned, not published by PostHog) with hardcoded secrets (`SECRET_KEY`, `ENCRYPTION_SALT_KEYS`, MinIO root credentials, `posthog`/`posthog` Postgres, `apipass`/`apppass` ClickHouse users), a public TCP proxy on a password-less Redis and a broken `CLICKHOUSE_HOST` value on the Temporal worker. Read for the overall Railway topology only; nothing copied (no license).
- `posthog-proxy` (verified, 50 active) and `qHvw-4` "PostHog Proxy": reverse proxies for PostHog Cloud, not a self-hosted PostHog. Not used.
- `_upstream/PostHog__posthog-nginx-reverse-proxy`, `_upstream/paulocsanz__posthog-proxy`: Cloud proxies. Not used.
- **Built from upstream instead:** PostHog's `docker-compose.hobby.yml` + `docker-compose.base.yml` at commit `716405ddea318758493221f26e844512757c7927` (master, 2026-10-11), service by service.

## Pinned versions

PostHog publishes every master build as `sha-<commit>` tags. Images are built only when their part of the monorepo changes, so each image is pinned to the commit of its current `master` build (resolved from the image's `org.opencontainers.image.revision` label, 2026-10-11). Exception: the Node image is the one the hobby installer actually deploys (`posthog/posthog-node:latest` on Docker Hub, last pushed 2026-03-31). The current ghcr.io master build was tested and fails person creation on the hobby database layout (it writes with `ON CONFLICT (team_id, uuid)`, which needs the partitioned persons table that hobby migrations skip).

| Service(s) | Image | Tag / revision | Built |
|---|---|---|---|
| web, worker, temporal-django-worker | `posthog/posthog` | `sha-716405ddea318758493221f26e844512757c7927` | 2026-10-11 |
| plugins, ingestion, recordings (via `services/posthog-node`) | `posthog/posthog-node` | `82ea6681305bb00ad4ca920e3ba6e8fb39157424` (= the `latest` tag the hobby installer pulls) | 2026-03-31 |
| capture (via `services/capture`: events, ai, recordings processes) | `ghcr.io/posthog/posthog/capture` | `sha-14a43b7` | 2026-10-09 |
| capture-logs | `ghcr.io/posthog/posthog/capture-logs` | `sha-04cdf1c` | 2026-10-10 |
| property-defs (via `services/property-defs`: events and ai processes) | `ghcr.io/posthog/posthog/property-defs-rs` | `sha-000ac49` | 2026-10-07 |
| feature-flags (via `services/feature-flags`) | `ghcr.io/posthog/posthog/feature-flags` | `sha-3dc6352` | 2026-10-08 |
| hypercache-server | `ghcr.io/posthog/posthog/hypercache-server` | `sha-14bcc04` | 2026-10-07 |
| personhog (via `services/personhog`: router + replica processes) | `ghcr.io/posthog/posthog/personhog-router` + `personhog-replica` binary | `sha-4fb044d` | 2026-10-07 |
| cymbal (via `services/cymbal`: processing + resolution processes) | `ghcr.io/posthog/posthog/cymbal` | `sha-ef168ea` | 2026-10-09 |
| livestream (+ GeoLite2 source for the wrappers) | `ghcr.io/posthog/posthog/livestream` | `397fc8862e1ca5121a8679f0f686afde88d70b14` | 2026-10-08 |
| clickhouse (`services/clickhouse`) | `clickhouse/clickhouse-server` | `26.9.15.5` (upstream compose: `26.9.13.15`) | 2026-10 |
| zookeeper | `zookeeper` | `3.9.6` (upstream: `3.7.0`, end of life) | 2026 |
| kafka (`services/kafka`) | `redpandadata/redpanda` | `v26.2.4` (upstream: `v25.1.9`) | 2026-10-06 |
| temporal | `temporalio/auto-setup` | `1.29.7` (last auto-setup line; upstream: `1.26.2`) | 2026-06-12 |
| browserless | `ghcr.io/browserless/chromium` | `v2.57.0` (upstream: `v2.51.2`) | 2026-09-30 |
| seaweedfs (`services/seaweedfs`; serves both upstream stores) | `chrislusf/seaweedfs` | `4.48` (upstream: `4.29`; PostHog requires >= 4.05) | 2026-09-28 |
| proxy (`services/proxy`) | `caddy` | `2.11.7-alpine` | 2026 |
| Redis | `redis` | `7.2.16-alpine` (upstream: `7.2-alpine`; PostHog lists Redis >= 7.0, < 8.0) | 2026 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` (Railway base; upstream: `postgres:15.12`; PostHog requires >= 14) | Railway base |

ClickHouse config files, UDF scripts, Kafka topic list: fetched at build time from the same PostHog commit (`ARG POSTHOG_COMMIT` in `services/clickhouse` and `services/kafka`).

## Architecture

Only `proxy` has a public domain. Everything else is on Railway's private network. 23 services.

```
 Browser / SDKs ── HTTPS ──> [proxy :8080 Caddy]
   /e /i/v0 /batch /capture ──> capture :3000 (events) ─┐
   /i/v0/ai ───────────────────> capture :3001 (ai) ────┤
   /s ─────────────────────────> capture :3002 (recordings) ──> [kafka (Redpanda)] ──> ClickHouse Kafka tables
   /i/v1/logs|traces|metrics ──> capture-logs ──────────┘          │
   /flags ─────────────────────> feature-flags                     ├──> ingestion (events + error tracking) ──> personhog ──> Postgres; cymbal; kafka ──> ClickHouse
   /surveys /array/* ──────────> hypercache-server                 ├──> recordings (blob ingestion) ──> seaweedfs
   /public/webhooks ───────────> plugins (CDP, logs, traces)       ├──> plugins (CDP, logs and traces ingestion)
   /livestream ────────────────> livestream (SSE)                  ├──> property-defs (events + ai) ──> Postgres
   /posthog/* (presigned) ─────> seaweedfs                         └──> livestream
   everything else ────────────> web (Django)
 web / worker / temporal-django-worker ──> Postgres, Redis, ClickHouse, seaweedfs, recordings :6739 (recording API), personhog, temporal, browserless
 ClickHouse ──> zookeeper (distributed DDL)        temporal ──> Postgres (temporal, temporal_visibility)
```

- SDKs send events to `capture` (Rust), which writes them to Kafka. `ingestion` (Node, `ingestion-v2-combined` process) processes them (persons, groups, GeoIP, transformations) and produces rows that ClickHouse consumes through its Kafka engine tables. Exception events go to the error-tracking process of the same service, which calls `cymbal`.
- Session replay snapshots go `capture` (recordings process) → Kafka → `recordings` (blob ingestion process) → `seaweedfs`; the recording API process of `recordings` serves them back for playback.
- Django (`web`) serves the UI and API, runs all migrations in its pre-deploy step and queries ClickHouse. `worker` runs Celery tasks and the RedBeat scheduler; `temporal-django-worker` runs Temporal workflows (batch exports, data warehouse imports, subscriptions).
- Feature flags are evaluated by the Rust `feature-flags` service; surveys and remote config by `hypercache-server`.

## Consolidation for Railway's 25-service limit

Railway deploys at most 25 services from one template. The hobby stack has 34 long-running containers that map to Railway services, so related processes share a service. Nothing PostHog runs in the hobby stack is dropped; every upstream process still runs with the same image and settings.

| Template service | Upstream containers it replaces | How |
|---|---|---|
| `plugins` | `plugins`, `ingestion-logs`, `ingestion-traces` | One Node process with `NODEJS_CAPABILITY_GROUPS=cdp_workflows,realtime_cohorts,logs,traces,feature_flags`: the plugin server's default capability set (which already includes logs ingestion) plus traces ingestion. PostHog's own capability-group mechanism, no extra process. |
| `ingestion` | `ingestion-general`, `ingestion-error-tracking` | Two Node processes (`NODE_PROCESSES`, ports 6738/6739). |
| `recordings` | `ingestion-sessionreplay`, `recording-api` | Two Node processes (`NODE_PROCESSES`, ports 6738/6739); web calls the recording API on 6739. |
| `capture` | `capture`, `capture-ai`, `replay-capture` | Three processes of the capture image (ports 3000/3001/3002), one per `CAPTURE_MODE`; the proxy routes each path to its port. |
| `property-defs` | `property-defs-rs`, `property-defs-ai` | Two processes (ports 3301/3303), the AI one on `clickhouse_ai_events_json` with its own consumer group. |
| `personhog` | `personhog-router`, `personhog-replica` | Two processes; the replica listens on container-local `127.0.0.1:50051`, the router on `[::]:50052`. |
| `cymbal` | `cymbal`, `cymbal-resolution` | Two processes; the resolution gRPC server is container-local (`127.0.0.1:50061`). |
| `seaweedfs` | `objectstorage`, `seaweedfs` | One SeaweedFS S3 store. Upstream's two stores held different data under different key prefixes (exports, media, HyperCache and AI blobs vs. recordings and symbol sets); they now share the `posthog` bucket (plus `ai-blobs`) and one set of credentials. |
| `Redis` | `redis7`, `valkey` | The pinned Node build does not use Valkey (only newer builds dual-write CDP state to it); `CDP_VALKEY_*` point at Redis so an upgrade keeps starting. |

Multi-process services use a small supervisor (`railway-supervise.sh` in each service folder): every process gets SIGTERM on stop, and if one process exits the others are stopped and the service exits non-zero, so Railway's `ALWAYS` restart policy restarts the whole service instead of leaving it half-running. Logs of all processes go to the service's log stream; the `railway: started ...` lines at start list each process and its PID.

Trade-offs: processes that share a service scale together (add replicas to `capture` and you get more of all three capture modes) and share one memory limit; a crash in one restarts its siblings. For the hobby-scale volumes this template targets, that is acceptable; if one process needs to scale alone, deploy the same image as an extra service with a single mode (`NODE_PROCESSES` unset and `PLUGIN_SERVER_MODE` set, or the upstream image with the `CAPTURE_MODE`/topic variables from `railway-capture.sh`).

## Services

<!-- BEGIN SERVICES -->

### proxy

Caddy router that owns the public domain and forwards each path to the right PostHog service (same routing table as the hobby compose proxy). TLS is terminated by Railway.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/proxy` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_proxy/health` (timeout 120 s)
- Public domain: yes, target port `8080`
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Caddy listen port (public domain target). |
| `WEB_UPSTREAM` | `${{web.RAILWAY_PRIVATE_DOMAIN}}:8000` | Django web app. |
| `CAPTURE_UPSTREAM` | `${{capture.RAILWAY_PRIVATE_DOMAIN}}:3000` | Event capture (/e, /i/v0, /batch, /capture). |
| `CAPTURE_AI_UPSTREAM` | `${{capture.RAILWAY_PRIVATE_DOMAIN}}:3001` | LLM analytics capture (/i/v0/ai; ai process of the capture service). |
| `REPLAY_CAPTURE_UPSTREAM` | `${{capture.RAILWAY_PRIVATE_DOMAIN}}:3002` | Session replay capture (/s; recordings process of the capture service). |
| `CAPTURE_LOGS_UPSTREAM` | `${{capture-logs.RAILWAY_PRIVATE_DOMAIN}}:4318` | OTLP logs/traces/metrics capture (/i/v1/logs, /i/v1/traces, /i/v1/metrics). |
| `FEATURE_FLAGS_UPSTREAM` | `${{feature-flags.RAILWAY_PRIVATE_DOMAIN}}:3001` | Feature flags (/flags, local evaluation). |
| `HYPERCACHE_UPSTREAM` | `${{hypercache-server.RAILWAY_PRIVATE_DOMAIN}}:3002` | Surveys and remote config (/surveys, /array). |
| `PLUGINS_UPSTREAM` | `${{plugins.RAILWAY_PRIVATE_DOMAIN}}:6738` | Webhook sources (/public/webhooks, /public/m). |
| `LIVESTREAM_UPSTREAM` | `${{livestream.RAILWAY_PRIVATE_DOMAIN}}:8080` | Live events stream (/livestream). |
| `OBJECTSTORAGE_UPSTREAM` | `${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | Presigned object downloads (/posthog/*). |

### web

PostHog Django app (UI + API, Granian ASGI server). Runs Postgres, ClickHouse, persons and async migrations in the pre-deploy step after waiting for its dependencies.

- Source: image `posthog/posthog:sha-716405ddea318758493221f26e844512757c7927`
- Start command: `./bin/docker-server`
- Pre-deploy command: `/bin/bash -c 'for hp in $MIGRATE_WAIT_FOR; do until (exec 3<>/dev/tcp/${hp%:*}/${hp##*:}) 2>/dev/null; do echo "waiting for $hp"; sleep 5; done; done; exec ./bin/migrate'` (timeout 3600 s)
- Healthcheck: `/_health` (timeout 900 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8000` | Granian HTTP port; Railway healthcheck probes it. |
| `GRANIAN_WORKERS` | `2` | Web worker processes (~1.1 GB RAM each). Upstream default is 4; raise it for more concurrent API/UI requests. |
| `SITE_URL` | `https://${{proxy.RAILWAY_PUBLIC_DOMAIN}}` | Public URL of PostHog (the proxy domain). Change it when you add a custom domain to the proxy. |
| `SECRET_KEY` | `${{secret(56, "abcdef0123456789")}}` | Django secret key (hobby installer format). Generated once; changing it logs everyone out. |
| `ENCRYPTION_SALT_KEYS` | `${{secret(32, "abcdef0123456789")}}` | Salt for encrypted fields. Generated once; never change after first deploy. |
| `INTERNAL_API_SECRET` | `${{secret(64, "abcdef0123456789")}}` | Shared secret for internal calls (web/worker to recording-api, cymbal). |
| `INTERNAL_REQUEST_TOKEN` | `${{secret(64, "abcdef0123456789")}}` | Token for Django to feature-flags calls (flag test evaluation). |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string (private network). |
| `PERSONS_DB_WRITER_URL` | `${{Postgres.DATABASE_URL}}` | Persons database (same Postgres database in the hobby layout). |
| `PERSONS_DB_READER_URL` | `${{Postgres.DATABASE_URL}}` | Persons database reader (same Postgres database). |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for cache, Celery broker and locks. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka (Redpanda) bootstrap server. |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host (private network). |
| `CLICKHOUSE_DATABASE` | `posthog` | ClickHouse database PostHog uses. |
| `CLICKHOUSE_SECURE` | `false` | Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `false` | No TLS verification (no TLS on the private network). |
| `CLICKHOUSE_USER` | `default` | ClickHouse admin user used for queries and migrations. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse default-user password (reference). |
| `CLICKHOUSE_API_USER` | `api` | ClickHouse user for API queries. |
| `CLICKHOUSE_API_PASSWORD` | `${{clickhouse.CLICKHOUSE_API_PASSWORD}}` | Password of the api user (reference). |
| `CLICKHOUSE_APP_USER` | `app` | ClickHouse user for app queries. |
| `CLICKHOUSE_APP_PASSWORD` | `${{clickhouse.CLICKHOUSE_APP_PASSWORD}}` | Password of the app user (reference). |
| `CLICKHOUSE_DICT_READER_USER` | `dict_reader` | Read-only user ClickHouse dictionaries authenticate as. |
| `CLICKHOUSE_DICT_READER_PASSWORD` | `${{clickhouse.CLICKHOUSE_DICT_READER_PASSWORD}}` | Password of the dict_reader user (reference). |
| `CLICKHOUSE_LOGS_CLUSTER_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host for the logs product (same server; upstream default is localhost). |
| `CLICKHOUSE_LOGS_CLUSTER_SECURE` | `false` | Plain TCP for the logs cluster connection. |
| `CLICKHOUSE_LOGS_CLUSTER_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | Password for the logs cluster connection (default user). |
| `DEPLOYMENT` | `hobby` | Deployment type; hobby keeps persons in the main database and runs persons migrations. |
| `IS_BEHIND_PROXY` | `true` | Trust X-Forwarded-* from the Caddy proxy / Railway edge. |
| `DISABLE_SECURE_SSL_REDIRECT` | `true` | TLS is terminated by Railway; avoids a redirect loop. |
| `OTEL_SDK_DISABLED` | `true` | No OpenTelemetry export from Django. |
| `OTEL_SERVICE_NAME` | `posthog` | Service name if OpenTelemetry is enabled later. |
| `API_QUERIES_PER_TEAM` | `{"1": 100}` | Concurrent API query limit per team (upstream hobby value). |
| `CDP_API_URL` | `http://${{plugins.RAILWAY_PRIVATE_DOMAIN}}:6738` | Internal URL of the plugins (CDP) service. |
| `OBJECT_STORAGE_ENABLED` | `true` | Use S3 object storage for exports and media. |
| `OBJECT_STORAGE_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint for exports, media and AI blobs (private network). |
| `OBJECT_STORAGE_PUBLIC_ENDPOINT` | `${{SITE_URL}}` | Base URL for presigned downloads; the proxy forwards /posthog/* to seaweedfs. |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Object storage access key (reference). |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Object storage secret key (reference). |
| `OBJECT_STORAGE_FORCE_PATH_STYLE` | `true` | SeaweedFS needs path-style requests. |
| `SESSION_RECORDING_V2_S3_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint for session recordings. |
| `SESSION_RECORDING_V2_S3_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Recording store access key (reference). |
| `SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Recording store secret key (reference). |
| `RECORDING_API_URL` | `http://${{recordings.RAILWAY_PRIVATE_DOMAIN}}:6739` | Internal URL of the recording API (replay playback; second process of the recordings service). |
| `PERSONHOG_ADDR` | `${{personhog.RAILWAY_PRIVATE_DOMAIN}}:50052` | gRPC address of the personhog router. |
| `PERSONHOG_ENABLED` | `true` | Read persons through personhog, as the upstream hobby stack does. |
| `FEATURE_FLAGS_SERVICE_URL` | `http://${{feature-flags.RAILWAY_PRIVATE_DOMAIN}}:3001` | Internal URL of the Rust feature-flags service. |
| `TEMPORAL_HOST` | `${{temporal.RAILWAY_PRIVATE_DOMAIN}}` | Temporal frontend host (batch exports, data warehouse, workflows). |
| `LIVESTREAM_HOST` | `${{SITE_URL}}/livestream` | Public URL of the live events stream (proxied to livestream). |
| `OPT_OUT_CAPTURE` | `false` | Anonymous usage reporting to PostHog Inc. (upstream default). Set true to opt out. |
| `ANTHROPIC_API_KEY` | `` | Optional: Anthropic API key to enable PostHog AI. Leave empty to keep AI features off. |
| `OPENAI_API_KEY` | `` | Optional: OpenAI API key for SQL and regex assist. |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | OpenAI-compatible API base URL. |
| `OPENAI_MODEL` | `gpt-4.1-mini` | Model used for OpenAI-backed assists (upstream default). |
| `MIGRATE_WAIT_FOR` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432 ${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}:9000 ${{zookeeper.RAILWAY_PRIVATE_DOMAIN}}:2181 ${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092 ${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379` | host:port list the pre-deploy step waits for before running migrations. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Let in-flight requests finish on redeploy. |

### worker

Celery worker with the RedBeat scheduler (`--with-scheduler`): scheduled tasks, cohort calculation, exports, alerts. Keep one instance (the scheduler must not run twice); add a scheduler-less copy to scale.

- Source: image `posthog/posthog:sha-716405ddea318758493221f26e844512757c7927`
- Start command: `./bin/docker-worker-celery --with-scheduler`
- Pre-deploy command: none
- Healthcheck: none (no HTTP endpoint suitable for a deploy check)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `SITE_URL` | `${{web.SITE_URL}}` | Same as web: Public URL of PostHog (the proxy domain). |
| `SECRET_KEY` | `${{web.SECRET_KEY}}` | Same as web: Django secret key; signs sessions and tokens. |
| `ENCRYPTION_SALT_KEYS` | `${{web.ENCRYPTION_SALT_KEYS}}` | Same as web: Salt for encrypted fields (integration secrets). |
| `DATABASE_URL` | `${{web.DATABASE_URL}}` | Same as web: Postgres connection string. |
| `PERSONS_DB_WRITER_URL` | `${{web.PERSONS_DB_WRITER_URL}}` | Same as web: Persons database (same Postgres database in this stack). |
| `PERSONS_DB_READER_URL` | `${{web.PERSONS_DB_READER_URL}}` | Same as web: Persons database reader (same Postgres database). |
| `REDIS_URL` | `${{web.REDIS_URL}}` | Same as web: Redis for cache, Celery broker and locks. |
| `KAFKA_HOSTS` | `${{web.KAFKA_HOSTS}}` | Same as web: Kafka (Redpanda) bootstrap server. |
| `CLICKHOUSE_HOST` | `${{web.CLICKHOUSE_HOST}}` | Same as web: ClickHouse host (private network). |
| `CLICKHOUSE_DATABASE` | `${{web.CLICKHOUSE_DATABASE}}` | Same as web: ClickHouse database PostHog uses. |
| `CLICKHOUSE_SECURE` | `${{web.CLICKHOUSE_SECURE}}` | Same as web: Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `${{web.CLICKHOUSE_VERIFY}}` | Same as web: No TLS verification (no TLS on the private network). |
| `CLICKHOUSE_USER` | `${{web.CLICKHOUSE_USER}}` | Same as web: ClickHouse admin user used for queries and migrations. |
| `CLICKHOUSE_PASSWORD` | `${{web.CLICKHOUSE_PASSWORD}}` | Same as web: ClickHouse default-user password. |
| `CLICKHOUSE_API_USER` | `${{web.CLICKHOUSE_API_USER}}` | Same as web: ClickHouse user for API queries. |
| `CLICKHOUSE_API_PASSWORD` | `${{web.CLICKHOUSE_API_PASSWORD}}` | Same as web: Password of the api user. |
| `CLICKHOUSE_APP_USER` | `${{web.CLICKHOUSE_APP_USER}}` | Same as web: ClickHouse user for app queries. |
| `CLICKHOUSE_APP_PASSWORD` | `${{web.CLICKHOUSE_APP_PASSWORD}}` | Same as web: Password of the app user. |
| `CLICKHOUSE_DICT_READER_USER` | `${{web.CLICKHOUSE_DICT_READER_USER}}` | Same as web: Read-only user ClickHouse dictionaries authenticate as. |
| `CLICKHOUSE_DICT_READER_PASSWORD` | `${{web.CLICKHOUSE_DICT_READER_PASSWORD}}` | Same as web: Password of the dict_reader user. |
| `CLICKHOUSE_LOGS_CLUSTER_HOST` | `${{web.CLICKHOUSE_LOGS_CLUSTER_HOST}}` | Same as web: ClickHouse host for the logs product (same server). |
| `CLICKHOUSE_LOGS_CLUSTER_SECURE` | `${{web.CLICKHOUSE_LOGS_CLUSTER_SECURE}}` | Same as web: Plain TCP for the logs cluster connection. |
| `CLICKHOUSE_LOGS_CLUSTER_PASSWORD` | `${{web.CLICKHOUSE_LOGS_CLUSTER_PASSWORD}}` | Same as web: Password for the logs cluster connection (default user). |
| `DEPLOYMENT` | `${{web.DEPLOYMENT}}` | Same as web: Deployment type; hobby keeps persons in the main database. |
| `IS_BEHIND_PROXY` | `${{web.IS_BEHIND_PROXY}}` | Same as web: Trust X-Forwarded-* from the Caddy proxy / Railway edge. |
| `DISABLE_SECURE_SSL_REDIRECT` | `${{web.DISABLE_SECURE_SSL_REDIRECT}}` | Same as web: TLS is terminated by Railway; no redirect loop. |
| `OTEL_SDK_DISABLED` | `${{web.OTEL_SDK_DISABLED}}` | Same as web: No OpenTelemetry export from Django. |
| `API_QUERIES_PER_TEAM` | `${{web.API_QUERIES_PER_TEAM}}` | Same as web: Concurrent API query limit per team (upstream hobby value). |
| `CDP_API_URL` | `${{web.CDP_API_URL}}` | Same as web: Internal URL of the plugins (CDP) service. |
| `OBJECT_STORAGE_ENABLED` | `${{web.OBJECT_STORAGE_ENABLED}}` | Same as web: Use S3 object storage for exports and media. |
| `OBJECT_STORAGE_ENDPOINT` | `${{web.OBJECT_STORAGE_ENDPOINT}}` | Same as web: SeaweedFS S3 endpoint for exports, media and AI blobs. |
| `OBJECT_STORAGE_PUBLIC_ENDPOINT` | `${{web.OBJECT_STORAGE_PUBLIC_ENDPOINT}}` | Same as web: Base URL for presigned downloads (proxied under /posthog). |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | `${{web.OBJECT_STORAGE_ACCESS_KEY_ID}}` | Same as web: Object storage access key. |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | `${{web.OBJECT_STORAGE_SECRET_ACCESS_KEY}}` | Same as web: Object storage secret key. |
| `OBJECT_STORAGE_FORCE_PATH_STYLE` | `${{web.OBJECT_STORAGE_FORCE_PATH_STYLE}}` | Same as web: SeaweedFS needs path-style requests. |
| `SESSION_RECORDING_V2_S3_ENDPOINT` | `${{web.SESSION_RECORDING_V2_S3_ENDPOINT}}` | Same as web: SeaweedFS S3 endpoint for session recordings. |
| `SESSION_RECORDING_V2_S3_ACCESS_KEY_ID` | `${{web.SESSION_RECORDING_V2_S3_ACCESS_KEY_ID}}` | Same as web: Recording store access key. |
| `SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY` | `${{web.SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY}}` | Same as web: Recording store secret key. |
| `RECORDING_API_URL` | `${{web.RECORDING_API_URL}}` | Same as web: Internal URL of the recording API (replay playback). |
| `INTERNAL_API_SECRET` | `${{web.INTERNAL_API_SECRET}}` | Same as web: Shared secret for internal service-to-service calls. |
| `PERSONHOG_ADDR` | `${{web.PERSONHOG_ADDR}}` | Same as web: gRPC address of the personhog router. |
| `PERSONHOG_ENABLED` | `${{web.PERSONHOG_ENABLED}}` | Same as web: Read persons through personhog, as upstream hobby does. |
| `FEATURE_FLAGS_SERVICE_URL` | `${{web.FEATURE_FLAGS_SERVICE_URL}}` | Same as web: Internal URL of the Rust feature-flags service. |
| `INTERNAL_REQUEST_TOKEN` | `${{web.INTERNAL_REQUEST_TOKEN}}` | Same as web: Token for Django to feature-flags calls. |
| `TEMPORAL_HOST` | `${{web.TEMPORAL_HOST}}` | Same as web: Temporal frontend host (batch exports, data warehouse, workflows). |
| `ANTHROPIC_API_KEY` | `${{web.ANTHROPIC_API_KEY}}` | Same as web: Optional Anthropic key for PostHog AI. |
| `OPENAI_API_KEY` | `${{web.OPENAI_API_KEY}}` | Same as web: Optional OpenAI key for SQL/regex assist. |
| `OPENAI_BASE_URL` | `${{web.OPENAI_BASE_URL}}` | Same as web: OpenAI-compatible API base URL. |
| `OPENAI_MODEL` | `${{web.OPENAI_MODEL}}` | Same as web: Model used for OpenAI-backed assists. |
| `BROWSERLESS_CDP_URL` | `ws://${{browserless.RAILWAY_PRIVATE_DOMAIN}}:3000` | Browserless CDP endpoint for image exports. |
| `BROWSERLESS_TOKEN` | `${{browserless.TOKEN}}` | Browserless token (reference). |
| `HEATMAP_BROWSERLESS_URL` | `http://${{browserless.RAILWAY_PRIVATE_DOMAIN}}:3000` | Browserless HTTP endpoint for heatmap screenshots. |
| `HEATMAP_BROWSERLESS_TOKEN` | `${{browserless.TOKEN}}` | Browserless token (reference). |
| `HEATMAP_BROWSERLESS_SCREENSHOT_COOKIES_ENABLED` | `false` | Do not forward cookies to heatmap screenshots (upstream default). |
| `POSTHOG_SKIP_MIGRATION_CHECKS` | `1` | Migrations run in web's pre-deploy step; do not block on them here (upstream hobby setting). |
| `WEB_CONCURRENCY` | `2` | Celery worker processes. Upstream default is one per CPU, which on Railway means the host's CPU count. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let running Celery tasks finish on redeploy. |

### temporal-django-worker

Temporal worker for PostHog's durable workflows (batch exports, data warehouse syncs, recording deletion, subscriptions).

- Source: image `posthog/posthog:sha-716405ddea318758493221f26e844512757c7927`
- Start command: `./bin/temporal-django-worker`
- Pre-deploy command: none
- Healthcheck: none (no HTTP endpoint suitable for a deploy check)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `SITE_URL` | `${{web.SITE_URL}}` | Same as web: Public URL of PostHog (the proxy domain). |
| `SECRET_KEY` | `${{web.SECRET_KEY}}` | Same as web: Django secret key; signs sessions and tokens. |
| `ENCRYPTION_SALT_KEYS` | `${{web.ENCRYPTION_SALT_KEYS}}` | Same as web: Salt for encrypted fields (integration secrets). |
| `DATABASE_URL` | `${{web.DATABASE_URL}}` | Same as web: Postgres connection string. |
| `PERSONS_DB_WRITER_URL` | `${{web.PERSONS_DB_WRITER_URL}}` | Same as web: Persons database (same Postgres database in this stack). |
| `PERSONS_DB_READER_URL` | `${{web.PERSONS_DB_READER_URL}}` | Same as web: Persons database reader (same Postgres database). |
| `REDIS_URL` | `${{web.REDIS_URL}}` | Same as web: Redis for cache, Celery broker and locks. |
| `KAFKA_HOSTS` | `${{web.KAFKA_HOSTS}}` | Same as web: Kafka (Redpanda) bootstrap server. |
| `CLICKHOUSE_HOST` | `${{web.CLICKHOUSE_HOST}}` | Same as web: ClickHouse host (private network). |
| `CLICKHOUSE_DATABASE` | `${{web.CLICKHOUSE_DATABASE}}` | Same as web: ClickHouse database PostHog uses. |
| `CLICKHOUSE_SECURE` | `${{web.CLICKHOUSE_SECURE}}` | Same as web: Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `${{web.CLICKHOUSE_VERIFY}}` | Same as web: No TLS verification (no TLS on the private network). |
| `CLICKHOUSE_USER` | `${{web.CLICKHOUSE_USER}}` | Same as web: ClickHouse admin user used for queries and migrations. |
| `CLICKHOUSE_PASSWORD` | `${{web.CLICKHOUSE_PASSWORD}}` | Same as web: ClickHouse default-user password. |
| `CLICKHOUSE_API_USER` | `${{web.CLICKHOUSE_API_USER}}` | Same as web: ClickHouse user for API queries. |
| `CLICKHOUSE_API_PASSWORD` | `${{web.CLICKHOUSE_API_PASSWORD}}` | Same as web: Password of the api user. |
| `CLICKHOUSE_APP_USER` | `${{web.CLICKHOUSE_APP_USER}}` | Same as web: ClickHouse user for app queries. |
| `CLICKHOUSE_APP_PASSWORD` | `${{web.CLICKHOUSE_APP_PASSWORD}}` | Same as web: Password of the app user. |
| `CLICKHOUSE_DICT_READER_USER` | `${{web.CLICKHOUSE_DICT_READER_USER}}` | Same as web: Read-only user ClickHouse dictionaries authenticate as. |
| `CLICKHOUSE_DICT_READER_PASSWORD` | `${{web.CLICKHOUSE_DICT_READER_PASSWORD}}` | Same as web: Password of the dict_reader user. |
| `CLICKHOUSE_LOGS_CLUSTER_HOST` | `${{web.CLICKHOUSE_LOGS_CLUSTER_HOST}}` | Same as web: ClickHouse host for the logs product (same server). |
| `CLICKHOUSE_LOGS_CLUSTER_SECURE` | `${{web.CLICKHOUSE_LOGS_CLUSTER_SECURE}}` | Same as web: Plain TCP for the logs cluster connection. |
| `CLICKHOUSE_LOGS_CLUSTER_PASSWORD` | `${{web.CLICKHOUSE_LOGS_CLUSTER_PASSWORD}}` | Same as web: Password for the logs cluster connection (default user). |
| `DEPLOYMENT` | `${{web.DEPLOYMENT}}` | Same as web: Deployment type; hobby keeps persons in the main database. |
| `IS_BEHIND_PROXY` | `${{web.IS_BEHIND_PROXY}}` | Same as web: Trust X-Forwarded-* from the Caddy proxy / Railway edge. |
| `DISABLE_SECURE_SSL_REDIRECT` | `${{web.DISABLE_SECURE_SSL_REDIRECT}}` | Same as web: TLS is terminated by Railway; no redirect loop. |
| `OTEL_SDK_DISABLED` | `${{web.OTEL_SDK_DISABLED}}` | Same as web: No OpenTelemetry export from Django. |
| `API_QUERIES_PER_TEAM` | `${{web.API_QUERIES_PER_TEAM}}` | Same as web: Concurrent API query limit per team (upstream hobby value). |
| `CDP_API_URL` | `${{web.CDP_API_URL}}` | Same as web: Internal URL of the plugins (CDP) service. |
| `OBJECT_STORAGE_ENABLED` | `${{web.OBJECT_STORAGE_ENABLED}}` | Same as web: Use S3 object storage for exports and media. |
| `OBJECT_STORAGE_ENDPOINT` | `${{web.OBJECT_STORAGE_ENDPOINT}}` | Same as web: SeaweedFS S3 endpoint for exports, media and AI blobs. |
| `OBJECT_STORAGE_PUBLIC_ENDPOINT` | `${{web.OBJECT_STORAGE_PUBLIC_ENDPOINT}}` | Same as web: Base URL for presigned downloads (proxied under /posthog). |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | `${{web.OBJECT_STORAGE_ACCESS_KEY_ID}}` | Same as web: Object storage access key. |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | `${{web.OBJECT_STORAGE_SECRET_ACCESS_KEY}}` | Same as web: Object storage secret key. |
| `OBJECT_STORAGE_FORCE_PATH_STYLE` | `${{web.OBJECT_STORAGE_FORCE_PATH_STYLE}}` | Same as web: SeaweedFS needs path-style requests. |
| `SESSION_RECORDING_V2_S3_ENDPOINT` | `${{web.SESSION_RECORDING_V2_S3_ENDPOINT}}` | Same as web: SeaweedFS S3 endpoint for session recordings. |
| `SESSION_RECORDING_V2_S3_ACCESS_KEY_ID` | `${{web.SESSION_RECORDING_V2_S3_ACCESS_KEY_ID}}` | Same as web: Recording store access key. |
| `SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY` | `${{web.SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY}}` | Same as web: Recording store secret key. |
| `RECORDING_API_URL` | `${{web.RECORDING_API_URL}}` | Same as web: Internal URL of the recording API (replay playback). |
| `INTERNAL_API_SECRET` | `${{web.INTERNAL_API_SECRET}}` | Same as web: Shared secret for internal service-to-service calls. |
| `PERSONHOG_ADDR` | `${{web.PERSONHOG_ADDR}}` | Same as web: gRPC address of the personhog router. |
| `PERSONHOG_ENABLED` | `${{web.PERSONHOG_ENABLED}}` | Same as web: Read persons through personhog, as upstream hobby does. |
| `FEATURE_FLAGS_SERVICE_URL` | `${{web.FEATURE_FLAGS_SERVICE_URL}}` | Same as web: Internal URL of the Rust feature-flags service. |
| `INTERNAL_REQUEST_TOKEN` | `${{web.INTERNAL_REQUEST_TOKEN}}` | Same as web: Token for Django to feature-flags calls. |
| `TEMPORAL_HOST` | `${{web.TEMPORAL_HOST}}` | Same as web: Temporal frontend host (batch exports, data warehouse, workflows). |
| `ANTHROPIC_API_KEY` | `${{web.ANTHROPIC_API_KEY}}` | Same as web: Optional Anthropic key for PostHog AI. |
| `OPENAI_API_KEY` | `${{web.OPENAI_API_KEY}}` | Same as web: Optional OpenAI key for SQL/regex assist. |
| `OPENAI_BASE_URL` | `${{web.OPENAI_BASE_URL}}` | Same as web: OpenAI-compatible API base URL. |
| `OPENAI_MODEL` | `${{web.OPENAI_MODEL}}` | Same as web: Model used for OpenAI-backed assists. |
| `BROWSERLESS_CDP_URL` | `ws://${{browserless.RAILWAY_PRIVATE_DOMAIN}}:3000` | Browserless CDP endpoint for image exports. |
| `BROWSERLESS_TOKEN` | `${{browserless.TOKEN}}` | Browserless token (reference). |
| `HEATMAP_BROWSERLESS_URL` | `http://${{browserless.RAILWAY_PRIVATE_DOMAIN}}:3000` | Browserless HTTP endpoint for heatmap screenshots. |
| `HEATMAP_BROWSERLESS_TOKEN` | `${{browserless.TOKEN}}` | Browserless token (reference). |
| `HEATMAP_BROWSERLESS_SCREENSHOT_COOKIES_ENABLED` | `false` | Do not forward cookies to heatmap screenshots (upstream default). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let running activities finish on redeploy. |

### plugins

Node plugin server in its default role: CDP (destinations, transformations, hog functions, workflows), realtime cohorts, the feature-flag evaluation scheduler, and the Logs and Traces ingestion consumers (`NODEJS_CAPABILITY_GROUPS`; upstream runs logs and traces as separate `ingestion-logs`/`ingestion-traces` containers of the same image). Serves /public/webhooks through the proxy.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/posthog-node` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_health` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `6738` | Node HTTP server port (HTTP_SERVER_PORT default); /_health is the healthcheck. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka (Redpanda) bootstrap server. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection string. |
| `NODEJS_CAPABILITY_GROUPS` | `cdp_workflows,realtime_cohorts,logs,traces,feature_flags` | Capabilities of this process: the default plugin-server set plus traces ingestion (replaces upstream's ingestion-logs and ingestion-traces services). |
| `PERSONS_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Persons live in the main database (hobby layout). |
| `BEHAVIORAL_COHORTS_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Behavioral cohorts live in the main database (hobby layout). |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host. |
| `CLICKHOUSE_DATABASE` | `posthog` | ClickHouse database. |
| `CLICKHOUSE_SECURE` | `false` | Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `false` | No TLS verification. |
| `CLICKHOUSE_USER` | `default` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password (reference). |
| `SITE_URL` | `${{web.SITE_URL}}` | Public URL of PostHog. |
| `SECRET_KEY` | `${{web.SECRET_KEY}}` | Must match web. |
| `OBJECT_STORAGE_ENABLED` | `true` | Use object storage. |
| `OBJECT_STORAGE_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint. |
| `OBJECT_STORAGE_PUBLIC_ENDPOINT` | `${{web.SITE_URL}}` | Public base URL for presigned links. |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Object storage access key (reference). |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Object storage secret key (reference). |
| `CDP_REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis host for CDP state (function health, rate limits). |
| `CDP_REDIS_PORT` | `6379` | Redis port. |
| `CDP_REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password (reference). |
| `LOGS_REDIS_HOST` | `${{Redis.REDIS_URL}}` | Redis for logs-product state. The pinned node build does not pass LOGS_REDIS_PASSWORD to this pool, so the full URL (with password) goes here; ioredis accepts it. |
| `LOGS_REDIS_PORT` | `6379` | Redis port. |
| `LOGS_REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password (reference). |
| `LOGS_REDIS_TLS` | `false` | No TLS on the private network. |
| `TRACES_REDIS_HOST` | `${{Redis.REDIS_URL}}` | Redis for traces-product state. Full URL with password, as for LOGS_REDIS_HOST. |
| `TRACES_REDIS_PORT` | `6379` | Redis port. |
| `TRACES_REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password (reference). |
| `TRACES_REDIS_TLS` | `false` | No TLS on the private network. |
| `CDP_VALKEY_HOST` | `${{Redis.REDISHOST}}` | Not read by the pinned node build. Newer builds dual-write CDP state to a Valkey host and refuse to start without one; it points at Redis so an upgrade keeps working (the hobby compose runs a separate Valkey). |
| `CDP_VALKEY_PORT` | `6379` | Port for CDP_VALKEY_HOST. |
| `CDP_VALKEY_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Password for CDP_VALKEY_HOST (reference). |
| `ENCRYPTION_SALT_KEYS` | `${{web.ENCRYPTION_SALT_KEYS}}` | Must match web (decrypts encrypted function inputs). |

### ingestion

Node event ingestion, two processes (`NODE_PROCESSES`): `ingestion-v2-combined` on 6738 reads captured events from Kafka, resolves persons and groups, applies transformations and GeoIP and writes to ClickHouse via Kafka (also the AI events lane; large AI payloads go to object storage); `ingestion-errortracking` on 6739 turns exception events into issues using cymbal. Upstream: `ingestion-general` and `ingestion-error-tracking` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/posthog-node` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_health` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `NODE_PROCESSES` | `ingestion-v2-combined:6738 ingestion-errortracking:6739` | Node processes in this service (mode:port). A process that exits restarts the service. |
| `PORT` | `6738` | Node HTTP server port (HTTP_SERVER_PORT default); /_health is the healthcheck. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka (Redpanda) bootstrap server. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection string. |
| `PERSONS_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Persons live in the main database (hobby layout). |
| `BEHAVIORAL_COHORTS_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Behavioral cohorts live in the main database (hobby layout). |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host. |
| `CLICKHOUSE_DATABASE` | `posthog` | ClickHouse database. |
| `CLICKHOUSE_SECURE` | `false` | Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `false` | No TLS verification. |
| `CLICKHOUSE_USER` | `default` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password (reference). |
| `CDP_REDIS_HOST` | `${{Redis.REDISHOST}}` | Redis host for CDP state (function health, rate limits). |
| `CDP_REDIS_PORT` | `6379` | Redis port. |
| `CDP_REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | Redis password (reference). |
| `ENCRYPTION_SALT_KEYS` | `${{web.ENCRYPTION_SALT_KEYS}}` | Must match web (decrypts encrypted function inputs). |
| `AI_BLOB_S3_BUCKET` | `ai-blobs` | Bucket for offloaded multimodal AI payloads. |
| `AI_BLOB_S3_PREFIX` | `aio/` | Key prefix for AI blobs. |
| `AI_BLOB_S3_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint. |
| `AI_BLOB_S3_REGION` | `us-east-1` | Region string for the S3 client. |
| `AI_BLOB_S3_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Object storage access key (reference). |
| `AI_BLOB_S3_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Object storage secret key (reference). |
| `AI_BLOB_OFFLOAD_TEAMS` | `*` | Offload AI blobs for all teams. |
| `INGESTION_AI_EVENT_SPLITTING_ENABLED` | `true` | Write the full LLM analytics events (prompts, outputs) to the ai_events table and keep them out of the events table, as PostHog's AI lane does. |
| `INGESTION_AI_EVENT_SPLITTING_TEAMS` | `*` | Teams to split AI events for (all). |
| `PERSONHOG_ADDR` | `${{personhog.RAILWAY_PRIVATE_DOMAIN}}:50052` | personhog router (gRPC). |
| `PERSONHOG_ENABLED` | `true` | Read persons through personhog for the AI consumer. |
| `ERROR_TRACKING_CYMBAL_BASE_URL` | `http://${{cymbal.RAILWAY_PRIVATE_DOMAIN}}:3302` | cymbal processing service (error tracking process). |

### recordings

Node session replay, two processes (`NODE_PROCESSES`): `recordings-blob-ingestion-v2` on 6738 batches recording snapshots from Kafka into blob files in SeaweedFS; `recording-api` on 6739 serves them to the web app for playback and handles deletion. Upstream: `ingestion-sessionreplay` and `recording-api` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/posthog-node` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_health` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `NODE_PROCESSES` | `recordings-blob-ingestion-v2:6738 recording-api:6739` | Node processes in this service (mode:port). web calls the recording API on 6739. |
| `PORT` | `6738` | Node HTTP server port (HTTP_SERVER_PORT default); /_health is the healthcheck. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka (Redpanda) bootstrap server. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection string. |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` | ClickHouse host. |
| `CLICKHOUSE_DATABASE` | `posthog` | ClickHouse database. |
| `CLICKHOUSE_SECURE` | `false` | Plain TCP inside the private network. |
| `CLICKHOUSE_VERIFY` | `false` | No TLS verification. |
| `CLICKHOUSE_USER` | `default` | ClickHouse user. |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` | ClickHouse password (reference). |
| `SESSION_RECORDING_V2_S3_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint for recordings. |
| `SESSION_RECORDING_V2_S3_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Recording store access key (reference). |
| `SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Recording store secret key (reference). |
| `SESSION_RECORDING_V2_S3_TIMEOUT_MS` | `120000` | S3 request timeout (upstream hobby value). |
| `SESSION_RECORDING_API_REDIS_HOST` | `${{Redis.REDIS_URL}}` | Redis for the recording API. This setting has no password field; ioredis accepts the full URL (with password) here. |
| `SESSION_RECORDING_API_REDIS_PORT` | `6379` | Redis port. |
| `INTERNAL_API_SECRET` | `${{web.INTERNAL_API_SECRET}}` | Must match web (X-Internal-Api-Secret on recording API calls). |
| `ENCRYPTION_SALT_KEYS` | `${{web.ENCRYPTION_SALT_KEYS}}` | Must match web (decrypts encrypted function inputs). |

### capture

Rust capture, three processes of the same image (`services/capture/railway-capture.sh`): events (`/e`, `/i/v0/e`, `/batch`, `/capture`) on 3000, LLM analytics (`/i/v0/ai`, `/i/v1/ai/events`) on 3001 and session replay (`/s`) on 3002. Each validates SDK payloads and produces them to its Kafka topic. Upstream: `capture`, `capture-ai` and `replay-capture` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/capture` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Events capture port; /_readiness is the healthcheck. |
| `CAPTURE_EVENTS_PORT` | `3000` | Port of the events process. |
| `CAPTURE_AI_PORT` | `3001` | Port of the LLM analytics (ai) process. |
| `CAPTURE_REPLAY_PORT` | `3002` | Port of the session replay (recordings) process. |
| `CAPTURE_AI_LANE_TOPIC` | `events_plugin_ingestion` | Topic for LLM analytics events. The main topic, because the pinned Node build does not consume PostHog's separate AI lane (events_plugin_ingestion_ai); change only together with a Node image that does. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server. |
| `KAFKA_INGESTION_PRODUCER_METADATA_BROKER_LIST` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka metadata broker list for the producer. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis (quota limits, event restrictions). |
| `RUST_LOG` | `info,rdkafka=warn` | Log level. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Short drain on redeploy. |

### capture-logs

Rust OTLP endpoint for the Logs and Traces products (`/i/v1/logs`, `/i/v1/traces`, `/i/v1/metrics`).

- Source: image `ghcr.io/posthog/posthog/capture-logs:sha-04cdf1c`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Management port (/_readiness, /_liveness, metrics); Railway healthcheck target. |
| `MANAGEMENT_BIND_PORT` | `8080` | Management port. |
| `BIND_HOST` | `::` | OTLP listen address (dual-stack). |
| `BIND_PORT` | `4318` | OTLP HTTP port. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server. |
| `KAFKA_TOPIC` | `logs_ingestion` | Logs topic. |
| `KAFKA_METRICS_TOPIC` | `metrics_ingestion` | Metrics topic. |
| `JWT_SECRET` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Secret for capture-logs JWT handling (upstream compose ships a placeholder string). |
| `RUST_LOG` | `info,rdkafka=warn` | Log level. |
| `RUST_BACKTRACE` | `1` | Backtraces on panic. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Short drain on redeploy. |

### property-defs

Rust consumers that maintain event and property definitions (the data management pages and property pickers), two processes of property-defs-rs: the events stream on 3301 and the LLM analytics stream (`clickhouse_ai_events_json`) on 3303. Upstream: `property-defs-rs` and `property-defs-ai` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/property-defs` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3301` | HTTP port of the events process (/_readiness). |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server. |
| `SKIP_WRITES` | `false` | Write definitions. |
| `SKIP_READS` | `false` | Read existing definitions. |
| `FILTER_MODE` | `opt-out` | Process all teams unless opted out. |

### feature-flags

Rust feature flag evaluation (`/flags`, local evaluation) with the GeoLite2 database baked in, and the HyperCache S3 tier on SeaweedFS.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/feature-flags` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3001` | HTTP port; /_readiness is the healthcheck. |
| `ADDRESS` | `[::]:3001` | Bind address (dual-stack). |
| `WRITE_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres (writer). |
| `READ_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres (reader). |
| `PERSONS_WRITE_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Persons database (main database in the hobby layout). |
| `PERSONS_READ_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Persons database reader. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for team and flag caches. |
| `COOKIELESS_REDIS_HOST` | `default:${{Redis.REDIS_PASSWORD}}@${{Redis.REDISHOST}}` | Cookieless-mode Redis. The service builds redis://HOST:PORT from this value, so the credentials are embedded in the host part. |
| `COOKIELESS_REDIS_PORT` | `6379` | Redis port. |
| `OBJECT_STORAGE_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | HyperCache S3 tier endpoint (SeaweedFS). |
| `AWS_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Object storage access key (reference). |
| `AWS_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Object storage secret key (reference). |
| `INTERNAL_REQUEST_TOKEN` | `${{web.INTERNAL_REQUEST_TOKEN}}` | Must match web (flag test evaluation). |
| `RUST_LOG` | `info` | Log level. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Short drain on redeploy. |

### hypercache-server

Rust server for surveys and remote config (`/surveys`, `/array/*`), backed by Redis with the S3 tier on SeaweedFS.

- Source: image `ghcr.io/posthog/posthog/hypercache-server:sha-14bcc04`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3002` | HTTP port; /_readiness is the healthcheck. |
| `ADDRESS` | `[::]:3002` | Bind address (dual-stack). |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection string. |
| `OBJECT_STORAGE_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | HyperCache S3 tier endpoint (SeaweedFS). |
| `AWS_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Object storage access key (reference). |
| `AWS_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Object storage secret key (reference). |
| `RUST_LOG` | `info` | Log level. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Short drain on redeploy. |

### personhog

Rust gRPC person/group service: personhog-router on 50052 (web, workers and ingestion call it) and personhog-replica (reads and writes Postgres) on container-local 127.0.0.1:50051, two processes in one service. Upstream: `personhog-router` and `personhog-replica` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/personhog` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9101` | Router metrics/health port; /_readiness is the healthcheck. |
| `PRIMARY_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Persons database (main database in the hobby layout). |
| `BACKEND_TIMEOUT_MS` | `5000` | Router-to-replica call timeout. |
| `RUST_LOG` | `info` | Log level. |

### cymbal

Rust error tracking: processing (symbolication, fingerprinting, issue grouping; HTTP 3302) and the symbol resolution gRPC server (container-local 127.0.0.1:50061), two processes of the same image, with GeoLite2 baked in. Symbol sets are stored in SeaweedFS. Upstream: `cymbal` and `cymbal-resolution` containers.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/cymbal` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/_readiness` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3302` | HTTP port of the processing process; /_readiness is the healthcheck. |
| `BIND_HOST` | `::` | Bind address (dual-stack). |
| `BIND_PORT` | `3302` | HTTP port. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server. |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string. |
| `PERSONS_URL` | `${{Postgres.DATABASE_URL}}` | Persons database (main database). |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection string. |
| `ISSUE_BUCKETS_REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for issue rate buckets. |
| `OBJECT_STORAGE_BUCKET` | `posthog` | Bucket for symbol sets. |
| `OBJECT_STORAGE_ENDPOINT` | `http://${{seaweedfs.RAILWAY_PRIVATE_DOMAIN}}:8333` | SeaweedFS S3 endpoint. |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | `${{seaweedfs.AWS_ACCESS_KEY_ID}}` | Access key (reference). |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | `${{seaweedfs.AWS_SECRET_ACCESS_KEY}}` | Secret key (reference). |
| `OBJECT_STORAGE_FORCE_PATH_STYLE` | `true` | SeaweedFS needs path-style requests. |
| `INTERNAL_API_SECRET` | `${{web.INTERNAL_API_SECRET}}` | Must match web. |
| `RUST_LOG` | `info` | Log level. |

### livestream

Go service behind the Activity > Live events view (`/livestream`, server-sent events). Configured through LIVESTREAM_* variables instead of the compose config file.

- Source: image `ghcr.io/posthog/posthog/livestream:397fc8862e1ca5121a8679f0f686afde88d70b14`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | HTTP port. |
| `LIVESTREAM_JWT_SECRET` | `${{web.SECRET_KEY}}` | Must equal web's SECRET_KEY (signs live-events tokens). |
| `LIVESTREAM_MMDB_PATH` | `/GeoLite2-City.mmdb` | GeoLite2 database shipped in the image. |
| `LIVESTREAM_CONSUMERS_EVENT_BROKERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server (events). |
| `LIVESTREAM_CONSUMERS_EVENT_TOPIC` | `events_plugin_ingestion` | Events topic. |
| `LIVESTREAM_CONSUMERS_EVENT_SECURITY_PROTOCOL` | `PLAINTEXT` | Kafka protocol. |
| `LIVESTREAM_CONSUMERS_EVENT_GROUP_ID` | `livestream` | Consumer group. |
| `LIVESTREAM_CONSUMERS_SESSION_RECORDING_BROKERS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Kafka bootstrap server (recordings). |
| `LIVESTREAM_CONSUMERS_SESSION_RECORDING_TOPIC` | `session_recording_snapshot_item_events` | Recording snapshots topic. |
| `LIVESTREAM_CONSUMERS_SESSION_RECORDING_SECURITY_PROTOCOL` | `PLAINTEXT` | Kafka protocol. |
| `LIVESTREAM_CONSUMERS_SESSION_RECORDING_GROUP_ID` | `livestream-session-recordings` | Consumer group. |

### temporal

Temporal server (auto-setup image: creates the `temporal` and `temporal_visibility` databases in Postgres, applies schema updates and the `default` namespace on every start). SQL visibility; no Elasticsearch.

- Source: image `temporalio/auto-setup:1.29.7`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/api/v1/system-info` (timeout 1200 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `7243` | Frontend HTTP API port; /api/v1/system-info is the healthcheck. |
| `DB` | `postgres12` | Postgres persistence plugin. |
| `DB_PORT` | `5432` | Postgres port. |
| `POSTGRES_SEEDS` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` | Postgres host. |
| `POSTGRES_USER` | `${{Postgres.PGUSER}}` | Postgres user (needs CREATE DATABASE). |
| `POSTGRES_PWD` | `${{Postgres.POSTGRES_PASSWORD}}` | Postgres password (reference). |
| `ENABLE_ES` | `false` | SQL visibility store (upstream hobby setting). |
| `BIND_ON_IP` | `::0` | Listen on all interfaces (dual-stack). |
| `TEMPORAL_BROADCAST_ADDRESS` | `127.0.0.1` | Single-node membership address. |
| `TEMPORAL_ADDRESS` | `127.0.0.1:7233` | Address the setup script uses to create the namespace. |
| `DYNAMIC_CONFIG_FILE_PATH` | `config/dynamicconfig/docker.yaml` | Dynamic config shipped in the image. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Clean shutdown on redeploy. |

### browserless

Headless Chromium for image exports of insights/dashboards and heatmap screenshots (the PostHog image ships no browser). Private; token-protected.

- Source: image `ghcr.io/browserless/chromium:v2.57.0`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: none (no HTTP endpoint suitable for a deploy check)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: none
- Restart policy: ALWAYS; replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | HTTP/WebSocket port. |
| `HOST` | `::` | Listen on all interfaces (dual-stack). |
| `TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Browserless API token (separate from Django's SECRET_KEY). |
| `LOG_LEVEL` | `warn` | Log level (upstream hobby value). |
| `DEBUG` | `-*` | Silence debug namespaces (upstream hobby value). |

### clickhouse

ClickHouse 26.9 with PostHog's server config, users, UDFs (funnels, JSON cleaners) and format schemas baked in from the pinned PostHog commit. Every user has a generated password.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/clickhouse` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/ping` (timeout 600 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/var/lib/clickhouse`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8123` | HTTP port; /ping is the healthcheck. |
| `CLICKHOUSE_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the default (admin) user. Alphanumeric: PostHog embeds it in SQL. |
| `CLICKHOUSE_API_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the api user. |
| `CLICKHOUSE_APP_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the app user. |
| `CLICKHOUSE_DICT_READER_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Password of the read-only dict_reader user. |
| `KAFKA_HOSTS` | `${{kafka.RAILWAY_PRIVATE_DOMAIN}}:9092` | Brokers for PostHog's Kafka engine tables (named collections). |
| `ZOOKEEPER_HOST` | `${{zookeeper.RAILWAY_PRIVATE_DOMAIN}}` | ZooKeeper host for ON CLUSTER DDL and replicated tables. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let ClickHouse flush and stop cleanly. |

### zookeeper

ZooKeeper for ClickHouse coordination (distributed DDL queue, replicated tables), as in the hobby compose. Transaction log and snapshots on one volume; autopurge on.

- Source: image `zookeeper:3.9.6`
- Start command: `/bin/bash -c "mkdir -p /data/datalog && exec /docker-entrypoint.sh zkServer.sh start-foreground"`
- Pre-deploy command: none
- Healthcheck: `/commands/ruok` (timeout 300 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | ZooKeeper AdminServer port; /commands/ruok is the healthcheck. |
| `ZOO_DATA_LOG_DIR` | `/data/datalog` | Transaction log on the volume (Railway allows one volume per service). |
| `ZK_SERVER_HEAP` | `256` | JVM heap in MB (image default 1000); ClickHouse's coordination data is small. |
| `ZOO_AUTOPURGE_PURGEINTERVAL` | `1` | Purge old snapshots hourly (upstream hobby value). |
| `ZOO_AUTOPURGE_SNAPRETAINCOUNT` | `3` | Snapshots to keep (upstream hobby value). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Clean shutdown on redeploy. |

### kafka

Redpanda (Kafka API) as in PostHog's compose (`dev-container` mode). Creates PostHog's topics after every start (replaces the hobby `kafka-init` job) and sets a 24 h retention.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/kafka` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/v1/status/ready` (timeout 300 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/var/lib/redpanda/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `9644` | Admin API port; /v1/status/ready is the healthcheck. |
| `REDPANDA_SMP` | `1` | CPU cores Redpanda uses. |
| `REDPANDA_MEMORY` | `1G` | Memory Redpanda allocates (upstream hobby uses 3G). |
| `KAFKA_LOG_RETENTION_MS` | `86400000` | Topic retention (24 h). Kafka is a buffer here; ClickHouse holds the data. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Clean shutdown on redeploy. |

### Postgres

Railway base Postgres (`_railway-base/postgres.json`) with the default database renamed to `posthog`. Holds the app database and, via the temporal service, Temporal's two databases.

- Source: image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: none (no HTTP endpoint suitable for a deploy check)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/var/lib/postgresql/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel |
| `POSTGRES_DB` | `posthog` | Default database created when image is started (PostHog's database name). |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `postgres` | User to connect to Postgres DB |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down |

### Redis

Railway base Redis (`_railway-base/redis.json`) on the 7.2 line that PostHog supports (>= 7.0, < 8.0), with the hobby compose's LRU cap. Also stands in for the hobby compose's Valkey (only newer node builds use it).

- Source: image `redis:7.2.16-alpine`
- Start command: `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH --maxmemory $REDIS_MAXMEMORY --maxmemory-policy allkeys-lru"`
- Pre-deploy command: none
- Healthcheck: none (no HTTP endpoint suitable for a deploy check)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment |
| `REDISPORT` | `6379` | Port that Redis listens on |
| `REDISUSER` | `default` | Username for authenticating with Redis |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis |
| `REDIS_MAXMEMORY` | `512mb` | Memory cap with LRU eviction (hobby compose uses 200mb). |

### seaweedfs

SeaweedFS S3 store for everything PostHog keeps in object storage: exports, media uploads, HyperCache and session recording blobs, error-tracking symbol sets (bucket `posthog`, separate key prefixes) and offloaded AI payloads (bucket `ai-blobs`). Replaces the hobby compose's two stores (`objectstorage` and `seaweedfs`). Generated credentials; presigned downloads go through the proxy at /posthog/*.

- Source: repo `baranberkay96/posthog-railway`, root directory `/services/seaweedfs` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/healthz` (timeout 300 s)
- Public domain: no (private network only)
- TCP proxy: none
- Volume: `/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8333` | S3 port; /healthz is the healthcheck. |
| `S3_PORT` | `8333` | S3 gateway port. |
| `S3_BUCKETS` | `posthog,ai-blobs` | Buckets created at start (idempotent). |
| `AWS_ACCESS_KEY_ID` | `${{secret(20, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | S3 access key (admin identity). |
| `AWS_SECRET_ACCESS_KEY` | `${{secret(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | S3 secret key. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Clean shutdown on redeploy. |

<!-- END SERVICES -->

## Upstream components not deployed, and why

| Upstream (hobby compose) | Decision | Impact |
|---|---|---|
| `kafka-init` (one-shot topic creation) | Folded into the `kafka` service: topics from `docker/kafka/topics.txt` are created after every broker start (idempotent). | None; avoids a one-shot job that later services would have to wait for. |
| `asyncmigrationscheck`, base `migrate` (replicas 0) | Replaced by `web`'s pre-deploy step (`bin/migrate`: Postgres, ClickHouse, persons and async migrations + check). | None. |
| `elasticsearch` | Dropped. The hobby compose sets `ENABLE_ES=false` for Temporal, so Elasticsearch runs but is unused. | None. |
| `temporal-admin-tools` | Dropped (interactive CLI container). | Use `temporal` CLI inside the `temporal` service shell if needed. |
| `temporal-ui` | Dropped (hobby binds it to localhost only; no authentication). | No Temporal web UI. Add `temporalio/ui` behind a basic-auth proxy if you need it. |
| `capture-ai`, `replay-capture`, `property-defs-ai`, `cymbal-resolution`, `personhog-replica`, `ingestion-error-tracking`, `ingestion-sessionreplay`, `recording-api`, `ingestion-logs`, `ingestion-traces`, `objectstorage`, `valkey` as separate services | Run inside another service (see "Consolidation for Railway's 25-service limit"). | Same processes and settings; they scale and restart together with their host service. |
| Host `./share/GeoLite2-City.mmdb` bind mount | Baked into `services/posthog-node`, `services/feature-flags`, `services/cymbal` from PostHog's livestream image. | GeoIP works without a shared filesystem. |
| `./posthog/docker/clickhouse/*`, `./posthog/posthog/idl`, `./posthog/posthog/user_scripts` bind mounts | Baked into `services/clickhouse` at build time from the pinned commit. | UDFs and schemas live outside the data volume. |
| Host ports, Caddy ACME TLS | Railway terminates TLS and routes the public domain to `proxy`. | Custom domains are added to the `proxy` service. |
| Base-only services not in the hobby stack (`kafka_ui`, `flower`, `maildev`, `otel-collector`, `jaeger`, `opensearch`, `duckgres`, `dynamodb`, `usage-ingestion`, `personhog-leader/-writer/-identity/-router-leader`, `objectstorage-azure`) | Not deployed (development/cloud-only). | None for a self-hosted instance. |

Nothing in the hobby stack needs UDP, Docker-in-Docker or privileged containers. The only compose feature that does not map to Railway (shared host directories) is handled by baking the files into images.

## Improvements over market templates

1. **Official images only, pinned to exact commit tags.** Market `posthog-1` uses unpinned third-party `ghcr.io/hexatare/*:latest` images. Here every PostHog image is one PostHog publishes, pinned by commit (Django and Rust services: current master builds; Node: the build the hobby installer deploys); infrastructure images are pinned to exact versions.
2. **Current upstream topology within Railway's 25-service limit.** Runs every process of the current hobby stack, including what the market template lacks: personhog (router + replica), `hypercache-server`, the recording API (replay playback), error tracking (`cymbal` processing + resolution), Logs and Traces ingestion, `capture-logs`, AI property definitions, `browserless` (image exports, heatmaps) and AI capture (routed by the hobby proxy but missing from its service list). Related processes share a service (23 services in total).
3. **Generated secrets everywhere.** `SECRET_KEY`, `ENCRYPTION_SALT_KEYS`, `INTERNAL_API_SECRET`, `INTERNAL_REQUEST_TOKEN`, browserless token, capture-logs JWT secret, S3 keys, and passwords for every ClickHouse user (upstream hobby: empty `default` password, `apipass`/`apppass`/`dictreaderpass`) and Redis (upstream: none). The SeaweedFS store requires credentials (upstream recordings store: open access).
4. **No public database ports.** The market template exposes Redis via TCP proxy without a password; here only the router is public.
5. **Migrations as a pre-deploy step** that waits for Postgres, ClickHouse, ZooKeeper, Kafka and Redis, so parallel service start-up on Railway cannot race the schema.
6. **Topic creation inside the broker** (no `kafka-init` job to sequence), 24 h retention instead of unbounded growth on the volume.
7. **ClickHouse tuned for a container:** smaller caches (developer config assumes 5 GiB mark cache + 8 GiB uncompressed cache), high-churn system log tables disabled (`text_log` at trace level, `trace_log`, `metric_log`, ...), console logging, no TLS/MySQL/PostgreSQL listeners.
8. **GeoIP everywhere it is used** (ingestion, CDP, feature flags, cymbal, livestream). In the hobby compose only `plugins`, `feature-flags` and `cymbal` get the database.
9. **Every Node Kafka client points at the right broker.** PostHog's Node services create about fifteen Kafka clients whose broker lists default to the compose hostname `kafka:9092`; `services/posthog-node` derives them all from `KAFKA_HOSTS` (verified end to end: capture → Redpanda → ingestion → ClickHouse).
10. **LLM analytics events are not lost.** The current capture build sends `$ai_*` events to a separate AI-lane topic that only newer Node ingestion builds read; with the Node build the hobby installer deploys, those events would sit unconsumed. Here capture writes them to the main lane (`CAPTURE_AI_LANE_TOPIC`) and `ingestion` splits large AI payloads into the `ai_events` table (`INGESTION_AI_EVENT_SPLITTING_ENABLED`), verified locally.
11. **Bounded process counts:** Celery `WEB_CONCURRENCY=2` (upstream default is one process per visible CPU, which on Railway is the host's CPU count) and Granian `GRANIAN_WORKERS=2` (upstream 4; each worker holds ~1.1 GB). ZooKeeper heap capped at 256 MB (image default 1 GB).
12. **Healthchecks and restart policy `ALWAYS`** with 20-minute healthcheck windows on every dependent service (round-1 lesson: repo-built dependencies finish later).

## Resource estimate

Idle figures measured in the local test of this 23-service layout (arm64, all services running, a handful of test events; `browserless` not started, estimated). Consolidating processes into fewer services does not change the total: each process still uses its own memory.

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| web (Granian, 2 workers) | 2.4 GB | 2.7 GB | 0.3 | – |
| worker (Celery x2 + beat) | 3.1 GB | 3.5 GB | 0.2 | – |
| temporal-django-worker | 1.15 GB | 1.3 GB | 0.1 | – |
| plugins (CDP, logs, traces) | 0.3 GB | 0.5 GB | 0.15 | – |
| ingestion (2 Node processes) | 0.5 GB | 1.2 GB | 0.35 | – |
| recordings (2 Node processes) | 0.4 GB | 0.8 GB | 0.1 | – |
| Rust/Go services: capture (3 processes), capture-logs, property-defs (2), feature-flags, hypercache-server, personhog (2), cymbal (2), livestream | 0.25 GB | 1.0 GB | 0.3 | – |
| clickhouse | 0.75 GB | 2.5 GB | 0.5 | 5–50 GB |
| kafka (Redpanda, 1 GB cap) | 0.3 GB | 1.0 GB | 0.1 | 1–5 GB |
| zookeeper (256 MB heap) | 0.27 GB | 0.35 GB | 0.02 | < 0.5 GB |
| temporal | 0.22 GB | 0.3 GB | 0.05 | – |
| browserless | 0.2 GB | 0.6 GB | 0.05 | – |
| Postgres | 0.22 GB | 0.4 GB | 0.05 | 1–5 GB |
| Redis | 0.01 GB | 0.6 GB | 0.02 | < 0.5 GB |
| seaweedfs | 0.06 GB | 0.3 GB | 0.03 | 1–50 GB (recordings) |
| proxy | 0.01 GB | 0.05 GB | 0.02 | – |
| **Total** | **~10.1 GB** | **~17.1 GB** | **~2.3** | **~10–160 GB** |

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month.

- **Idle:** 10.1 GB × $10 + ~0.6 vCPU × $20 + ~10 GB × $0.15 ≈ **$115/month**.
- **Typical (a product team, ~1–5 M events and a few thousand recordings per month):** 17.1 GB × $10 + 2.3 vCPU × $20 + ~40 GB × $0.15 ≈ **$223/month**.
- Load scales mostly `ingestion`, ClickHouse and the recordings store. `worker` is the largest idle consumer; `WEB_CONCURRENCY=1` saves about 1 GB if Celery throughput is not needed.

**Minimum plan: Hobby** (no service exceeds the per-service limits; Trial's 1 GB per service is too small for web, the workers and ClickHouse). **Pro is recommended for production:** Hobby caps every volume at 5 GB, which ClickHouse and the recordings store outgrow quickly; PostHog itself says the hobby stack needs at least 8 GB of RAM.

## Verification checklist

1. All 23 services deploy. First boot: `web`'s pre-deploy step waits for its dependencies, then runs migrations (allow 10–20 minutes); its logs end with `All migrations completed successfully.`
2. `https://{proxy-domain}/_proxy/health` returns `OK`; `https://{proxy-domain}/_health` returns 200 (Django).
3. Open `https://{proxy-domain}`, create the first account and organization (the signup wizard). Do this right after deploy: the first visitor becomes the owner.
4. Install the snippet from Project settings on a test page (or `curl -X POST https://{proxy-domain}/i/v0/e/ -d '{"api_key":"{project-token}","event":"test","distinct_id":"1"}'` with your token): the event appears in Activity within a minute, and in Activity > Live (proves capture → kafka → ingestion → ClickHouse and livestream).
5. Event properties include `$geoip_country_name` for a real client IP (GeoIP baked into the Node image).
6. Enable session replay, browse the test page, play the recording (capture recordings process → recordings blob ingestion → seaweedfs → recording API).
7. Create a feature flag and call `https://{proxy-domain}/flags/?v=2` from posthog-js; the flag is returned (feature-flags).
8. Export an insight as PNG (browserless + seaweedfs presigned download via `/posthog/...`).
9. Create a batch export (e.g. to S3) and check `temporal-django-worker` logs pick it up (Temporal).
10. Redeploy `clickhouse`, `kafka`, `Postgres`, `seaweedfs`; data and recordings survive.
11. `kafka` logs show `railway: PostHog topics ready`; `clickhouse` logs have no authentication errors.
12. Logs of `capture`, `ingestion`, `recordings`, `property-defs`, `personhog` and `cymbal` start with one `railway: started ...` line per process and show no `exited` line.

## Open questions

- **Railway deploy test:** the first attempt (34 services) was rejected by Railway's limit of 25 services per template; this 23-service layout has not been deploy-tested on Railway yet.
- **Consolidated layout, verified locally (2026-10-11, arm64, every service started from `template.json` with resolved references, `docker run --init`):** migrations, all 23 services healthy, every process of the multi-process services answering its health port, signup, events and an `$exception` through capture → Redpanda → `ingestion` → ClickHouse, an error-tracking issue created via cymbal (processing + local resolution), `$ai_generation` stored in `events` and `ai_events`, property definitions written by both property-defs processes, logs and traces consumers running in `plugins`, a session recording ingested into SeaweedFS and played back through web and the recording API (port 6739 of `recordings`), personhog answering Django and Node calls, `/flags` answered, a crash of one capture process restarting the whole service and SIGTERM stopping all processes cleanly.
- **Earlier full-stack test (34-service layout):** verified locally (arm64 builds of the same Dockerfiles, Docker network names standing in for private domains): web pre-deploy migrations end to end on Postgres 18 + ClickHouse 26.9 (passwords, cluster DDL via ZooKeeper, UDFs) + Redpanda topics; web `/_health` 200 and `/_preflight` with db/redis/clickhouse/kafka/object storage up; signup of the first user; an event sent to capture reached ClickHouse through Redpanda and the Node ingestion (persons created); all Node modes, feature-flags (GeoIP loaded, `/flags` answered), SeaweedFS auth and presigned GET/POST, Caddy routing incl. presigned downloads, Temporal auto-setup 1.29.7 on Postgres 18. Not run locally: worker, temporal-django-worker, livestream, cymbal, browserless, capture-logs, hypercache.
- **GeoIP on events** needs the GeoIP transformation (Data pipelines > Transformations) to exist for the project; a project created in the local test had none until the Celery worker synced templates. Check it after first login.
- **Postgres 18 vs upstream 15:** PostHog states Postgres >= 14; the hobby compose uses 15.12. If a migration misbehaves, switch the Postgres image to `ghcr.io/railwayapp-templates/postgres-ssl:16` before first deploy.
- **Node image age:** like the hobby installer, the Node services run `posthog/posthog-node` build `82ea668` (2026-03-31), while Django and the Rust services are October builds. That is the combination PostHog's own hobby deployment ships, and it ingested events end to end in the local test; the newer ghcr.io Node builds expect the partitioned persons table and are not usable with hobby migrations. When PostHog publishes a newer hobby-compatible Node image, update `services/posthog-node/Dockerfile`. Newer Node builds also dual-write CDP state to Valkey; `CDP_VALKEY_*` point at Redis so they start, but check the upgrade against the hobby compose of that commit.
- **Redis password workarounds:** `SESSION_RECORDING_API_REDIS_HOST`, `LOGS_REDIS_HOST` and `TRACES_REDIS_HOST` get the full Redis URL because the pinned Node build does not pass a password to those pools (verified: ioredis accepts the URL and all Node modes started cleanly); feature-flags' cookieless Redis is built as `redis://HOST:PORT`, so its host value carries `default:{password}@` (verified with a flags request). ioredis forces IPv4, which Railway's current private network provides (legacy IPv6-only environments are not supported).
- **Redpanda `dev-container` mode** (as upstream): fsync is bypassed; an unclean host crash can lose the last buffered events. Kafka only buffers here (24 h retention).
- **PostHog AI features** stay off until `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` are set on `web`.
- **Email** (invites, password resets) needs SMTP settings (`EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `EMAIL_USE_TLS`, `EMAIL_DEFAULT_FROM`) on web and worker; outbound SMTP requires Railway Pro.
- **Upgrades** are commit-based: PostHog changes the hobby compose often. Upgrade all PostHog images together, and diff `docker-compose.hobby.yml`/`docker-compose.base.yml` between the old and new commit for new services or variables. When the Node image is upgraded to a build that consumes PostHog's AI lane, set `CAPTURE_AI_LANE_TOPIC=events_plugin_ingestion_ai` on `capture` at the same time.
