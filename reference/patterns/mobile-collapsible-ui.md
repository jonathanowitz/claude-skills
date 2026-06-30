# Mobile Collapsible UI Patterns

## Problem
Large filter or control panels consume valuable mobile screen real estate, pushing content below the fold. Users need the controls, but not always visible.

## Key Principle: Always-Visible Toggle
**Place the toggle button in an element that never collapses.** Common patterns:
- Sticky header (nav bar)
- Sticky results/summary bar (e.g., "X items showing")
- Fixed footer

Avoid putting toggle in the panel itself—users can't access it if the panel is collapsed.

## Implementation

### HTML Structure
```html
<!-- Always-visible container -->
<div class="results-bar">
  <span id="result-count">42 performances showing</span>
  <button id="filter-toggle">Show Filters</button>
</div>

<!-- Collapsible panel -->
<section class="filters" id="filters">
  <!-- Filter content -->
</section>
```

### CSS: Sticky + Z-Index Management
```css
/* Results bar stays visible, on top */
.results-bar {
  position: sticky;
  top: 0;
  z-index: 11;  /* Higher than filters */
  background: #fff;
}

/* Filters collapse independently */
.filters {
  background: #fff;
  /* NO sticky - collapses normally */
}

.filters.collapsed {
  display: none;
}
```

### JavaScript: Toggle & Text Update
```javascript
filterToggle.addEventListener("click", () => {
  filtersEl.classList.toggle("collapsed");
  updateButtonText();
});

function updateButtonText() {
  if (filtersEl.classList.contains("collapsed")) {
    filterToggle.textContent = "Show Filters";
  } else {
    filterToggle.textContent = "Hide Filters";
  }
}
```

## Responsive Design

### Desktop (always show)
```css
@media (min-width: 600px) {
  .filter-toggle {
    display: none;  /* Button hidden */
  }

  .filters {
    display: flex;  /* Filters always open */
  }
}
```

### Mobile (togglable)
```css
@media (max-width: 599px) {
  .filter-toggle {
    display: block;  /* Button visible */
  }

  .filters.collapsed {
    display: none;  /* Filters hidden by default */
  }
}
```

## UX Best Practices

### Button Clarity
- **Use text, not just icons** — "Show Filters" > "▼" (clearer intent)
- **Dynamic text** — Changes to reflect current state
- **Obvious placement** — Always-visible area, ideally with related content (results count)

### Default States
- **Desktop:** Filters open (enough space)
- **Mobile:** Filters open initially, user can collapse (discovery), then toggle as needed
- **Optional:** Save toggle state to localStorage for power users

### Avoid
- ❌ Hamburger menu in collapsing header (header collapses, button disappears)
- ❌ Toggle buried in filter panel (can't collapse if button is inside)
- ❌ No label, just icon (unclear what it does)
- ❌ Multiple sticky elements with same `top` value (they overlap)

## Sticky Positioning Gotchas

### Problem: Overlapping Sticky Elements
```css
/* ❌ Both at top: 0, they overlap */
.header { position: sticky; top: 0; }
.filters { position: sticky; top: 0; }  /* Covers header */
```

### Solution: Adjust Z-Index + Top Values
```css
/* ✅ Results bar floats above filters */
.results-bar {
  position: sticky;
  top: 0;
  z-index: 11;  /* Higher */
}

.filters {
  position: sticky;
  top: 3rem;  /* Below results bar */
  z-index: 10;
}
```

Or: **Remove sticky from collapsing panels** — let them scroll naturally:
```css
.filters {
  /* No position: sticky */
  /* Collapses/expands, no overlap issues */
}
```

## Real-World Examples

**E-commerce:** Product filters collapsible on mobile, always-visible toggle next to "X results"
**Social feed:** Feed settings/filters above timeline, toggle in sticky header
**Admin dashboards:** Table filters above table, toggle in sticky toolbar

## See Also
- `composite-key-patterns.md` — Key management for filtered selections
- `url-parameter-patterns.md` — Persisting filter state across sessions
