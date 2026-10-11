# Deploy and Host PostHog with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/posthog-product-analytics-suite?referralCode=20H68q)

PostHog is an open-source product platform: product analytics, web analytics, session replay, feature flags, experiments, surveys and error tracking in one tool. This community template deploys PostHog's full self-hosted ("hobby") stack on Railway, built from PostHog's own images and compose files, with every secret generated for you.

## About Hosting PostHog

Self-hosted PostHog is a distributed system, not a single container. Rust capture services receive events from the SDKs and write them to Kafka. Node.js ingestion services enrich them (persons, groups, GeoIP, transformations) and feed ClickHouse, where every chart and query runs. Django serves the app and API, Celery and Temporal run background jobs and exports, and SeaweedFS stores session recordings and exports. This template wires all 34 services together over Railway's private network behind one public router, runs database migrations before the app starts, creates the Kafka topics, bakes in the GeoIP database and keeps ClickHouse tuned for a container. You open one URL and create your account.

## Common Use Cases

- Product analytics on your own infrastructure: funnels, retention, paths, cohorts and SQL insights over raw events.
- Session replay and heatmaps to see how users move through your app, with recordings stored in your project.
- Feature flags and A/B experiments evaluated by your own flag service.
- Web analytics and surveys without sending visitor data to a third-party cloud.
- Error tracking and LLM analytics next to the product data they relate to.

## Dependencies for PostHog Hosting

- PostHog app images (`posthog/posthog`, `posthog/posthog-node`, PostHog's Rust services), pinned to exact commit builds
- ClickHouse 26.9 with ZooKeeper
- Redpanda (Kafka API)
- PostgreSQL (Railway Postgres), Redis 7.2 and Valkey
- Temporal (workflow engine) and Browserless (headless Chromium for image exports)
- SeaweedFS (S3-compatible storage for exports and recordings)

### Deployment Dependencies

- PostHog self-hosting docs: https://posthog.com/docs/self-host
- Hobby deployment guide: https://posthog.com/docs/self-host/deploy/hobby
- Hobby compose file: https://github.com/PostHog/posthog/blob/master/docker-compose.hobby.yml
- Base compose file: https://github.com/PostHog/posthog/blob/master/docker-compose.base.yml
- Self-host configuration (environment variables): https://posthog.com/docs/self-host/configure/environment-variables
- Redpanda: https://docs.redpanda.com
- Temporal: https://docs.temporal.io/self-hosted-guide

### Implementation Details

| Group | Services | Notes |
|---|---|---|
| Edge | proxy | Only public service. Routes `/e`, `/s`, `/flags`, `/livestream`, `/posthog/*` and the app to the services below. |
| App | web, worker, temporal-django-worker | Django UI/API (migrations run in web's pre-deploy step), Celery + scheduler, Temporal worker |
| Ingestion (Node) | plugins, ingestion-general, ingestion-sessionreplay, recording-api, ingestion-error-tracking, ingestion-logs, ingestion-traces | Event, replay, error, logs and traces pipelines; CDP destinations |
| Capture and flags (Rust/Go) | capture, replay-capture, capture-ai, capture-logs, feature-flags, hypercache-server, property-defs-rs, property-defs-ai, personhog-replica, personhog-router, cymbal, cymbal-resolution, livestream | SDK endpoints, flag evaluation, surveys, persons API, error symbolication, live events |
| Data | clickhouse, zookeeper, kafka, Postgres, Redis, valkey, objectstorage, seaweedfs | ClickHouse, Redpanda, Postgres, both SeaweedFS stores and ZooKeeper have volumes |
| Jobs | temporal, browserless | Workflow engine; headless Chromium for PNG exports and heatmaps (Browserless is SSPL-1.0 or commercial; see NOTICE.md) |

**First login**

1. Deploy and wait until `web` is active. The first deploy runs all migrations in web's pre-deploy step, which takes 10–20 minutes.
2. Open the `proxy` service's public domain and complete the signup wizard. The first account becomes the instance owner, so do this right away, then invite teammates from the organization settings.
3. Copy the project snippet (Project settings) into your site or app. SDKs use `https://{your-proxy-domain}` as the API host.

**Optional settings (on `web`):** `ANTHROPIC_API_KEY` enables PostHog AI, `OPENAI_API_KEY` enables SQL/regex assist. For invite and password-reset emails add PostHog's `EMAIL_*` SMTP variables to `web` and `worker` (outbound SMTP needs a Railway Pro plan).

**Custom domain:** add it to the `proxy` service, then set `SITE_URL` on `web` to `https://{your-domain}` and redeploy the PostHog services.

**Scaling:** `capture`, the `ingestion-*` services and `recording-api` are stateless and can run more replicas. Keep `worker` at one replica (it runs the Celery scheduler); add a copy without `--with-scheduler` if you need more Celery throughput. `web` concurrency is set by `GRANIAN_WORKERS` (2 here, about 1.1 GB RAM per worker). ClickHouse and Redpanda scale vertically (`REDPANDA_MEMORY`, `REDPANDA_SMP`).

**Pinning and upgrades:** PostHog does not publish versioned self-hosted releases; every image is pinned to a commit build. The Node services use the same `posthog/posthog-node` build the hobby installer deploys. To upgrade, pick a newer master commit, update the `posthog/posthog` tag on web, worker and temporal-django-worker, the Rust image tags, and `POSTHOG_COMMIT` in `services/clickhouse` and `services/kafka`; change the Node image only to a build that works with hobby's persons tables. Compare PostHog's compose files between the two commits for new services or variables before redeploying.

**Resources:** idle around 10 GB RAM (about $110/month); a team sending a few million events a month typically uses 15–18 GB (about $200–230/month). Hobby plan works; Pro is recommended because Hobby limits each volume to 5 GB.

### Why Deploy PostHog on Railway?

PostHog's self-hosted stack has more than thirty moving parts. Railway runs them as one project with private networking, volumes, generated secrets and per-second billing, so you get your own PostHog instance without managing servers or Kubernetes. Scaling an ingestion service is a replica setting, and every component is pinned so upgrades are deliberate.
