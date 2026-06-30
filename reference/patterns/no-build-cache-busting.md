# Cache-Busting for No-Build-Step Projects

For vanilla JS apps with no bundler, browsers and WebViews (including Capacitor's WKWebView) can serve stale cached module files against newer orchestrator code — silently breaking inter-module contracts.

## When to Use

- Any project that loads JS/CSS via `<script src>` or `<link href>` without content-hash filenames
- Capacitor/Cordova apps where the WKWebView caches aggressively
- Anytime a module adds or renames an exported method/global

## The Pattern

### Date-based `?v=` param on all local assets

Add `?v=YYYYMMDD` to every local script and stylesheet tag in the HTML entry point:

```html
<script defer src="live-activities.js?v=20260415"></script>
<link rel="stylesheet" href="style.css?v=20260415">
```

**Rule:** Use today's date, not a sequential counter. No state to track — just use the current date when touching the file. If you deploy twice in one day, append a suffix: `?v=20260415b`.

**Exclude:**
- External CDN scripts (Sentry, PostHog) — versioned by the CDN
- Vendor files already versioned by filename (`supabase-js-2.98.0.umd.min.js`)
- Vercel/platform injected scripts (`/_vercel/insights/script.js`)

### Mandatory for new files

Any new local JS/CSS file added to the HTML entry point **must** include a `?v=` param from day one. A file added without one starts with a caching debt that only becomes visible when its API changes.

### Defensive method calls

When calling an optional method on a global exported by another module, use double optional chaining:

```js
// Wrong — throws if window.LiveActivities exists but loadQueue was added later
window.LiveActivities?.loadQueue();

// Right — silently skips if loadQueue isn't on the object yet
window.LiveActivities?.loadQueue?.();
```

This is belt-and-suspenders: the version param is the real fix; the `?.` is the last-line guard.

## Why This Matters

Without version params, browsers and Capacitor WebViews cache JS files by URL. A new deployment can land new `app.js` (which calls `module.newMethod()`) while users still have old `module.js` (which doesn't have `newMethod`) served from cache. The error is a production TypeError, non-obvious to diagnose, and affects a subset of users (those whose cache hasn't expired).

The risk multiplies as the module count grows. With 44 local files and no build step, any file whose API changes is a potential Sentry event.

## Checklist Hook

The `scripts/pr-gate.sh` check for this: verify any new `<script src>` or `<link href>` tag pointing to a local file has a `?v=` param. Add this check to the gate script so it's mechanical.

```bash
# Pseudo-check to add to pr-gate.sh
NEW_LOCAL_SCRIPTS=$(git diff "$BASE_BRANCH"...HEAD -- app.html | grep '^+.*src="[^/h][^"]*\.js"' | grep -v '?v=')
if [ -n "$NEW_LOCAL_SCRIPTS" ]; then
  step_fail "new local script tags without ?v= cache-bust param: $NEW_LOCAL_SCRIPTS"
fi
```

## Evidence

- 2026-04-15 — Sentry TypeError: `window.LiveActivities?.loadQueue is not a function`. Root cause: `live-activities.js` had no `?v=` param while `app.js?v=2` did. Users with cached old `live-activities.js` (pre-#598, no `loadQueue`) got new `app.js` that called it. Fixed by adding `?v=20260415` to all 44 local files in `app.html`. (USER/example-app#619, #620)

## See Also

- `example-app/scripts/pr-gate.sh` — where to add the automated check
