# API-key gateway in front of the private Firecrawl API.
# Self-hosted Firecrawl has no built-in API key check (USE_DB_AUTHENTICATION needs
# Supabase), so this Caddy instance is the only public entry point and rejects
# requests without "Authorization: Bearer $FIRECRAWL_API_KEY".
FROM caddy:2.11.7-alpine

COPY Caddyfile /etc/caddy/Caddyfile

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
