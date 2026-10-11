# Notice

## Upstream software

- **Firecrawl** — AGPL-3.0. Copyright (c) Firecrawl (Mendable). Images used unmodified: `ghcr.io/firecrawl/firecrawl:2.11.504`, `ghcr.io/firecrawl/playwright-service` and `ghcr.io/firecrawl/nuq-postgres` (pinned by digest), all published by Firecrawl on GHCR. `services/firecrawl-workers/Dockerfile` adds only a launcher script on top of the official image; no Firecrawl source is modified. If you modify Firecrawl itself and offer it over a network, AGPL-3.0 obligations apply.
- **Caddy** — Apache-2.0. Image `caddy:2.11.7-alpine` (Docker official image).
- **RabbitMQ** — MPL-2.0. Image `rabbitmq:4.3.6-alpine` (Docker official image).
- **PostgreSQL** (inside nuq-postgres) — PostgreSQL License; **pg_cron** — PostgreSQL License.
- **Redis** — Redis 8 is available under RSALv2/SSPLv1/AGPLv3. Image `redis:8.2` (Docker official image).

## Verified against

| What | Source | Version / ref | Checked |
|---|---|---|---|
| Service list, env vars, RabbitMQ, nuq-postgres | https://github.com/firecrawl/firecrawl/blob/main/docker-compose.yaml (also diffed against tag `v2.11.0`) | main / v2.11.0 | 2026-10-10 |
| Self-hosting env reference | https://github.com/firecrawl/firecrawl/blob/main/SELF_HOST.md | v2.11.0 | 2026-10-10 |
| Process list and per-process env (ports, `NUQ_POD_NAME`, prefetch replicas) | `apps/api/src/harness.ts` | v2.11.0 / main | 2026-10-10 |
| Config schema (`HOST`, `PORT`, `*_PORT`, `NUQ_*`, `IS_KUBERNETES`) | `apps/api/src/config.ts`, `services/system-monitor.ts` | main | 2026-10-10 |
| Health routes | `apps/api/src/routes/v0.ts`, `services/queue-worker.ts`, `services/worker/nuq-worker-runner.ts`, `apps/playwright-service-ts/api.ts` | main | 2026-10-10 |
| NuQ Postgres image (pg_cron, `cron.database_name`, WAL settings) | `apps/nuq-postgres/Dockerfile`, `apps/nuq-postgres/nuq.sql` | main | 2026-10-10 |
| NuQ RabbitMQ usage (transient exclusive queues) | `apps/api/src/services/worker/nuq.ts` | main | 2026-10-10 |
| Kubernetes reference split (api / worker / nuq-worker) | `examples/kubernetes/cluster-install/*.yaml` | v2.11.0 | 2026-10-10 |
| Image tags and digests | GHCR registry API (`firecrawl/firecrawl` 2.11.504 = `latest`; playwright-service and nuq-postgres digests) | — | 2026-10-10 |

## Adapted code

None. `services/gateway/Caddyfile`, `services/gateway/Dockerfile`, `services/firecrawl-workers/Dockerfile` and `railway-workers.sh` were written for this template; the launcher reproduces the process list and environment that upstream's `harness.ts` uses. Redis is copied from this repository's `_railway-base/redis.json`.

## Reference only (not copied)

- Railway marketplace templates `AIaBEM` (firecrawl), `firecrawl` and `firecrawl-web-scraping-api`: read for ideas only; no text or files copied. No license is attached to them.

## Trademarks

Firecrawl is a trademark of its owner; Playwright, Chromium, Caddy, RabbitMQ, PostgreSQL and Redis belong to their respective owners. This is a community template and is not affiliated with or endorsed by Firecrawl.
