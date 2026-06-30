# Event Delegation Patterns (Vanilla JS)

Reference for wiring event handlers in views that re-render via `innerHTML`.

---

## The Listener Leak Anti-Pattern

**Never attach event listeners inside functions that re-run** — interval callbacks, re-render functions, or event handlers that trigger re-renders. Each call adds a duplicate listener.

```javascript
// BAD — renderTimeline() runs every 60s via setInterval AND on followsChanged
function renderTimeline(entries) {
  container.innerHTML = buildHTML(entries);
  // This adds a NEW listener every time renderTimeline runs
  container.querySelector('.list').addEventListener('click', handleClick);
}
```

```javascript
// GOOD — wire once in init() on a stable container that survives innerHTML rewrites
function init() {
  const container = document.getElementById('view-gym');
  container.addEventListener('click', (ev) => {
    const target = ev.target.closest('.fav-star');
    if (target) handleStarClick(ev);
  });
}

function renderTimeline(entries) {
  // Only update innerHTML — listeners on the parent survive
  container.innerHTML = buildHTML(entries);
}
```

**Why this works:** Event delegation relies on event bubbling. The listener lives on a parent element that is never destroyed by `innerHTML`. Child elements are replaced freely — clicks still bubble up to the stable parent.

---

## When to Use Each Pattern

### Event delegation on stable parent (preferred)
- Container content changes via `innerHTML`
- Multiple child elements share the same interaction (e.g., star buttons on every card)
- Wire in `init()`, filter with `ev.target.closest('.selector')`

### Direct listener on element
- Element is created once and never replaced
- Only one instance exists (e.g., a submit button)
- Simpler code when delegation isn't needed

### Targeted DOM updates (avoid full re-render)
When an event elsewhere changes state that affects your view, update specific elements instead of re-rendering the entire container:

```javascript
// Instead of re-rendering everything on followsChanged:
window.addEventListener('followsChanged', () => {
  document.querySelectorAll('.fav-star').forEach(star => {
    const id = star.dataset.teamId || star.dataset.gymId;
    const isFav = window.Follows?.isFollowing(id);
    star.classList.toggle('active', isFav);
    star.textContent = isFav ? '\u2605' : '\u2606';
  });
});
```

This avoids: DOM flash, layout shift, scroll position reset, and re-attaching listeners (if you made the mistake of wiring them in the render function).

---

## Checklist Before Wiring Handlers

1. **Does this container re-render?** Check for `innerHTML =`, `setInterval` calling render, or event listeners that trigger re-render. If yes → delegate on a stable parent.
2. **Is the parent stable?** The element you attach to must survive all re-renders. Usually a view container (`#view-gym`, `#schedule-container`) set up once in HTML.
3. **Can you update in-place?** If an external state change only affects a few attributes (class, text, aria-label), update those directly instead of re-rendering.

---

**Evidence:** Gemini caught this exact bug in a plan review (2026-03-17, #61). Handler was proposed inside `renderTimeline()` which runs on a 60s interval — would have leaked listeners and caused multiple handler calls per click.
