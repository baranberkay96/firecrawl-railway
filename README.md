# Deploy and Host Firecrawl with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/firecrawl-v2-web-data-api-for-ai)

Firecrawl is an open-source API that turns websites into clean markdown, HTML, screenshots or structured JSON for LLM applications. This community template deploys the self-hosted Firecrawl stack on Railway with separate workers, a headless Chromium renderer, its queue databases and an API-key gateway in front.

## About Hosting Firecrawl

Self-hosted Firecrawl is more than one API container. Scrape and crawl requests are queued, executed by worker processes that fetch pages directly or through a Playwright/Chromium service, converted to markdown, and tracked in Redis and a dedicated Postgres queue (NuQ) with RabbitMQ notifications. Without its cloud authentication backend, a self-hosted instance also accepts requests from anyone who knows the URL. This template runs the official Firecrawl images with the API, orchestration workers and scrape executors as separate Railway services, keeps all databases on the private network, and adds a small gateway that only forwards requests carrying your generated API key.

## Common Use Cases

- Convert documentation sites, help centers and blogs you are permitted to crawl into markdown for RAG pipelines.
- Give AI agents a scrape and search tool through the Firecrawl SDKs, MCP server or n8n/LangChain integrations.
- Extract structured JSON from product or listing pages with an OpenAI-compatible model.
- Monitor your own or partner sites for content changes on a schedule.

## Dependencies for Firecrawl Hosting

- Firecrawl API and worker image `ghcr.io/firecrawl/firecrawl:2.11.504`
- Firecrawl Playwright service (headless Chromium) and NuQ Postgres images (pinned by digest)
- Redis (Railway Redis 8.2) and RabbitMQ 4.3
- Caddy 2.11 as the API-key gateway
- Optional: an OpenAI-compatible API key for JSON extraction and `/extract`

### Deployment Dependencies

- Self-hosting guide: https://github.com/firecrawl/firecrawl/blob/main/SELF_HOST.md
- Upstream docker-compose: https://github.com/firecrawl/firecrawl/blob/main/docker-compose.yaml
- API reference: https://docs.firecrawl.dev/api-reference/introduction
- Railway Fair Use Policy: https://railway.com/legal/fair-use

### Implementation Details

| Service | Role | Public | Storage |
|---|---|---|---|
| firecrawl | Caddy gateway, checks `Authorization: Bearer {key}` | Yes (port 8080) | – |
| firecrawl-api | Firecrawl HTTP API | No | – |
| firecrawl-worker | Crawl orchestration, extract, NuQ prefetch and reconciler | No | – |
| firecrawl-nuq-worker | Scrape executors (5 processes by default) | No | – |
| playwright-service | Headless Chromium rendering | No | – |
| nuq-postgres | NuQ job queue (Postgres + pg_cron) | No | Volume |
| Redis | BullMQ queues, crawl state, rate limits | No | Volume |
| RabbitMQ | Job wake-up notifications | No | – |

**First request**

1. Copy `FIRECRAWL_API_KEY` from the `firecrawl` (gateway) service variables.
2. Use the gateway's public URL as the API URL in an SDK (for example `FirecrawlApp(api_key=..., api_url="https://{gateway-domain}")`) or call it directly:
   `curl -X POST https://{gateway-domain}/v2/scrape -H "Authorization: Bearer {key}" -H "Content-Type: application/json" -d '{"url":"https://example.com","formats":["markdown"]}'`
3. The BullMQ queue dashboard is at `https://{gateway-domain}/admin/{BULL_AUTH_KEY}/queues` (`BULL_AUTH_KEY` is on `firecrawl-api`).
4. To enable JSON extraction and `/extract`, set `OPENAI_API_KEY` (and optionally `OPENAI_BASE_URL`, `MODEL_NAME`) on `firecrawl-api`; the workers reference those values.

**Scaling:** raise `NUQ_WORKER_COUNT` on `firecrawl-nuq-worker` or add replicas to it for more parallel scrapes, and add replicas to `playwright-service` for heavier JavaScript rendering. Keep `firecrawl-worker` at one replica.

**Pinning and upgrades:** the Firecrawl version is the image tag on `firecrawl-api` and in `services/firecrawl-workers/Dockerfile`; change both together. Playwright and nuq-postgres are pinned by digest because upstream only publishes `latest`; refresh the digests when you upgrade.

**Responsible use:** you are responsible for complying with the terms of service, robots.txt rules and applicable laws of every site you scrape. Railway's Fair Use Policy forbids scrapers that violate the terms of the sites they target; only crawl content you are permitted to access.

### Why Deploy Firecrawl on Railway?

Railway runs the eight services as one project with private networking, generated credentials, volumes for the queue databases and usage-based billing, so idle time stays cheap and crawl bursts scale with replicas. The gateway gives you a single authenticated HTTPS endpoint without managing servers.
