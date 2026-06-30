# URL Parameter Patterns for Shareable State

## Problem
Users filter/configure an app, want to share that exact state with others. Without URL parameters, the recipient gets defaults. With URL params, they get the exact same view.

## Two Approaches

### 1. Read-Only (Simpler)
- Parse URL params on page load
- Apply them to set defaults
- No automatic URL updates as user changes filters
- **Good for:** Setup links, onboarding, static configurations

### 2. Read + Write (Full State Sync)
- Parse URL params on load
- Update URL as user changes state
- User can copy URL anytime to share
- **Good for:** Collaborative apps, saved views, bookmarkable states

This guide covers **Read-Only** (simpler, covers 80% of use cases). Write updates require managing URL history without full page reloads.

## Implementation: Read-Only

### URL Format
Choose a clear, shareable format:

```
?gym=Acme%20Widgets&city=Springfield&teams=Red,Blue&competitors=true
```

Encoding:
- Spaces → `%20`
- Commas for arrays: `teams=A,B,C`
- Booleans: `true` / `false`

### JavaScript: Parse & Apply

```javascript
function applyUrlParams() {
  const params = new URLSearchParams(window.location.search);

  const gym = params.get("gym");
  const city = params.get("city");
  const teams = params.get("teams");
  const competitors = params.get("competitors") === "true";

  // Apply gym
  if (gym) {
    selectedGym = gym;
    gymInput.value = gym;
  }

  // Apply city
  if (city) {
    selectedCity = city;
  }

  // Apply teams (array: split comma-separated list)
  if (teams) {
    teams.split(",").forEach(team => {
      const trimmed = team.trim();
      // Handle composite keys if needed (see composite-key-patterns.md)
      const key = selectedGym ? `${selectedGym}|${trimmed}` : trimmed;
      selectedTeams.add(key);
    });
  }

  // Apply competitors
  if (competitors) {
    showCompetitors = true;
  }
}

// Call during initialization, before rendering
document.addEventListener("DOMContentLoaded", () => {
  applyUrlParams();  // Before other filters load
  loadFilters();     // localStorage as fallback
  render();
});
```

### JavaScript: Generate Shareable URL

```javascript
function generateShareUrl() {
  const params = new URLSearchParams();

  if (selectedGym) {
    params.set("gym", selectedGym);
  }

  if (selectedCity) {
    params.set("city", selectedCity);
  }

  // Array: extract names from composite keys
  if (selectedTeams.size > 0) {
    const teamNames = [...selectedTeams].map(key => {
      const parts = key.split("|");
      return parts.length > 1 ? parts[1] : parts[0];
    });
    params.set("teams", teamNames.join(","));
  }

  if (showCompetitors) {
    params.set("competitors", "true");
  }

  const baseUrl = window.location.origin + window.location.pathname;
  return params.toString() ? `${baseUrl}?${params}` : baseUrl;
}

// Expose via button
document.getElementById("share-btn").addEventListener("click", () => {
  const url = generateShareUrl();
  navigator.clipboard.writeText(url).then(() => {
    console.log("URL copied to clipboard");
  });
});
```

## Priority: URL > localStorage

If both exist, URL params should take priority (shared links override saved preferences):

```javascript
document.addEventListener("DOMContentLoaded", () => {
  // URL params first (highest priority)
  applyUrlParams();

  // localStorage as fallback
  loadFilters();

  // If URL params were applied, they overwrite localStorage values
  render();
});
```

## Encoding Considerations

### Using URLSearchParams (Recommended)
Handles encoding automatically:
```javascript
const params = new URLSearchParams();
params.set("name", "John Doe");  // Automatically → "John%20Doe"
const url = "?" + params.toString();  // Safe to use
```

### Manual Encoding (If Needed)
```javascript
const encoded = encodeURIComponent("Acme Widgets");
// "Acme%20Widgets"
```

### Composite Keys in URLs
If using composite keys (see `composite-key-patterns.md`), extract just the entity name:

```javascript
// Store: "Acme Widgets|Red"
// URL: teams=Red (omit scope, reconstruct on load with current gym)
// Load: reconstruct key from selectedGym + team name
```

## Testing

```javascript
// Test URL:
// http://localhost:3000?gym=Acme&city=Springfield&teams=Red,Blue&competitors=true

// Verify:
console.log(selectedGym);        // "Acme"
console.log(selectedCity);       // "Springfield"
console.log(selectedTeams);      // Set {"Acme|Red", "Acme|Blue"}
console.log(showCompetitors);    // true
```

## Optional: Write Mode (Advanced)

For full URL sync, replace `History.pushState()` instead of reloading:

```javascript
function updateUrl() {
  const url = generateShareUrl();
  window.history.replaceState({}, "", url);
}

// Call after any filter change
filterToggle.addEventListener("change", updateUrl);
teamCheckboxes.addEventListener("change", updateUrl);
```

⚠️ **Warning:** Can cause back-button confusion if not implemented carefully.

## Real-World Examples

**Example 1: Generic schedule** 
```
?gym=Acme%20Widgets&city=Springfield&teams=Red,Blue&competitors=true
```

**Example 2: E-commerce filters**
```
?category=shoes&brand=Nike,Adidas&price=50-200&sort=price_asc
```

**Example 3: Analytics dashboard**
```
?date_range=2026-01-01:2026-02-04&metric=revenue&region=US,CA
```

## See Also
- `composite-key-patterns.md` — Handling composite keys in URLs
- `mobile-collapsible-ui.md` — UI for toggling filters (often used with URLs)
