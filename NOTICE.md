# Notice

This is a community template. It is not affiliated with or endorsed by PostHog Inc.

## Upstream software

| Component | License | Images used |
|---|---|---|
| PostHog (Django app, Node services, Rust services, livestream) | MIT (Expat) for the repository except `ee/` (PostHog Enterprise license; paid features stay locked without a license key). Copyright (c) 2020-2026 PostHog Inc. | `posthog/posthog`, `posthog/posthog-node`, `ghcr.io/posthog/posthog/{capture,capture-logs,property-defs-rs,feature-flags,hypercache-server,personhog-replica,personhog-router,cymbal,livestream}` |
| ClickHouse | Apache-2.0 | `clickhouse/clickhouse-server:26.9.15.5` |
| Apache ZooKeeper | Apache-2.0 | `zookeeper:3.9.6` |
| Redpanda | Business Source License 1.1 (core; free to self-host, not to resell as a streaming service) and Redpanda Community License for some features | `redpandadata/redpanda:v26.2.4` |
| Temporal | MIT | `temporalio/auto-setup:1.29.7` |
| Browserless | SSPL-1.0 or Browserless commercial license. Browserless states that commercial, closed-source use needs a commercial license. It is used here only for PNG exports and heatmap screenshots; remove the `browserless` service if that license does not suit you (those two features then stop working). This is not legal advice. | `ghcr.io/browserless/chromium:v2.57.0` |
| SeaweedFS | Apache-2.0 | `chrislusf/seaweedfs:4.48` |
| Caddy | Apache-2.0 | `caddy:2.11.7-alpine` |
| Valkey | BSD-3-Clause | `valkey/valkey:8.1.10-alpine` |
| Redis 7.2 | BSD-3-Clause | `redis:7.2.16-alpine` |
| PostgreSQL | PostgreSQL License | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway) |
| GeoLite2 City (MaxMind) | GeoLite2 End User License Agreement (CC BY-SA 4.0 attribution). This product includes GeoLite2 data created by MaxMind, available from https://www.maxmind.com. Copied at build time from PostHog's livestream image, as PostHog distributes it. | — |

## Verified against

| What | Source | Version / ref | Checked |
|---|---|---|---|
| Service list, images, environment, proxy routes | https://github.com/PostHog/posthog/blob/master/docker-compose.hobby.yml and `docker-compose.base.yml` | commit `716405ddea318758493221f26e844512757c7927` (2026-10-11) | 2026-10-11 |
| Installer behaviour (secrets, `compose/start`, GeoIP download, `POSTHOG_NODE_TAG`) | `bin/deploy-hobby`, `bin/hobby-installer/core/env.go` | same commit | 2026-10-11 |
| Migrations and start scripts | `bin/migrate`, `bin/migrate-check`, `bin/docker-server`, `bin/docker-worker-celery`, `bin/temporal-django-worker` | same commit | 2026-10-11 |
| Django settings (ClickHouse users, Postgres, Temporal, object storage, service version requirements) | `posthog/settings/{data_stores,temporal,object_storage,service_requirements}.py`, `posthog/clickhouse/dictionaries.py` | same commit | 2026-10-11 |
| Node configuration (Redis/Valkey/ClickHouse/S3/Kafka variables, health routes) | `nodejs/src/**/config.ts`, `nodejs/src/common/api/router.ts`, `nodejs/src/common/utils/db/redis.ts`, `Dockerfile.node` (commit `a7831e30`), and the compiled `nodejs/dist` of the pinned image `posthog/posthog-node:82ea668` | 2026-10-11 | 2026-10-11 |
| Rust services (bind addresses, health routes, path-style S3, cookieless Redis URL) | `rust/{capture,capture-logs,feature-flags,hypercache-server,property-defs-rs,personhog-replica,personhog-router,cymbal}/src` | master 2026-10-11 | 2026-10-11 |
| Livestream environment variables | `livestream/configs/configs.go`, `livestream/main.go` | master 2026-10-11 | 2026-10-11 |
| Image publishing and tags (`sha-*`, ghcr vs Docker Hub) | `.github/workflows/{container-images-cd,ci-nodejs-container,rust-docker-build}.yml`, `.github/actions/docker-meta/action.yml`; registry manifests | 2026-10-11 | 2026-10-11 |
| Temporal auto-setup variables (`BIND_ON_IP`, broadcast address, dynamic config path) | `temporalio/auto-setup:1.29.7` image (`entrypoint.sh`, `auto-setup.sh`, `config_template.yaml`) | 1.29.7 | 2026-10-11 |
| Railway Buckets (virtual-hosted style only for new buckets) | https://docs.railway.com/storage-buckets | docs | 2026-10-11 |

## Adapted code

- `services/clickhouse/config.d/zz-railway.xml`: the `remote_servers`, `named_collections` and `macros` blocks are adapted from PostHog's `docker/clickhouse/config.d/default.xml` (MIT, Copyright (c) 2020-2026 PostHog Inc.); hosts changed to `localhost`, credentials and ZooKeeper host taken from the environment.
- `services/proxy/Caddyfile`: path matchers follow the `proxy` service's Caddyfile in PostHog's `docker-compose.base.yml` (MIT, Copyright (c) 2020-2026 PostHog Inc.), rewritten for Railway (environment-based upstreams, trusted proxies, health route).
- `services/kafka/railway-redpanda.sh`: topic creation follows the hobby `kafka-init` command (MIT, PostHog Inc.), rewritten as a background step of the broker container.
- `services/seaweedfs/railway-seaweedfs.sh`: bucket bootstrap follows the `objectstorage` entrypoint in `docker-compose.hobby.yml` (MIT, PostHog Inc.); credentials use SeaweedFS's environment-variable identity instead.
- Fetched unmodified at build time from the pinned PostHog commit (MIT): `docker/clickhouse/{config.xml,users.xml,user_defined_function.xml}`, `posthog/idl/*.json`, `posthog/user_scripts/*` (UDF wrappers and binaries), `docker/kafka/topics.txt`.
- The Postgres service definition is copied from this repository's `_railway-base/postgres.json` (database name changed to `posthog`); Redis from `_railway-base/redis.json` (image moved to the 7.2 line, LRU cap added).

## Reference only (not copied)

- Railway marketplace templates `posthog-1` (third-party `ghcr.io/hexatare/posthog-railway-template` images), `posthog-proxy` and `qHvw-4`, and the repos in `_upstream/`: read for ideas; no license attached, nothing copied.

## Trademarks

PostHog is a trademark of PostHog Inc. ClickHouse, Redpanda, Temporal, Browserless, SeaweedFS, Apache ZooKeeper, Valkey, Redis and PostgreSQL belong to their respective owners.
