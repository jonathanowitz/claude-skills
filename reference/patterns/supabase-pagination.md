# Supabase / PostgREST Pagination

PostgREST (which Supabase sits on top of) caps every response at **1000 rows**. An explicit `.limit(5000)` does not defeat it — the cap is server-side `max_rows`. Any query that could return >1000 rows must paginate via `.range()` or it will silently truncate.

## When to Use

- Any unfiltered `SELECT` against a table that can grow past 1000 rows (gyms, teams, schedule entries, users).
- Any `SELECT` where the filter is weak enough that >1000 rows could match (e.g. "all active X", "everything from the last year").
- Admin/backfill/export code paths that need the full set.

**Safe to skip:** searches with bounded filters (`.eq('id', uuid)`, `.ilike('name', '%query%')` with user-typed query), or paginated UI that only ever shows one page at a time.

## The Pattern

```js
const PAGE = 1000;
const rows = [];
let from = 0;
while (true) {
  const { data, error } = await client
    .from('table')
    .select('...')
    .order('...')            // deterministic ordering is mandatory — without it, page boundaries overlap or skip
    .range(from, from + PAGE - 1);

  if (error) throw new Error('query failed: ' + error.message);
  if (!data || data.length === 0) break;
  rows.push(...data);
  if (data.length < PAGE) break;   // short page = last page
  from += PAGE;
}
```

Key details:
- **`.order()` is mandatory.** Without a deterministic order, pages can overlap or skip rows.
- **Stop on short page, not on empty array.** An empty array only happens when `from` is past the end; stopping on `data.length < PAGE` saves one round-trip.
- **`.range(from, to)` is inclusive on both ends.** `range(0, 999)` fetches 1000 rows.

### Bumping `.limit()` does not work

Tested on 2026-04-20 against Supabase production:
```
GET /rest/v1/gyms?limit=2000 + Range: 0-1404  →  returns 1000 rows
```
The 1000-row cap is enforced by PostgREST's `max_rows` config at the server level. The client-side `.limit()` only trims further; it cannot raise the cap.

### Helper function

For any file that calls the same table repeatedly, wrap the loop once:

```js
async function fetchAll(client, table, { select = '*', order = 'id', ascending = true } = {}) {
  const PAGE = 1000;
  const rows = [];
  let from = 0;
  while (true) {
    const { data, error } = await client.from(table).select(select).order(order, { ascending }).range(from, from + PAGE - 1);
    if (error) throw error;
    if (!data?.length) break;
    rows.push(...data);
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return rows;
}
```

## Why This Matters

The truncation is **silent**. No error, no warning — the client just sees 1000 rows and assumes it's the full set. Bugs caused by this are invisible until someone who sorts past row 1000 complains, and by then the system has already shipped data-complete-looking UI to every user.

Specific failure modes seen in prod:
- Autocomplete pickers missing late-alphabet entries.
- "All users" admin views missing recently-added users.
- Backfill scripts skipping rows silently.
- Count badges disagreeing with list views because one used `count: exact` and the other iterated the list.

## Guards to Add

When writing or reviewing a Supabase query, ask:

1. **Could this table exceed 1000 rows in prod at any point in the next 2 years?** If yes, paginate unconditionally — don't wait for it to happen.
2. **Is there a deterministic `.order()`?** If no, add one.
3. **If this is a handler returning "all X", does the caller need the full set?** If it's driving an autocomplete or picker, yes. If it's a paginated table UI, no — use server-side pagination with `range` per page instead.
4. **Is the `.limit()` misleading?** `.limit(5000)` reads as "fetch up to 5000" but actually fetches up to 1000. Either paginate (and remove the `.limit`) or drop the number below 1000 so the code's intent matches its behavior.

## Evidence

- **2026-04-20 — #662 / PR #663.** Home-gym selector in `example-app` was missing Acme Widgets and every other "The ___" / late-alphabet gym. Root cause: `web/gym-team-selector.js` `fetchGyms()` used Supabase direct with no `.limit()` and no pagination; `api/_lib/handlers/gyms.js` passed `limit: 1000` explicitly. Prod had 1405 gyms; 1191 sort alphabetically before "Acme Widgets", so they fell past the 1000-row cap. Users could not select their home gym. Fix paginated both paths via `.range()` in 1000-row chunks. Hotfix shipped in ~15 min from diagnosis to merged PR, but the bug had been latent since the gym table grew past ~1000 rows — weeks to months.

## Related Gotcha: LIKE on UUID Columns Returns Empty

PostgREST does **not** implicitly cast a `uuid` column to `text` for `.like()` / `.ilike()` queries. A query like `.like('id', 'd3053e6b%')` silently returns zero rows — no error, no warning.

```js
// WRONG — always returns empty for uuid columns
const { data } = await client.from('subscriptions').select('*').like('id', 'd3053e6b%');
// data = []   ← NOT evidence of absence

// CORRECT — exact match or count
const { data } = await client.from('subscriptions').select('*').eq('id', 'd3053e6b-...-full-uuid');
const { count } = await client.from('subscriptions').select('id', { count: 'exact', head: true }).eq('id', 'd3053e6b-...');
```

**Rule:** Never conclude a row is absent from a uuid-PK table based on a pattern-match query. Verify row-absence with an exact `.eq()` or a `count` with `head: true`. A "row not found" from a type-mismatched query is not evidence of deletion.

**Evidence:** 2026-05-29 — `.like('id', 'd3053e6b%')` returned empty on a valid active subscription. Propagated a false "row deleted" claim into a PR body and two chat turns before an exact-match SELECT surfaced the row.

## See Also

- `workflows/supabase-schema-workflow.md` — schema changes (different failure mode, same platform)
- PostgREST docs: https://postgrest.org/en/stable/references/api/pagination_count.html
