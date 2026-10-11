# Firecrawl v2 Web Data API for AI — Railway template spec

## Listing

- **Name:** Firecrawl v2 Web Data API for AI (LISTINGS.md name with the pinned major version inserted after the software name; Firecrawl tags releases `v2.x`)
- **Description (79 chars):** Turn websites into clean markdown and JSON for LLMs. Self-hosted workers. (unchanged)
- **Category:** AI/ML
- **Tags:** firecrawl, web-scraping, crawler, markdown, llm, rag, playwright

## Base market template

- **Chosen base: `AIaBEM` "firecrawl"** (73 active / 477 total projects): the most used layout — API + separate worker services + Playwright + nuq-postgres + Redis. Kept: running worker processes as their own Railway services and wiring the API to Playwright over the private network.
- Replaced in `AIaBEM`: third-party `bonkboykz/*:latest` images (now official `ghcr.io/firecrawl/*`), Redis reached over its public TCP proxy (`REDIS_PUBLIC_URL`), hardcoded nuq-postgres password, `BULL_AUTH_KEY='@'`, no RabbitMQ, no healthchecks and no API authentication.
- `firecrawl` "[Updated Oct ’26]" (45 active): same `bonkboykz` images and issues; nothing taken.
- `firecrawl-web-scraping-api` (17 active): official images + RabbitMQ (good), but `:latest` tags, no volume on nuq-postgres, partly hardcoded credentials and no auth. Used to confirm the official image names and the RabbitMQ requirement.
- `_upstream`: none for this app.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| firecrawl-api | `ghcr.io/firecrawl/firecrawl` | `2.11.504` (same digest as `latest` and `2.11.504-production`) | 2026-10-10 build | 2026-10-10 |
| firecrawl-worker, firecrawl-nuq-worker | Dockerfile `services/firecrawl-workers` (`FROM ghcr.io/firecrawl/firecrawl:2.11.504`) | `2.11.504` | 2026-10-10 build | 2026-10-10 |
| playwright-service | `ghcr.io/firecrawl/playwright-service` | `latest@sha256:717699bf…08fcc6` (no version tags are published) | 2026-10-06 build | 2026-10-10 |
| nuq-postgres | `ghcr.io/firecrawl/nuq-postgres` | `latest@sha256:9b638af7…21e8fc` (no version tags are published) | 2026-09-16 build | 2026-10-10 |
| firecrawl (gateway) | Dockerfile `services/gateway` (`FROM caddy:2.11.7-alpine`) | `2.11.7` | 2026-10-06 | 2026-10-10 |
| RabbitMQ | `rabbitmq` | `4.3.6-alpine` | 2026-10-02 | 2026-10-10 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-10 |

The latest GitHub release is `v2.11.0` (2026-06-19); Firecrawl publishes continuous `2.11.N` images from `main`, and `2.11.504` is the build currently tagged `latest`/`-production`. Playwright and nuq-postgres are only published as `latest`, so they are pinned by digest.

## Architecture

```
 SDK / HTTP client --Authorization: Bearer fc-...--> [firecrawl gateway :8080]  (only public service)
                                                             |
                                                             v
  [playwright-service :3000] <---- /scrape ---------- [firecrawl-api :3002]
            ^                                           |       |        |
            |                                    BullMQ |   NuQ |   AMQP |
            |                                           v       v        v
            +----- [firecrawl-nuq-worker x5] -------> [Redis] [nuq-postgres] [RabbitMQ]
            +----- [firecrawl-worker: queue, extract, prefetch, reconciler] ----^
```

- The upstream docker-compose runs `harness.js --start-docker` in one container, which spawns the API plus about ten worker processes. This template runs the same entrypoints with the same environment, split into three services so the API, the orchestration workers and the scrape executors restart and scale independently.
- nuq-postgres holds the NuQ job queue (with pg_cron maintenance jobs). RabbitMQ only carries transient wake-up notifications (non-durable, exclusive queues), so it has no volume.
- Only the Caddy gateway is public. It answers `/healthz`, forwards `/admin/<BULL_AUTH_KEY>/queues` (queue dashboard behind a secret path, as upstream), and forwards all other requests only when `Authorization: Bearer $FIRECRAWL_API_KEY` matches; otherwise it returns 401.

