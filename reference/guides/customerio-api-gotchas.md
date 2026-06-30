# Customer.io API Gotchas

Quirks of the Customer.io Fly (UI) API that the official skill docs don't fully surface. Each entry is grounded in an actual session where the wrong behavior cost cycles.

Workspace context: Example Co. — `account_id: <ACCOUNT_ID>`, `environment_id: <WORKSPACE_ID>`. Authenticate the MCP via `mcp__customerio__authenticate` if calls return HTML or 401.

## 1. Anchors carry the audience composition — not `filters`

When you want a campaign trigger like "in segment X **and** not in segment Y," the right place to express it is the `anchors` field on `update_type: "recipients"` — **not** the separate `filters` field.

`anchors` accepts an array of `segments_negatable` entries that are AND'd together. Each entry has a `negate` flag for inclusion vs exclusion:

```json
[
  { "negate": false, "segments": [1],  "type": "segments_negatable" },
  { "negate": true,  "segments": [29], "type": "segments_negatable" },
  { "negate": true,  "segments": [3],  "type": "segments_negatable" }
]
```

That reads as: in segment 1, not in 29, not in 3. Encode via `base64(encodeURIComponent(JSON.stringify(...)))` before sending.

The `filters` field is a different beast — it's an attribute-based audience filter, encoded the same way but with a different DSL (FilterCondition objects, not segments_negatable). In practice it 500s when you try to set it programmatically with a pure-negative composition like `[{"type":"segment","id":3,"inverse":true}]`. The UI accepts it via a different code path. Don't waste cycles on `filters` if anchors can express what you need.

**Rule of thumb:** if you can express the audience as a combination of segment memberships, use anchors. Reserve `filters` for attribute-based gating that has no segment equivalent.

## 2. `global_exit_conditions` only saves under `update_type: "exit_conditions"`

The schema description on `update_type: "exit_and_conversion"` claims it covers "all conversion fields + `exit_on_trigger_or_filter_not_matched`, `global_exit_conditions`." That second field is a silent lie.

When you send `global_exit_conditions` under `exit_and_conversion`, the API returns 200, the conversion fields persist, but `global_exit_conditions` comes back `null` on the next read. The skill doc's warning ("If `global_exit_conditions` comes back `null` in the response, your format was wrong — the API silently ignores malformed exit conditions") is the symptom, but the cause here isn't malformed JSON — it's the wrong `update_type`.

Pattern that works: split the call.

```
PUT /campaigns/:id  body: { campaign: { update_type: "exit_and_conversion", conversion: ..., conversion_type: ..., ... } }
PUT /campaigns/:id  body: { campaign: { update_type: "exit_conditions", exit_on_trigger_or_filter_not_matched: true, global_exit_conditions: [...] } }
```

The second call is the one that persists `global_exit_conditions`. Always re-read the campaign after writing to confirm — the silent-fail behavior is the worst kind because the API gives no signal that anything went wrong.

`global_exit_conditions` uses the nested wrapper format: `[{"segment": {"id": 3}}, {"segment": {"id": 28}}]`.

## 3. The recipients block is full-replace, not partial-merge

Every `update_type: "recipients"` write replaces the entire recipients section. Omitted fields can be silently cleared. The skill docs flag a real customer incident where omitting `filters` while updating `attribute_filters` wiped segment targeting on 52 running campaigns.

