# Firecrawl worker processes for Railway.
# Same official image as firecrawl-api; only adds a small launcher that runs one
# group of worker processes (what the upstream harness starts inside the api
# container) so workers can be scaled and restarted independently of the API.
FROM ghcr.io/firecrawl/firecrawl:2.11.504

COPY --chmod=755 railway-workers.sh /usr/local/bin/railway-workers.sh

WORKDIR /app
CMD ["/usr/local/bin/railway-workers.sh"]
