# Frontend State Patterns

Reference for deciding where state lives and avoiding mid-implementation refactors.

---

## State Location Decision Tree

```
Does only ONE component use this state?
  └─ Yes → Local state (component-level)
  └─ No ↓

Do PARENT and CHILDREN share it?
  └─ Yes → Lift to parent, pass as props
  └─ No ↓

Do SIBLING components share it?
  └─ Yes → Lift to common parent
  └─ No ↓

Do DISTANT components share it?
  └─ Yes → Store/Context pattern
```

---

## Svelte 5 Reactivity Gotchas

### Problem: Functions in reactive blocks don't auto-track

```javascript
// BAD - only triggers when isComplete changes
$: rankedList = isComplete ? calculateRankedList() : [];

// GOOD - explicitly list dependencies
$: {
  dimensions;  // dependency
  options;     // dependency
  evaluations; // dependency
  rankedList = isComplete ? calculateRankedList() : [];
}
```

### Problem: Array/object mutations don't trigger reactivity

```javascript
// BAD - mutation doesn't trigger
items.push(newItem);

// GOOD - reassignment triggers
items = [...items, newItem];
```

### Problem: Nested object changes

```javascript
// BAD - nested change doesn't trigger
evaluations[optionId][dimensionId] = true;

// GOOD - reassign the whole object
evaluations = {
  ...evaluations,
  [optionId]: {
    ...evaluations[optionId],
    [dimensionId]: true
  }
};
```

---

## Common Patterns

### Pattern 1: Lifted State with Callbacks

**Use when:** Parent owns state, children render and emit events

```svelte
<!-- App.svelte -->
<script>
  let items = $state([]);

  function addItem(item) {
    items = [...items, item];
  }

  function deleteItem(id) {
    items = items.filter(i => i.id !== id);
  }
</script>

<ItemList {items} onDelete={deleteItem} />
<AddItemForm onAdd={addItem} />
```

```svelte
<!-- ItemList.svelte -->
<script>
  let { items, onDelete } = $props();
</script>

{#each items as item}
  <div>
    {item.name}
    <button onclick={() => onDelete(item.id)}>Delete</button>
  </div>
{/each}
```

### Pattern 2: Shared Store

**Use when:** Many distant components need the same state

```javascript
// stores.js
import { writable } from 'svelte/store';

export const items = writable([]);

// Helper functions
export function addItem(item) {
  items.update(current => [...current, item]);
}
```

```svelte
<!-- Any component -->
<script>
  import { items, addItem } from './stores.js';
</script>

{#each $items as item}
  ...
{/each}
```

---

## Planning During Breadboarding

When creating the wiring table, note state dependencies:

| ID | Affordance | Reads | Writes |
|----|------------|-------|--------|
| U1 | Add button | - | dimensions |
| U6 | List display | dimensions | - |
| U8 | Delete button | dimensions | dimensions |
| U15 | Eval grid | dimensions, options | evaluations |

**Analysis:**
- `dimensions` read by U6, U15; written by U1, U8 → lives in common parent
- `evaluations` read/written by U15-U19 → could be local to EvaluateTab, but if Results needs it → lift to parent

---

## Anti-Patterns

### Don't: Prop drilling through many layers
If passing props through 3+ components, use a store instead.

### Don't: Duplicate state
If two components both maintain `items`, they'll drift. Single source of truth.

### Don't: Derive state that should be computed
```javascript
// BAD - storing derived state
let total = $state(0);
$: total = items.reduce((sum, i) => sum + i.price, 0);

// GOOD - compute on demand
$: total = items.reduce((sum, i) => sum + i.price, 0);
// (no separate state variable needed)
```