**Required pattern:**
1. Fetch the campaign: `GET /campaigns/:id`
2. Pull all five recipient fields from the response: `type`, `event`, `attribute_filters`, `filters`, `anchors`. (Plus `recipients_filter` if it's a broadcast.)
3. Modify only the field(s) you intend to change.
4. PUT back the full set with unchanged fields passed through verbatim. Do not decode/re-encode `filters` or `anchors` — pass the exact base64 string you read.

This is non-negotiable on production campaigns. Even on draft campaigns, partial PUTs will bite you eventually.

## 4. Verify everything with a re-read

Customer.io's API has multiple silent-fail modes:
- Wrong `update_type` → 200, field ignored
- Malformed filter JSON → 200, field stored as null
- Wrong filter wrapper shape → 200, field stored as the literal wrong shape, never matches anyone

After any non-trivial write, re-read the campaign and assert the field you wrote is present and shaped correctly. The cost is one GET; the cost of skipping it is finding out three weeks later that your exit conditions weren't actually configured.

## 5. Segment build state is async but fast

After creating a dynamic segment, it enters `state: "build"` while conditions evaluate. Poll `GET /segments/:id/status` until `state: "complete"`. In practice this completes in 1–3 seconds even on ~1,500-user workspaces, so a single retry with a 3-second delay is usually enough.

## 6. Use the MCP, not raw curl, for ad-hoc inspection

The auth token (`JOURNEYS_ACCESS_TOKEN`) doesn't live in the shell environment when the MCP server is the auth holder. `curl -H "Authorization: Bearer $JOURNEYS_ACCESS_TOKEN"` returns empty bodies because the variable expands to nothing. Use `cio_read_api` for any read you'd otherwise reach for `curl`.

## 7. The MCP `cio_*_api` tools CAN reach `/design-studio/api/...` endpoints

The Customer.io skill (`skills/design-studio`) states that Design Studio API endpoints (PATCH component markup, render-to-validate, publish-to-template) require curl with auth setup because `$CIO_ACCESS_TOKEN` isn't exposed in the shell. **This is incorrect for the MCP.**

The MCP tools (`cio_read_api`, `cio_write_api`) reach `/design-studio/api/workspaces/<env_id>/nodes/<id>` (and sibling paths) without any special auth setup. Workspace routing is server-side — the MCP server holds the token and routes the request. Confirmed live during the 2026-05-18 session: PATCH component markup, GET `check-unpublished-changes`, and GET node state all worked via `cio_write_api`/`cio_read_api` with full `/design-studio/api/...` paths.

**Practical implication:** When iterating on component markup, you do NOT need to hand-off to USER for DS UI edits. Use `cio_write_api` with the `/design-studio/api/workspaces/<WORKSPACE_ID>/nodes/<node_id>` path directly. The skill's "curl-only" caveat applies to raw shell curl only, not to the MCP.

## 8. Design Studio snapshots components at save time — edits don't auto-propagate

When a DS email node is saved, it **snapshots** the current markup of any custom components (`od-*`) it uses into the email's stored HTML. It does NOT store references that resolve at render time.

**Consequence:** If you update a component (e.g., fix the gradient on `od-cta-pricing-general`), email nodes that already include that component will NOT pick up the change automatically. You must:
1. Re-open each affected email node in DS
2. Re-save the node (this re-snapshots the component at its new state)
3. Re-publish the node to its journey template

**Key trap:** re-saving and re-publishing a node does NOT set `hasUnpublishedChanges: true` on the component itself — only on the node. Checking `check-unpublished-changes` on the component after you've re-saved nodes will still return `false`. The component is "clean"; it's the node that needs updating.

**Propagation pattern for live campaigns:** batch all component changes before the node re-save/re-publish cycle. Each publish to a live-campaign template carries risk (especially on `automatic` actions), so minimizing publish cycles matters. Confirm: make all component edits → re-save node → verify node HTML → publish once.

Confirmed during 2026-05-18 session: gradient fix on `od-cta-pricing-general` + bottom-corner fix on `od-section-medium` both required node re-save + re-publish to appear in templates 16 + 21.

## 9. Never infer Customer.io campaign send/state from a single field

Campaign state is volatile and CIO's field names are misleading:
- `sending_state: "draft"` does NOT mean "not yet sent" — an action in `draft` state can already have `delivered_count > 0` (manually sent).
- `sending_state: "automatic"` on a running campaign means the action WILL fire automatically for in-flight cohort members. This is high-risk if you assumed it was safe.
- Campaign `state: "running"` vs `"sunsetting"` is changed by the account owner in the UI; agents cannot change campaign state (403).

**Required corroboration before asserting any claim about send status:**
1. `GET /v1/environments/<env_id>/campaigns/<id>/actions/<action_id>` → check `sending_state`
2. `GET /v1/environments/<env_id>/campaigns/<id>/actions/<action_id>/metrics` → check `delivered_count`, `opened_count`
3. `GET /design-studio/api/workspaces/<env_id>/nodes/<node_id>/journeys` → confirms which template/action the node is linked to

Treat campaign state as volatile — re-verify at each decision point, not just at session start. An action can move from `draft` → `automatic` between your reads. (Evidence: 2026-05-18 session — Acme action 17 was inferred as "manual/calm" from `draft` state, then discovered to be `automatic` on a live running campaign, requiring defuse before any writes.)

## 10. Unsubscribe URL must use Liquid TAG `{% unsubscribe_url %}` — not OUTPUT `{{ unsubscribe_url }}`

In CIO Empty Layout templates, the unsubscribe link uses the **Liquid TAG form**:

```html
<a href="{% unsubscribe_url %}">Unsubscribe</a>
```

The standalone brand reference HTML files (`example-marketing-plus.html`, etc.) use `{{ unsubscribe_url }}` — the Liquid OUTPUT form — because they are hand-rolled static files, not CIO-rendered templates.

If you copy unsubscribe markup from a brand reference HTML into a CIO template body field without changing to the tag form, CIO's Liquid renderer will throw `undefined variable: unsubscribe_url` on test send or live send, because no `unsubscribe_url` variable is injected into the template context — it's a built-in TAG, not a variable.

**Ground truth:** when in doubt, open the Empty Layout's body (via `cio_read_api` GET template) and read what form it uses — that's authoritative for the CIO context. Never copy Liquid syntax from non-CIO references without verifying against the CIO source.

(Evidence: 2026-05-24 — shipped `{{ unsubscribe_url }}` in both Email 4 templates; USER caught it on test send. Required a full re-push of both templates with the tag form.)

## 11. Custom HTML with media queries in Empty Layout: put `<style>` block at top of body field

The CIO Empty Layout has **no `<head>` element** accessible from the `body` template field. If your email content needs media queries (e.g., responsive column widths, font-size adjustments on mobile), put the `<style>` block at the top of the `body` field rather than trying to inject into `<head>`:

```html
<style>
@media only screen and (max-width: 600px) {
  .feature-col { width: 50% !important; }
  .tier-col    { width: 25% !important; }
}
</style>
<!-- rest of email HTML -->
```

This works in most native email clients (Apple Mail, Outlook Mac, iOS Mail). Gmail web may strip `<style>` blocks from the body — content still renders, but mobile-specific sizing overrides won't apply (the table will fall back to its percentage widths, which should still be reasonable). Test in Gmail iOS before relying on the media queries for a critical layout.

(Evidence: 2026-05-24 — Email 4 comparison matrix used this pattern to deliver responsive column collapsing on mobile. Unproven in Gmail web at time of writing.)

## 12. Discovery before inference on CIO surface

The MCP exposes `cio_schema`, `cio_skills_list`, and `cio_skills_read` — these are discovery tools. Before guessing an endpoint path, skill name, required body field, or Liquid syntax, **call the discovery tool first.** Cost: 1 tool call. Saved: 1–3 dead-end calls + a 4xx response retry.

**Specific guards:**

- **Endpoint path unknown** → `cio_schema` with an operationId guess. Don't guess by URL shape.
- **Skill name unknown** → `cio_skills_list` (NOT `cio_skills_read campaigns` blind). Skill names use namespace prefixes (`fly-api/campaigns`, not `campaigns`).
- **Required body fields** → `cio_schema` GET-of-target-resource first to see the response shape, then PUT with the full shape. Minimum-body PUTs on Action endpoints will 400 because required fields (`type`, `sub_type`, `tracked`, `can_convert`, `send_to_unsubscribed`, `frequency_cap_mode`) aren't surfaced in error responses.
- **Liquid syntax** → the Empty Layout body (via `cio_read_api` GET template) is ground truth. NEVER copy Liquid syntax from non-CIO brand-reference HTML files. Built-in tags use `{% ... %}`; variables use `{{ ... }}`. Confusing the two ships a runtime undefined-variable error on test send.

**Pattern:** Discovery beats inference on CIO surface. If you find yourself reasoning "the endpoint is probably …" or "the field is probably called …" — stop and call the discovery tool. The inference cycles dominate the discovery call.

(Evidence: 2026-05-22 Email 3 — guessed endpoint path and skill name; each one `cio_skills_list` away from correct. 2026-05-24 Email 4 — copied `{{ unsubscribe_url }}` from non-CIO brand template; required full re-push after USER caught it on test send. 2026-05-25 Email 5 — action 23 PUT with minimum body returned 400; required full action-shape body. Four consecutive sessions, same class of waste.)

## Reference: action types we wired in the End-of-Season drip

For a behavioral campaign with a linear drip workflow:
- System actions auto-created on `type: "behavioral"`: `filter_match_delay_action` (entry gate) + `exit_action`
- Email steps: `email_action` with `sending_state: "draft"` (queues for manual approval before sending)
- Delay steps: `delay_seconds_action` with `delay` in seconds (`86400` = 1 day, `432000` = 5 days)

Edges chain entry → email → delay → email → ... → exit. Placeholder IDs use negative indexing: with 9 new actions in the array, `-9` is `actions[0]` and `-1` is `actions[8]`.

The full wiring example lives in the session that built campaigns 6 and 7 (May 13 2026); search `~/.claude/sessions/` for `end-of-season` if you need to reconstruct.
