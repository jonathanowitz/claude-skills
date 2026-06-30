# Composite Key Patterns for Non-Unique Data

## Problem
When filtering or selecting entities in a list where the primary identifier (e.g., team name) isn't globally unique across all data, simple string keys fail.

**Example:** Multiple gyms have a team named "Red"
- Acme Widgets → Red
- Beta Athletics → Red

Storing just `selectedTeams = {"Red"}` matches **all** Red teams globally, even when user filtered to one gym.

## Solution: Composite Keys

Use a delimited string combining the uniqueness scope with the entity identifier.

### Pattern
```javascript
// Store: scope + delimiter + entity
const teamKey = selectedGym ? `${selectedGym}|${team}` : team;
selectedTeams.add(teamKey);

// Retrieve: split and extract
const [gym, team] = teamKey.split("|");
```

### When Populating Options
Options should be derived from **already-filtered data** so the composite key captures the right scope:

```javascript
// ✅ Correct
let filtered = allEntries;
if (selectedGym) filtered = filtered.filter(e => e.program === selectedGym);
const teams = [...new Set(filtered.map(e => e.team))];

// Create keys with selectedGym context
teams.forEach(team => {
  const teamKey = selectedGym ? `${selectedGym}|${team}` : team;
  selectedTeams.add(teamKey);
});
```

### When Matching Against Full Dataset
Use the **entry's own scope**, not the filter's selected scope:

```javascript
// ✅ Correct (use entry's program)
result = allEntries.filter(e => {
  const teamKey = `${e.program}|${e.team}`;  // Use e.program, not selectedGym
  return selectedTeams.has(teamKey);
});

// ❌ Wrong (use selectedGym - creates false matches)
result = allEntries.filter(e => {
  const teamKey = `${selectedGym}|${e.team}`;  // BUG: matches all entries named e.team
  return selectedTeams.has(teamKey);
});
```

## Implementation Checklist

- [ ] Identify which fields are globally unique vs. locally unique
- [ ] Choose delimiter ("|" is common, avoid if it could appear in data)
- [ ] Build composite keys when **storing** selections
- [ ] Build keys using **entry's own scope** when **matching**
- [ ] Test with real data that has duplicates
- [ ] Document key format in comments

## Real-World Examples

**Sports app:** `"{division}|{team_name}"`
**Multi-tenant SaaS:** `"{org_id}|{user_email}"`
**Inventory system:** `"{warehouse}|{sku}"`

## See Also
- `url-parameter-patterns.md` — Encoding composite keys in URLs