## Services

### firecrawl

Public API-key gateway (Caddy) built from `services/gateway`. The only service with a domain; clients use its URL as the Firecrawl API URL.

- Source: repo `baranberkay96/firecrawl-railway`, root directory `/services/gateway` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/healthz` (timeout 60 s)
- Public domain: yes, target port `8080`
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Gateway listen port (public domain target). |
| `FIRECRAWL_API_KEY` | `fc-${{secret(32, "abcdef0123456789")}}` | API key clients must send as 'Authorization: Bearer <key>'. Use it as the SDK api_key. |
| `FIRECRAWL_UPSTREAM` | `${{firecrawl-api.RAILWAY_PRIVATE_DOMAIN}}:3002` | Private address of firecrawl-api. |

### firecrawl-api

Official image. The start command runs only the API process (`dist/src/index.js`) instead of the all-in-one harness.

- Source: image `ghcr.io/firecrawl/firecrawl:2.11.504`
- Start command: `node dist/src/index.js`
- Pre-deploy command: none
- Healthcheck: `/v0/health/readiness` (timeout 300 s)
- Public domain: no (listens on `3002` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `HOST` | `::` | Bind address; :: accepts IPv4 and IPv6 from the gateway. |
| `PORT` | `3002` | API port (private). |
| `ENV` | `local` | Self-hosted mode (same value as the upstream docker-compose). |
| `LOGGING_LEVEL` | `INFO` | Log level. |
| `USE_DB_AUTHENTICATION` | `false` | Supabase auth is not available for self-hosting; the firecrawl gateway enforces the API key instead. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for BullMQ queues and crawl state. |
| `REDIS_RATE_LIMIT_URL` | `${{Redis.REDIS_URL}}` | Redis for rate limiting. |
| `NUQ_DATABASE_URL` | `postgresql://postgres:${{nuq-postgres.POSTGRES_PASSWORD}}@${{nuq-postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/postgres` | NuQ job queue database (nuq-postgres, private network). |
| `NUQ_DATABASE_URL_LISTEN` | `${{NUQ_DATABASE_URL}}` | Direct connection used for LISTEN/NOTIFY (same database). |
| `NUQ_RABBITMQ_URL` | `amqp://firecrawl:${{RabbitMQ.RABBITMQ_DEFAULT_PASS}}@${{RabbitMQ.RAILWAY_PRIVATE_DOMAIN}}:5672` | RabbitMQ used by NuQ to wake workers when jobs arrive. |
| `PLAYWRIGHT_MICROSERVICE_URL` | `http://${{playwright-service.RAILWAY_PRIVATE_DOMAIN}}:3000/scrape` | Browser rendering service (private network). |
| `BULL_AUTH_KEY` | `${{secret(32, "abcdef0123456789")}}` | Secret path segment for the queue dashboard: /admin/<BULL_AUTH_KEY>/queues. |
| `NUM_WORKERS_PER_QUEUE` | `8` | BullMQ concurrency per queue (upstream default). |
| `CRAWL_CONCURRENT_REQUESTS` | `10` | Concurrent requests per crawl (upstream default). |
| `MAX_CONCURRENT_JOBS` | `5` | Max concurrent jobs per team (upstream default). |
| `BROWSER_POOL_SIZE` | `5` | Browser pool size (upstream default). |
| `OPENAI_API_KEY` | `` | Optional. Enables LLM features (JSON/extract formats, /extract). Leave empty to disable. |
| `OPENAI_BASE_URL` | `` | Optional. OpenAI-compatible base URL (e.g. a LiteLLM gateway). |
| `MODEL_NAME` | `` | Optional. Model used for extraction (e.g. gpt-4o-mini). |
| `MODEL_EMBEDDING_NAME` | `` | Optional. Embedding model name. |
| `OLLAMA_BASE_URL` | `` | Optional (experimental upstream). Ollama API base URL instead of OpenAI. |
| `PROXY_SERVER` | `` | Optional. Outbound HTTP proxy for fetches (http://host:port). |
| `PROXY_USERNAME` | `` | Optional. Proxy username. |
| `PROXY_PASSWORD` | `` | Optional. Proxy password. |
| `SEARXNG_ENDPOINT` | `` | Optional. SearXNG instance (JSON enabled) for /search instead of direct Google. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let in-flight scrape requests finish during redeploys. |

### firecrawl-worker

Built from `services/firecrawl-workers` (official image + `railway-workers.sh`). Runs queue-worker, extract-worker, NuQ prefetch and NuQ reconciler. Keep at 1 replica (prefetch and reconciler are singletons).

- Source: repo `baranberkay96/firecrawl-railway`, root directory `/services/firecrawl-workers` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/liveness` (timeout 300 s)
- Public domain: no (listens on `3005` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `FIRECRAWL_WORKER_ROLE` | `worker` | Process group run by services/firecrawl-workers/railway-workers.sh: queue-worker, extract-worker, NuQ prefetch and reconciler. |
| `PORT` | `3005` | Liveness port of the queue-worker (Railway healthcheck). |
| `WORKER_PORT` | `3005` | queue-worker liveness port. |
| `EXTRACT_WORKER_PORT` | `3004` | extract-worker health port. |
| `NUQ_PREFETCH_WORKER_PORT` | `3011` | NuQ prefetch worker health port. |
| `NUQ_RECONCILER_WORKER_PORT` | `3012` | NuQ reconciler health port. |
| `IS_KUBERNETES` | `true` | Use container (cgroup v2) CPU/RAM figures for job back-pressure instead of host-wide numbers. |
| `ENV` | `local` | Self-hosted mode (same value as the upstream docker-compose). |
| `LOGGING_LEVEL` | `INFO` | Log level. |
| `USE_DB_AUTHENTICATION` | `false` | Supabase auth is not available for self-hosting; the firecrawl gateway enforces the API key instead. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for BullMQ queues and crawl state. |
| `REDIS_RATE_LIMIT_URL` | `${{Redis.REDIS_URL}}` | Redis for rate limiting. |
| `NUQ_DATABASE_URL` | `postgresql://postgres:${{nuq-postgres.POSTGRES_PASSWORD}}@${{nuq-postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/postgres` | NuQ job queue database (nuq-postgres, private network). |
| `NUQ_DATABASE_URL_LISTEN` | `${{NUQ_DATABASE_URL}}` | Direct connection used for LISTEN/NOTIFY (same database). |
| `NUQ_RABBITMQ_URL` | `amqp://firecrawl:${{RabbitMQ.RABBITMQ_DEFAULT_PASS}}@${{RabbitMQ.RAILWAY_PRIVATE_DOMAIN}}:5672` | RabbitMQ used by NuQ to wake workers when jobs arrive. |
| `PLAYWRIGHT_MICROSERVICE_URL` | `http://${{playwright-service.RAILWAY_PRIVATE_DOMAIN}}:3000/scrape` | Browser rendering service (private network). |
| `BULL_AUTH_KEY` | `${{firecrawl-api.BULL_AUTH_KEY}}` | Shared with firecrawl-api (BULL_AUTH_KEY). |
| `NUM_WORKERS_PER_QUEUE` | `${{firecrawl-api.NUM_WORKERS_PER_QUEUE}}` | Shared with firecrawl-api (NUM_WORKERS_PER_QUEUE). |
| `CRAWL_CONCURRENT_REQUESTS` | `${{firecrawl-api.CRAWL_CONCURRENT_REQUESTS}}` | Shared with firecrawl-api (CRAWL_CONCURRENT_REQUESTS). |
| `MAX_CONCURRENT_JOBS` | `${{firecrawl-api.MAX_CONCURRENT_JOBS}}` | Shared with firecrawl-api (MAX_CONCURRENT_JOBS). |
| `BROWSER_POOL_SIZE` | `${{firecrawl-api.BROWSER_POOL_SIZE}}` | Shared with firecrawl-api (BROWSER_POOL_SIZE). |
| `OPENAI_API_KEY` | `${{firecrawl-api.OPENAI_API_KEY}}` | Shared with firecrawl-api (OPENAI_API_KEY). |
| `OPENAI_BASE_URL` | `${{firecrawl-api.OPENAI_BASE_URL}}` | Shared with firecrawl-api (OPENAI_BASE_URL). |
| `MODEL_NAME` | `${{firecrawl-api.MODEL_NAME}}` | Shared with firecrawl-api (MODEL_NAME). |
| `MODEL_EMBEDDING_NAME` | `${{firecrawl-api.MODEL_EMBEDDING_NAME}}` | Shared with firecrawl-api (MODEL_EMBEDDING_NAME). |
| `OLLAMA_BASE_URL` | `${{firecrawl-api.OLLAMA_BASE_URL}}` | Shared with firecrawl-api (OLLAMA_BASE_URL). |
| `PROXY_SERVER` | `${{firecrawl-api.PROXY_SERVER}}` | Shared with firecrawl-api (PROXY_SERVER). |
| `PROXY_USERNAME` | `${{firecrawl-api.PROXY_USERNAME}}` | Shared with firecrawl-api (PROXY_USERNAME). |
| `PROXY_PASSWORD` | `${{firecrawl-api.PROXY_PASSWORD}}` | Shared with firecrawl-api (PROXY_PASSWORD). |
| `SEARXNG_ENDPOINT` | `${{firecrawl-api.SEARXNG_ENDPOINT}}` | Shared with firecrawl-api (SEARXNG_ENDPOINT). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let running jobs finish during redeploys. |

### firecrawl-nuq-worker

Same build with `FIRECRAWL_WORKER_ROLE=nuq-worker`: `NUQ_WORKER_COUNT` scrape executors, one job each. Scale with the count or with replicas.

- Source: repo `baranberkay96/firecrawl-railway`, root directory `/services/firecrawl-workers` (Dockerfile build)
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/health` (timeout 300 s)
- Public domain: no (listens on `3006` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `FIRECRAWL_WORKER_ROLE` | `nuq-worker` | Runs NUQ_WORKER_COUNT scrape-executor processes (services/firecrawl-workers/railway-workers.sh). |
| `NUQ_WORKER_COUNT` | `5` | Scrape executor processes in this container (upstream harness default 5). Each handles one job at a time. |
| `NUQ_WORKER_START_PORT` | `3006` | First health port; process i listens on start+i. |
| `PORT` | `3006` | Health port of the first executor (Railway healthcheck). |
| `ENV` | `local` | Self-hosted mode (same value as the upstream docker-compose). |
| `LOGGING_LEVEL` | `INFO` | Log level. |
| `USE_DB_AUTHENTICATION` | `false` | Supabase auth is not available for self-hosting; the firecrawl gateway enforces the API key instead. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis for BullMQ queues and crawl state. |
| `REDIS_RATE_LIMIT_URL` | `${{Redis.REDIS_URL}}` | Redis for rate limiting. |
| `NUQ_DATABASE_URL` | `postgresql://postgres:${{nuq-postgres.POSTGRES_PASSWORD}}@${{nuq-postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/postgres` | NuQ job queue database (nuq-postgres, private network). |
| `NUQ_DATABASE_URL_LISTEN` | `${{NUQ_DATABASE_URL}}` | Direct connection used for LISTEN/NOTIFY (same database). |
| `NUQ_RABBITMQ_URL` | `amqp://firecrawl:${{RabbitMQ.RABBITMQ_DEFAULT_PASS}}@${{RabbitMQ.RAILWAY_PRIVATE_DOMAIN}}:5672` | RabbitMQ used by NuQ to wake workers when jobs arrive. |
| `PLAYWRIGHT_MICROSERVICE_URL` | `http://${{playwright-service.RAILWAY_PRIVATE_DOMAIN}}:3000/scrape` | Browser rendering service (private network). |
| `BULL_AUTH_KEY` | `${{firecrawl-api.BULL_AUTH_KEY}}` | Shared with firecrawl-api (BULL_AUTH_KEY). |
| `NUM_WORKERS_PER_QUEUE` | `${{firecrawl-api.NUM_WORKERS_PER_QUEUE}}` | Shared with firecrawl-api (NUM_WORKERS_PER_QUEUE). |
| `CRAWL_CONCURRENT_REQUESTS` | `${{firecrawl-api.CRAWL_CONCURRENT_REQUESTS}}` | Shared with firecrawl-api (CRAWL_CONCURRENT_REQUESTS). |
| `MAX_CONCURRENT_JOBS` | `${{firecrawl-api.MAX_CONCURRENT_JOBS}}` | Shared with firecrawl-api (MAX_CONCURRENT_JOBS). |
| `BROWSER_POOL_SIZE` | `${{firecrawl-api.BROWSER_POOL_SIZE}}` | Shared with firecrawl-api (BROWSER_POOL_SIZE). |
| `OPENAI_API_KEY` | `${{firecrawl-api.OPENAI_API_KEY}}` | Shared with firecrawl-api (OPENAI_API_KEY). |
| `OPENAI_BASE_URL` | `${{firecrawl-api.OPENAI_BASE_URL}}` | Shared with firecrawl-api (OPENAI_BASE_URL). |
| `MODEL_NAME` | `${{firecrawl-api.MODEL_NAME}}` | Shared with firecrawl-api (MODEL_NAME). |
| `MODEL_EMBEDDING_NAME` | `${{firecrawl-api.MODEL_EMBEDDING_NAME}}` | Shared with firecrawl-api (MODEL_EMBEDDING_NAME). |
| `OLLAMA_BASE_URL` | `${{firecrawl-api.OLLAMA_BASE_URL}}` | Shared with firecrawl-api (OLLAMA_BASE_URL). |
| `PROXY_SERVER` | `${{firecrawl-api.PROXY_SERVER}}` | Shared with firecrawl-api (PROXY_SERVER). |
| `PROXY_USERNAME` | `${{firecrawl-api.PROXY_USERNAME}}` | Shared with firecrawl-api (PROXY_USERNAME). |
| `PROXY_PASSWORD` | `${{firecrawl-api.PROXY_PASSWORD}}` | Shared with firecrawl-api (PROXY_PASSWORD). |
| `SEARXNG_ENDPOINT` | `${{firecrawl-api.SEARXNG_ENDPOINT}}` | Shared with firecrawl-api (SEARXNG_ENDPOINT). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Let running scrapes finish during redeploys. |

### playwright-service

Official Playwright/Chromium scrape service, pinned by digest.

- Source: image `ghcr.io/firecrawl/playwright-service:latest@sha256:717699bf8a61d94451926c810d19ca1d36278192907e307bf5229a558b08fcc6`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: `/health` (timeout 300 s)
- Public domain: no (listens on `3000` privately)
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | HTTP port of the Playwright scrape service (private). |
| `MAX_CONCURRENT_PAGES` | `${{firecrawl-api.CRAWL_CONCURRENT_REQUESTS}}` | Concurrent browser pages; follows CRAWL_CONCURRENT_REQUESTS like upstream. |
| `BLOCK_MEDIA` | `false` | Set true to block images/video downloads (less bandwidth, faster pages). |
| `ALLOW_LOCAL_WEBHOOKS` | `false` | Keep false so pages cannot be pointed at private addresses. |
| `PROXY_SERVER` | `${{firecrawl-api.PROXY_SERVER}}` | Optional outbound proxy (shared with firecrawl-api). |
| `PROXY_USERNAME` | `${{firecrawl-api.PROXY_USERNAME}}` | Optional proxy username. |
| `PROXY_PASSWORD` | `${{firecrawl-api.PROXY_PASSWORD}}` | Optional proxy password. |

### nuq-postgres

Official NuQ Postgres image (Postgres 17 + pg_cron + NuQ schema installed at initdb), pinned by digest. Kept separate from the Railway base Postgres because the image installs extensions and cron jobs at first boot.

- Source: image `ghcr.io/firecrawl/nuq-postgres:latest@sha256:9b638af78d99873bc0ba2b57c9cbcd01df6ce96efeaa72d36cfbe0f76521e8fc`
- Start command: `docker-entrypoint.sh postgres -c max_wal_size=1GB -c min_wal_size=128MB -c wal_buffers=16MB`
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: `/var/lib/postgresql/data`
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser created on first boot (pg_cron jobs run in the postgres database). |
| `POSTGRES_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | Database password, generated. |
| `POSTGRES_DB` | `postgres` | Must stay 'postgres': the image configures cron.database_name = 'postgres' and installs the NuQ schema there. |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Data directory inside the volume (avoids the volume's lost+found). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to shut down cleanly. |

### Redis

Railway base Redis (`_railway-base/redis.json`, verbatim).

- Source: image `redis:8.2`
- Start command: `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH"`
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
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

### RabbitMQ

Message broker NuQ uses for job notifications. No volume: NuQ only declares transient, exclusive queues.

- Source: image `rabbitmq:4.3.6-alpine`
- Start command: image default
- Pre-deploy command: none
- Healthcheck: none (no HTTP listener / not applicable)
- Public domain: no
- TCP proxy: none
- Volume: none
- Restart policy: ON_FAILURE (max 10 retries); replicas: 1; cron: none

| Variable | Value | Description |
|---|---|---|
| `RABBITMQ_DEFAULT_USER` | `firecrawl` | RabbitMQ user for NuQ. |
| `RABBITMQ_DEFAULT_PASS` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | RabbitMQ password, generated. |

## Improvements over market templates

1. **Official images only** (`ghcr.io/firecrawl/*`), pinned to a version tag or digest, instead of third-party `bonkboykz/*:latest`.
2. **API key authentication.** Self-hosted Firecrawl has no key check without Supabase, so the market templates exposed an open scraping API. A Caddy gateway now requires `Authorization: Bearer <FIRECRAWL_API_KEY>` (generated `fc-…` key), which is what the Firecrawl SDKs send.
3. **Current upstream process model:** API, queue-worker, extract-worker, NuQ prefetch, NuQ reconciler and N NuQ scrape executors (the market templates predate the prefetch/reconciler workers and RabbitMQ).
4. **RabbitMQ added** as in upstream compose, so NuQ executors are woken immediately instead of polling Postgres with back-off.
5. **Private networking only:** the base template reached Redis through its public TCP proxy; now everything uses `*.railway.internal` and the API binds `::`.
6. **nuq-postgres made safe for Railway volumes:** upstream's init SQL sets `max_wal_size=16GB` / `min_wal_size=4GB` (sized for large cloud disks). The start command caps WAL at 1 GB so it fits a Hobby 5 GB volume; data lives in `pgdata/` inside the volume.
7. **Generated secrets** for Postgres, RabbitMQ, the Bull dashboard path and the API key (market had a hardcoded Postgres password and `BULL_AUTH_KEY='@'`).
8. **Healthchecks** on every HTTP process: gateway `/healthz`, API `/v0/health/readiness`, queue-worker `/liveness`, NuQ executors `/health`, Playwright `/health`.
9. **Clean restarts:** the worker launcher forwards SIGTERM so jobs can finish inside the drain window, and if one process dies it stops its siblings and exits non-zero so Railway restarts the whole group.

## Resource estimate

| Service | Idle RAM | Typical RAM | Typical vCPU | Volume |
|---|---|---|---|---|
| firecrawl (Caddy gateway) | 0.03 GB | 0.05 GB | 0.02 | – |
| firecrawl-api | 0.4 GB | 1.0 GB | 0.3 | – |
| firecrawl-worker (4 processes) | 0.7 GB | 1.2 GB | 0.3 | – |
| firecrawl-nuq-worker (5 processes) | 0.9 GB | 2.5 GB | 1.0 | – |
| playwright-service (Chromium) | 0.3 GB | 1.5 GB | 0.8 | – |
| nuq-postgres | 0.1 GB | 0.3 GB | 0.1 | 1–3 GB |
| Redis | 0.02 GB | 0.15 GB | 0.02 | < 0.5 GB |
| RabbitMQ | 0.15 GB | 0.2 GB | 0.02 | – |
| **Total** | **~2.6 GB** | **~6.9 GB** | **~2.6** | **~1.5–3.5 GB** |

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month.

- **Idle:** 2.6 GB × $10 + ~0.2 vCPU × $20 + 2 GB × $0.15 ≈ **$30/month**.
- **Typical (regular crawling, a few thousand pages per day):** 6.9 GB × $10 + 2.6 vCPU × $20 + 3 GB × $0.15 ≈ **$121/month**. Load is bursty and follows crawl volume; outbound fetches and responses count as Railway egress.

**Minimum plan: Hobby.** Trial's 1 GB per service is too small for the NuQ executors and Chromium. Pro is recommended for sustained crawling (replicas of `firecrawl-nuq-worker` and `playwright-service`).

## Verification checklist

1. All services deploy green; `https://<gateway-domain>/healthz` returns `ok`.
2. `POST https://<gateway-domain>/v2/scrape` without a key returns 401.
3. With the key: `curl -X POST https://<gateway-domain>/v2/scrape -H "Authorization: Bearer $FIRECRAWL_API_KEY" -H 'Content-Type: application/json' -d '{"url":"https://example.com","formats":["markdown"]}'` returns markdown (API → NuQ → executor → Playwright path).
4. Scrape a JavaScript-heavy page and confirm rendered content.
5. Start a crawl (`POST /v2/crawl` with `"limit": 5`) and poll `GET /v2/crawl/<id>` until `completed` (queue-worker, prefetch, RabbitMQ wake-ups).
6. Open `https://<gateway-domain>/admin/<BULL_AUTH_KEY>/queues` and see the BullMQ dashboard.
7. Redeploy nuq-postgres and Redis; new jobs still run.
8. Raise `NUQ_WORKER_COUNT` or add a replica to `firecrawl-nuq-worker`; throughput rises.

## Open questions

- **Responsible use (Railway Fair Use Policy):** operators are responsible for complying with target sites' terms of service, robots.txt and applicable law; Railway forbids scrapers that violate the terms of the sites they target. Stated in the README.
- **RabbitMQ 4.3 vs upstream `rabbitmq:3-management`:** community 3.x images stopped receiving updates (last build 2025-12). NuQ only uses AMQP 0-9-1 with transient exclusive queues, which 4.x supports, but this is not runtime-tested. Use `rabbitmq:3.13-alpine` if AMQP errors appear.
- **Split process model:** upstream's Docker path is the all-in-one harness; running the entrypoints as separate services follows the upstream Kubernetes examples, but the prefetch/reconciler/extract split is not documented there. Fallback: set `firecrawl-api`'s start command to `node dist/src/harness.js --start-docker` and remove the two worker services.
- **Digest-pinned images:** playwright-service and nuq-postgres only publish `latest`; refresh their digests when upgrading the API image.
- **`IS_KUBERNETES=true` on firecrawl-worker** makes back-pressure read cgroup v2 files; if they are missing the code falls back to 0% usage (jobs are never rejected for load).
- **Single shared API key:** no per-user keys, quotas or rate limits in self-hosted mode.
- Not deploy-tested in this package (local files only).
