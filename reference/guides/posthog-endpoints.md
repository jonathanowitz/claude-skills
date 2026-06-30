# PostHog Endpoints — Reference

> Captured 2026-06-01 from a `/scan` of https://posthog.com/docs/endpoints. **Beta feature** — don't build anything load-bearing on it without a fallback. Example Project already runs PostHog, so this is a real option if customer/organizer-facing analytics lands on the roadmap.

## What it is

**Endpoints** turn a saved insight or a HogQL/SQL query into a **stable, cached, rate-limited API URL** you call from your own app. It's the productized path for embedding PostHog analytics in a customer-facing surface without rebuilding the query each time or rolling your own caching layer.

Three-step model: (1) define data via an insight or SQL query → (2) convert it to a stable endpoint URL → (3) call it from your app (cURL / Python / Node / TypeScript / Go / OpenAPI SDK).

## Why it exists — the Query API sharp edge

The raw Query API (`POST /api/projects/:project_id/query/`, body `{ query: { kind: "HogQLQuery", query: "<SQL>" } }`, Bearer token w/ "Query Read" personal API key) is for **ad-hoc / embedded** use only:

- Returns **100 rows** default, **50k max** with explicit `LIMIT`.
- **Explicitly prohibits bulk exports and recurring syncs** — those get rate-limited or rejected. PostHog says use **batch exports** for scheduled/large transfers.

**Footgun:** don't put `/query` on a cron. For repeated programmatic reads, use an Endpoint (higher rate limits, query known in advance → faster) or batch exports for bulk.

## What Endpoints add over raw `/query`

- **Stable URLs** — query is predefined, so the call shape is consistent and faster.
- **Built-in caching** — auto-returns cached data; configurable **TTL**, auto re-execution when freshness drops below your threshold. "Eliminates the need to implement your own caching layer."
- **Higher rate limits** than ad-hoc `/query`.
- **Materialization** — pre-compute hot queries / materialized views behind the endpoint for fast response.

## Best-practice notes

- Use shorter time ranges; apply filters to limit data scanned.
- Avoid redundant table scans; lean on materialized views for frequently-hit metrics.
- Security framing: expose a **secure subset** of analytics to customers without exposing full infrastructure.

## Pricing

Free during beta. Future pricing based on **compute usage + data scanned**.

## Example Project applicability (when, not now)

- Organizer/coach-facing dashboard — attendance trends, signup counts, event metrics — served from a parameterized endpoint instead of hand-rolled Supabase aggregation + custom caching.
- Landing-page live metrics ("X events scheduled this week") via a materialized endpoint.
- Could replace any Vercel serverless function currently juggling manual PostHog query + cache.

## Links

- Endpoints overview — https://posthog.com/docs/endpoints
- Start here — https://posthog.com/docs/endpoints/start-here
- Best practices — https://posthog.com/docs/endpoints/best-practices
- Query API (the primitive underneath) — https://posthog.com/docs/api/queries
