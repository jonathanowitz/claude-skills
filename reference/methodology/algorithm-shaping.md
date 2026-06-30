# Algorithm Shaping

Before implementing any non-trivial algorithm, probe for existing implementations and edge cases.

---

## Prior Art Discovery

**Always ask these questions during shaping:**

1. **Do you have an existing version?**
   - Excel spreadsheet with formulas
   - Notion database with rollups
   - Paper/whiteboard process
   - Previous code implementation
   - Mental model you run manually

2. **Can you walk me through a concrete example?**
   - Use real data, not hypotheticals
   - "If Option A has Cost=Yes, Timeline=No and Option B has Cost=No, Timeline=Yes, which wins?"
   - This reveals the actual algorithm, not assumptions

3. **What does the output look like?**
   - Single winner vs. ranked list vs. tiers
   - Scores shown or hidden
   - Ties allowed or forced resolution

---

## Edge Case Probing

**Standard edge cases to validate:**

| Scenario | Question |
|----------|----------|
| Empty input | What if there are no options/items? |
| Single item | Does one option automatically win? |
| All identical | What if all options have the same values? |
| All fail | What if nothing passes the first filter? |
| Ties | How should ties be displayed/resolved? |
| Partial data | What if some evaluations are missing? |

---

## Algorithm Documentation

After discovering the algorithm, document:

```markdown
## [Algorithm Name]

### Input
- What data does it receive?

### Process
1. Step one
2. Step two
3. ...

### Output
- What does it return?

### Edge Cases
- Empty: [behavior]
- Tie: [behavior]
- Single item: [behavior]

### Example
Input: [concrete example]
Output: [expected result]
Why: [explanation]
```

---

## Red Flags

Watch for these signals that shaping is incomplete:

- "I'll know it when I see it" → Need concrete example walkthrough
- "Just do whatever makes sense" → Need to probe for actual preference
- Multiple valid algorithms → Need to validate which one matches intent
- "That's a good question" → Edge case not yet decided, capture the decision

---

## Validation Checkpoint

Before moving to implementation, confirm:

- [ ] Prior art discovered (or confirmed none exists)
- [ ] Concrete example walked through with real data
- [ ] Edge cases discussed and decisions captured
- [ ] Output format agreed upon
- [ ] Algorithm documented in shaping doc or breadboard
