# Deploy and Host PostHog with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/posthog-product-analytics-suite?referralCode=20H68q)

PostHog is an open-source product platform: product analytics, web analytics, session replay, feature flags, experiments, surveys and error tracking in one tool. This community template deploys PostHog's full self-hosted ("hobby") stack on Railway, built from PostHog's own images and compose files, with every secret generated for you.

## About Hosting PostHog

Self-hosted PostHog is a distributed system, not a single container. Rust capture services receive events from the SDKs and write them to Kafka. Node.js ingestion services enrich them (persons, groups, GeoIP, transformations) and feed ClickHouse, where every chart and query runs. Django serves the app and API, Celery and Temporal run background jobs and exports, and SeaweedFS stores session recordings and exports. This template runs every process of PostHog's hobby stack in 23 Railway services (related processes share a service to stay within Railway's 25-service template limit), wired together over the private network behind one public router. It runs database migrations before the app starts, creates the Kafka topics, bakes in the GeoIP database and keeps ClickHouse tuned for a container. You open one URL and create your account.

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
- PostgreSQL (Railway Postgres) and Redis 7.2
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
| Ingestion (Node) | plugins (CDP, logs and traces), ingestion (events + error tracking), recordings (replay ingestion + recording API) | Event, replay, error, logs and traces pipelines; CDP destinations |
| Capture and flags (Rust/Go) | capture (events, AI and replay capture), capture-logs, feature-flags, hypercache-server, property-defs, personhog, cymbal, livestream | SDK endpoints, flag evaluation, surveys, persons API, error symbolication, live events |
| Data | clickhouse, zookeeper, kafka, Postgres, Redis, seaweedfs | ClickHouse, Redpanda, Postgres, SeaweedFS and ZooKeeper have volumes |
| Jobs | temporal, browserless | Workflow engine; headless Chromium for PNG exports and heatmaps (Browserless is SSPL-1.0 or commercial; see NOTICE.md) |

**First login**

1. Deploy and wait until `web` is active. The first deploy runs all migrations in web's pre-deploy step, which takes 10–20 minutes.
2. Open the `proxy` service's public domain and complete the signup wizard. The first account becomes the instance owner, so do this right away, then invite teammates from the organization settings.
3. Copy the project snippet (Project settings) into your site or app. SDKs use `https://{your-proxy-domain}` as the API host.

**Optional settings (on `web`):** `ANTHROPIC_API_KEY` enables PostHog AI, `OPENAI_API_KEY` enables SQL/regex assist. For invite and password-reset emails add PostHog's `EMAIL_*` SMTP variables to `web` and `worker` (outbound SMTP needs a Railway Pro plan).

**Custom domain:** add it to the `proxy` service, then set `SITE_URL` on `web` to `https://{your-domain}` and redeploy the PostHog services.

**Services with several processes:** `capture`, `ingestion`, `recordings`, `property-defs`, `personhog` and `cymbal` each run two or three PostHog processes that upstream runs as separate containers (same images and settings). If one process stops, the service restarts as a whole. The table in `TEMPLATE.md` lists which upstream containers each one replaces.

**Scaling:** `capture`, `ingestion` and `recordings` are stateless and can run more replicas (all processes of a service scale together). Keep `worker` at one replica (it runs the Celery scheduler); add a copy without `--with-scheduler` if you need more Celery throughput. `web` concurrency is set by `GRANIAN_WORKERS` (2 here, about 1.1 GB RAM per worker). ClickHouse and Redpanda scale vertically (`REDPANDA_MEMORY`, `REDPANDA_SMP`).

**Pinning and upgrades:** PostHog does not publish versioned self-hosted releases; every image is pinned to a commit build. The Node services use the same `posthog/posthog-node` build the hobby installer deploys. To upgrade, pick a newer master commit, update the `posthog/posthog` tag on web, worker and temporal-django-worker, the Rust image tags (service images and the `FROM` lines in `services/capture`, `services/property-defs`, `services/personhog`, `services/cymbal`, `services/feature-flags`), and `POSTHOG_COMMIT` in `services/clickhouse` and `services/kafka`; change the Node image only to a build that works with hobby's persons tables. If that Node build reads PostHog's separate AI-events topic, also set `CAPTURE_AI_LANE_TOPIC=events_plugin_ingestion_ai` on `capture`. Compare PostHog's compose files between the two commits for new services or variables before redeploying.

**Resources:** idle around 10 GB RAM (about $115/month); a team sending a few million events a month typically uses 16–18 GB (about $210–230/month). Hobby plan works; Pro is recommended because Hobby limits each volume to 5 GB.

### Why Deploy PostHog on Railway?

PostHog's self-hosted stack has more than thirty moving parts. Railway runs them as one project of 23 services with private networking, volumes, generated secrets and per-second billing, so you get your own PostHog instance without managing servers or Kubernetes. Scaling an ingestion service is a replica setting, and every component is pinned so upgrades are deliberate.
